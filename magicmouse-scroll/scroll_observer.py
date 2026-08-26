#!/usr/bin/env python3
"""Expose Magic Mouse surface scrolling as a native libinput touchpad.

The physical mouse is never grabbed. Hyprland continues to receive its
pointer motion and buttons directly from hid-magicmouse; this process only
observes multitouch coordinates and emits two-finger touchpad scroll gestures.

Momentum is synthesized here: when the finger lifts, the daemon emits
rapidly decaying scroll moves so that Chrome sees continuous velocity and
multiple quick swipes coalesce into one continuous gesture without the
pad.begin() interrupting an active kinetic fling.

One finger scrolls. Two or more are left alone for magic-mouse-gestures, which
watches the same surface over hidraw and maps horizontal swipes to Alt+Left and
Alt+Right; without that split, a two-finger flick would scroll and navigate back
on the one motion.
"""

import asyncio
import collections
import logging
import math
import os
import signal
import time

from evdev import AbsInfo, InputDevice, UInput, ecodes as e, list_devices

# Matched by USB/Bluetooth ID, not name: the Bluetooth alias is user-editable
# and renaming the mouse silently stopped this daemon from finding it. 0x004C is
# Apple over Bluetooth, 0x05AC over USB; 0x0269 is the Magic Mouse 2 and 0x030D
# the original. Name matching stays as a fallback for models not listed here.
MOUSE_IDS = frozenset(
    (vendor, product)
    for vendor in (0x004C, 0x05AC)
    for product in (0x0269, 0x030D)
)
DEVICE_NAME_SUBSTR = "Magic Mouse"

# Fingers beyond this belong to the gesture daemon, not to scrolling.
MAX_SCROLL_CONTACTS = 1
TOUCHPAD_NAME = "magicmouse-scroll-touchpad"
MOUSE_BUTTONS = {e.BTN_LEFT, e.BTN_RIGHT, e.BTN_MIDDLE}

SCROLL_START_MM = 0.7
SCROLL_START_WINDOW = 0.25
SCROLL_IDLE_TIMEOUT = 0.12
SIGNIFICANT_MOTION_MM = 0.05
MAX_FRAME_MM = 3.0
SPEED_CAP_MM = 3.5
REVERSAL_MIN_MM = 0.4
MOMENTUM_INTERVAL = 0.016
MOMENTUM_DECAY = 3.0
MOMENTUM_MIN_VEL = 0.05

SOURCE_RES_X = 26.0
SOURCE_RES_Y = 70.0

# Large virtual surface so the gesture never saturates at the edge.
# Resolution matches the Dell XPS 14 touchpad so scroll speed is realistic.
PAD_MAX_X = 200000
PAD_MAX_Y = 200000
PAD_RES_X = 32
PAD_RES_Y = 31
PAD_CENTER_X = PAD_MAX_X // 2
PAD_CENTER_Y = PAD_MAX_Y // 2
PAD_FINGER_GAP = 320

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
log = logging.getLogger("magicmouse-scroll-observer")


def has_multitouch(device):
    return e.ABS_MT_POSITION_X in {
        code for code, _ in device.capabilities().get(e.EV_ABS, [])
    }


def find_device():
    fallback = None
    for device_path in list_devices():
        device = InputDevice(device_path)
        if not has_multitouch(device):
            device.close()
            continue
        if (device.info.vendor, device.info.product) in MOUSE_IDS:
            if fallback is not None:
                fallback.close()
            return device
        if DEVICE_NAME_SUBSTR in device.name and fallback is None:
            fallback = device
            continue
        device.close()
    return fallback


def make_touchpad():
    abs_x = AbsInfo(0, 0, PAD_MAX_X, 0, 0, PAD_RES_X)
    abs_y = AbsInfo(0, 0, PAD_MAX_Y, 0, 0, PAD_RES_Y)
    return UInput(
        {
            e.EV_KEY: [e.BTN_LEFT, e.BTN_TOUCH, e.BTN_TOOL_FINGER, e.BTN_TOOL_DOUBLETAP],
            e.EV_ABS: [
                (e.ABS_X, abs_x),
                (e.ABS_Y, abs_y),
                (e.ABS_MT_SLOT, AbsInfo(0, 0, 1, 0, 0, 0)),
                (e.ABS_MT_TRACKING_ID, AbsInfo(0, 0, 65535, 0, 0, 0)),
                (e.ABS_MT_POSITION_X, abs_x),
                (e.ABS_MT_POSITION_Y, abs_y),
            ],
        },
        name=TOUCHPAD_NAME,
        vendor=0x2C2F,
        product=0x0034,
        version=3,
        input_props=[e.INPUT_PROP_POINTER, e.INPUT_PROP_BUTTONPAD],
    )


class VirtualTouchpad:
    def __init__(self, ui):
        self.ui = ui
        self.active = False
        self.x = float(PAD_CENTER_X)
        self.y = float(PAD_CENTER_Y)
        self.tracking_id = 1

    def _finger(self, slot, tracking_id=None):
        self.ui.write(e.EV_ABS, e.ABS_MT_SLOT, slot)
        if tracking_id is not None:
            self.ui.write(e.EV_ABS, e.ABS_MT_TRACKING_ID, tracking_id)
        offset = -PAD_FINGER_GAP / 2 if slot == 0 else PAD_FINGER_GAP / 2
        self.ui.write(e.EV_ABS, e.ABS_MT_POSITION_X, round(self.x + offset))
        self.ui.write(e.EV_ABS, e.ABS_MT_POSITION_Y, round(self.y))

    def begin(self):
        if self.active:
            return
        self.x = float(PAD_CENTER_X)
        self.y = float(PAD_CENTER_Y)
        first = self.tracking_id
        self.tracking_id += 2
        self.ui.write(e.EV_KEY, e.BTN_TOUCH, 1)
        self.ui.write(e.EV_KEY, e.BTN_TOOL_DOUBLETAP, 1)
        self._finger(0, first)
        self._finger(1, first + 1)
        self.ui.write(e.EV_ABS, e.ABS_X, round(self.x))
        self.ui.write(e.EV_ABS, e.ABS_Y, round(self.y))
        self.ui.syn()
        self.active = True

    def move_raw(self, dx, dy):
        if not self.active:
            return
        self.x += dx / SOURCE_RES_X * PAD_RES_X
        self.y += dy / SOURCE_RES_Y * PAD_RES_Y
        self.x = min(max(self.x, PAD_FINGER_GAP), PAD_MAX_X - PAD_FINGER_GAP)
        self.y = min(max(self.y, 1), PAD_MAX_Y - 1)
        self._finger(0)
        self._finger(1)
        self.ui.write(e.EV_ABS, e.ABS_X, round(self.x))
        self.ui.write(e.EV_ABS, e.ABS_Y, round(self.y))
        self.ui.syn()

    def end(self):
        if not self.active:
            return
        for slot in (0, 1):
            self.ui.write(e.EV_ABS, e.ABS_MT_SLOT, slot)
            self.ui.write(e.EV_ABS, e.ABS_MT_TRACKING_ID, -1)
        self.ui.write(e.EV_KEY, e.BTN_TOOL_DOUBLETAP, 0)
        self.ui.write(e.EV_KEY, e.BTN_TOUCH, 0)
        self.ui.syn()
        self.active = False


TRACE_CAPACITY = 6000  # ~30s at 200 Hz
TRACE_DIR = os.path.join(
    os.environ.get("XDG_RUNTIME_DIR", "/tmp"),
    "magicmouse-scroll-traces",
)
TRACE_LATEST = os.path.join(
    os.environ.get("XDG_RUNTIME_DIR", "/tmp"),
    "magicmouse-scroll-trace.log",
)
ANOMALY_MOTION_MM = 5.0
ANOMALY_COOLDOWN = 5.0
trace_buf = collections.deque(maxlen=TRACE_CAPACITY)
last_anomaly_dump = 0.0
anomaly_dump_count = 0


def dump_trace(reason="manual", signum=None, frame=None):
    global anomaly_dump_count
    anomaly_dump_count += 1
    wall = time.strftime("%Y-%m-%d %H:%M:%S")
    os.makedirs(TRACE_DIR, exist_ok=True)
    numbered = os.path.join(TRACE_DIR, f"trace-{anomaly_dump_count:04d}.log")
    try:
        with open(numbered, "w") as f:
            f.write(f"# dumped at {wall}  reason={reason}  ({len(trace_buf)} frames)\n")
            f.write("# evt_t wall_t slot contacts scrolling buttons point prev dx dy motion action\n")
            for line in trace_buf:
                f.write(line)
                f.write("\n")
        try:
            if os.path.islink(TRACE_LATEST) or os.path.exists(TRACE_LATEST):
                os.unlink(TRACE_LATEST)
            os.symlink(numbered, TRACE_LATEST)
        except OSError:
            pass
        log.info("trace #%d dumped to %s  reason=%s (%d frames)",
                 anomaly_dump_count, numbered, reason, len(trace_buf))
    except OSError as exc:
        log.warning("trace dump failed: %s", exc)


def _handle_sigusr1(signum, frame):
    dump_trace(reason="SIGUSR1")


signal.signal(signal.SIGUSR1, _handle_sigusr1)


def check_anomaly(motion_mm):
    global last_anomaly_dump
    if motion_mm < ANOMALY_MOTION_MM:
        return
    now = time.monotonic()
    if now - last_anomaly_dump < ANOMALY_COOLDOWN:
        return
    last_anomaly_dump = now
    dump_trace(reason=f"anomaly:motion={motion_mm:.1f}mm")


class ScrollEngine:
    def __init__(self, pad):
        self.pad = pad
        self.current_slot = 0
        self.slots = {}
        self.contact_slot = None
        self.origin = None
        self.previous = None
        self.origin_t = None
        self.scrolling = False
        self.last_motion_t = None
        self.buttons_down = set()
        self.prev_dx = 0.0
        self.prev_dy = 0.0
        self._momentum_handle = None
        self._momentum_vx = 0.0
        self._momentum_vy = 0.0

    def _cancel_momentum(self):
        if self._momentum_handle is not None:
            self._momentum_handle.cancel()
            self._momentum_handle = None

    def on_focus_change(self):
        if self._momentum_handle is not None:
            self._end_gesture()

    def _start_momentum(self):
        self._cancel_momentum()
        self._momentum_vx = self.prev_dx
        self._momentum_vy = self.prev_dy
        self._emit_momentum()

    def _emit_momentum(self):
        self._momentum_handle = None
        decay = math.exp(-MOMENTUM_DECAY * MOMENTUM_INTERVAL)
        self._momentum_vx *= decay
        self._momentum_vy *= decay
        vel = math.hypot(self._momentum_vx / SOURCE_RES_X,
                         self._momentum_vy / SOURCE_RES_Y)
        if vel < MOMENTUM_MIN_VEL or not self.scrolling:
            self._end_gesture()
            return
        self.pad.move_raw(self._momentum_vx, self._momentum_vy)
        loop = asyncio.get_running_loop()
        self._momentum_handle = loop.call_later(
            MOMENTUM_INTERVAL, self._emit_momentum)

    def _end_gesture(self):
        self._cancel_momentum()
        self.pad.end()
        self.contact_slot = None
        self.origin = None
        self.previous = None
        self.origin_t = None
        self.scrolling = False
        self.last_motion_t = None
        self.prev_dx = 0.0
        self.prev_dy = 0.0

    def handle_abs(self, code, value):
        if code == e.ABS_MT_SLOT:
            self.current_slot = value
            return
        info = self.slots.setdefault(self.current_slot, {"id": -1})
        if code == e.ABS_MT_TRACKING_ID:
            info.clear()
            info["id"] = value
        elif code == e.ABS_MT_POSITION_X:
            info["x"] = value
        elif code == e.ABS_MT_POSITION_Y:
            info["y"] = value

    def handle_button(self, code, value):
        if value:
            self.buttons_down.add(code)
            self._end_gesture()
        else:
            self.buttons_down.discard(code)
            if not self.buttons_down:
                self._end_gesture()

    def contacts(self):
        return [
            (slot, info)
            for slot, info in self.slots.items()
            if info.get("id", -1) != -1 and "x" in info and "y" in info
        ]

    def primary(self):
        return min(self.contacts(), default=(None, None))

    def _trace(self, now, point, dx, dy, motion, action):
        wall = time.monotonic()
        prev = self.previous or (0, 0)
        trace_buf.append(
            f"{now:.6f} {wall:.4f} {self.contact_slot} "
            f"{len(self.contacts())} {int(self.scrolling)} "
            f"{len(self.buttons_down)} "
            f"{point[0]},{point[1]} {prev[0]},{prev[1]} "
            f"{dx:+.1f} {dy:+.1f} {motion:.3f} {action}"
        )

    def frame(self, now):
        if self.buttons_down:
            return
        nc = len(self.contacts())
        if nc > MAX_SCROLL_CONTACTS:
            self._trace(now, (0, 0), 0, 0, 0, f"reset:multi({nc})")
            self._end_gesture()
            return
        slot, info = self.primary()
        if info is None:
            if self.scrolling and self._momentum_handle is None:
                self._start_momentum()
            elif not self.scrolling:
                self._end_gesture()
            return
        self._cancel_momentum()
        point = (info["x"], info["y"])
        if slot != self.contact_slot:
            if self.scrolling:
                self._trace(now, point, 0, 0, 0, f"slot_carry:slot{slot}")
                self.contact_slot = slot
                self.previous = point
                self.prev_dx = 0.0
                self.prev_dy = 0.0
                self.last_motion_t = now
                return
            self._trace(now, point, 0, 0, 0, f"new_contact:slot{slot}")
            self._end_gesture()
            self.contact_slot = slot
            self.origin = self.previous = point
            self.origin_t = now
            return
        if not self.scrolling:
            if now - self.origin_t > SCROLL_START_WINDOW:
                self._trace(now, point, 0, 0, 0, "origin_reset")
                self.origin = self.previous = point
                self.origin_t = now
                return
            distance = math.hypot(
                (point[0] - self.origin[0]) / SOURCE_RES_X,
                (point[1] - self.origin[1]) / SOURCE_RES_Y,
            )
            if distance >= SCROLL_START_MM:
                self._trace(now, point, 0, 0, distance, "scroll_begin")
                self.scrolling = True
                self.last_motion_t = now
                self.pad.begin()
                self.previous = point
            return
        dx = point[0] - self.previous[0]
        dy = point[1] - self.previous[1]
        motion = math.hypot(dx / SOURCE_RES_X, dy / SOURCE_RES_Y)
        if motion < SIGNIFICANT_MOTION_MM and now - self.last_motion_t >= SCROLL_IDLE_TIMEOUT:
            self._trace(now, point, dx, dy, motion, "scroll_end:idle")
            self._start_momentum()
            return
        if motion < SIGNIFICANT_MOTION_MM:
            self.previous = point
            return
        if dx or dy:
            if motion > MAX_FRAME_MM:
                check_anomaly(motion)
            prev_motion = math.hypot(self.prev_dx / SOURCE_RES_X,
                                     self.prev_dy / SOURCE_RES_Y)
            if (motion >= REVERSAL_MIN_MM and prev_motion >= REVERSAL_MIN_MM
                    and self.prev_dx * dx + self.prev_dy * dy < 0):
                self._trace(now, point, dx, dy, motion, "reversal")
                self.previous = point
                self.last_motion_t = now
                self.prev_dx = float(dx)
                self.prev_dy = float(dy)
                return
            if motion > SPEED_CAP_MM:
                scale = SPEED_CAP_MM / motion
                edx = dx * scale
                edy = dy * scale
                self._trace(now, point, dx, dy, motion, f"cap:{motion:.2f}")
                self.pad.move_raw(edx, edy)
                self.prev_dx = edx
                self.prev_dy = edy
            else:
                self._trace(now, point, dx, dy, motion, "move")
                self.pad.move_raw(dx, dy)
                self.prev_dx = float(dx)
                self.prev_dy = float(dy)
            self.previous = point
            if motion >= SIGNIFICANT_MOTION_MM:
                self.last_motion_t = now

    def reset(self):
        self._end_gesture()
        self.slots.clear()
        self.current_slot = 0
        self.buttons_down.clear()


def _hypr_socket_path():
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    xdg = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
    return os.path.join(xdg, "hypr", sig, ".socket2.sock")


async def watch_focus(engine):
    path = _hypr_socket_path()
    while True:
        try:
            reader, _ = await asyncio.open_unix_connection(path)
            while True:
                line = await reader.readline()
                if not line:
                    break
                if line.startswith(b"activewindow>>"):
                    engine.on_focus_change()
        except (OSError, ConnectionError):
            await asyncio.sleep(2)


async def run():
    while True:
        source = find_device()
        if source is None:
            await asyncio.sleep(1)
            continue
        log.info("observing %s without grabbing", source.path)
        touchpad_ui = make_touchpad()
        engine = ScrollEngine(VirtualTouchpad(touchpad_ui))
        focus_task = asyncio.create_task(watch_focus(engine))
        dropping = False
        try:
            async for event in source.async_read_loop():
                if event.type == e.EV_SYN and event.code == e.SYN_DROPPED:
                    trace_buf.append(
                        f"{event.timestamp():.6f} {time.monotonic():.4f} "
                        f"- - - - - - +0 +0 0 SYN_DROPPED"
                    )
                    dropping = True
                    engine.reset()
                    continue
                if dropping:
                    if event.type == e.EV_SYN and event.code == e.SYN_REPORT:
                        dropping = False
                    continue
                if event.type == e.EV_ABS:
                    engine.handle_abs(event.code, event.value)
                elif event.type == e.EV_KEY and event.code in MOUSE_BUTTONS:
                    engine.handle_button(event.code, event.value)
                elif event.type == e.EV_SYN and event.code == e.SYN_REPORT:
                    engine.frame(event.timestamp())
        except OSError:
            log.warning("device disappeared, will rediscover")
        finally:
            focus_task.cancel()
            engine.reset()
            touchpad_ui.close()
            source.close()


if __name__ == "__main__":
    asyncio.run(run())
