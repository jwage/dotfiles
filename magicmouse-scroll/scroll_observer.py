#!/usr/bin/env python3
"""Expose Magic Mouse surface scrolling as a native libinput touchpad.

The physical mouse is never grabbed. Hyprland continues to receive its
pointer motion and buttons directly from hid-magicmouse; this process only
observes multitouch coordinates and emits two-finger touchpad scroll gestures.

Momentum is deliberately not synthesized here. Replaying the surface as a real
multitouch touchpad means libinput reports finger-source scroll with a genuine
touch-end, so GTK/Chromium/Qt apply their own kinetic scrolling -- the same code
path that gives a laptop trackpad its fling.

One finger scrolls. Two or more are left alone for magic-mouse-gestures, which
watches the same surface over hidraw and maps horizontal swipes to Alt+Left and
Alt+Right; without that split, a two-finger flick would scroll and navigate back
on the one motion.
"""

import asyncio
import logging
import math
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

SOURCE_RES_X = 26.0
SOURCE_RES_Y = 70.0

# Match the Dell XPS 14 touchpad's measured geometry.
PAD_MAX_X = 4723
PAD_MAX_Y = 2298
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


class ScrollEngine:
    def __init__(self, pad, clock=time.monotonic):
        self.pad = pad
        self.clock = clock
        self.current_slot = 0
        self.slots = {}
        self.contact_slot = None
        self.origin = None
        self.previous = None
        self.origin_t = None
        self.scrolling = False
        self.last_motion_t = None
        self.buttons_down = set()

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
            self.reset_contact()
        else:
            self.buttons_down.discard(code)
            if not self.buttons_down:
                self.reset_contact()

    def contacts(self):
        return [
            (slot, info)
            for slot, info in self.slots.items()
            if info.get("id", -1) != -1 and "x" in info and "y" in info
        ]

    def primary(self):
        return min(self.contacts(), default=(None, None))

    def frame(self):
        if self.buttons_down:
            return
        if len(self.contacts()) > MAX_SCROLL_CONTACTS:
            # Hand multi-finger motion to the gesture daemon untouched.
            self.reset_contact()
            return
        slot, info = self.primary()
        if info is None:
            self.reset_contact()
            return
        point = (info["x"], info["y"])
        if slot != self.contact_slot:
            self.reset_contact()
            self.contact_slot = slot
            self.origin = self.previous = point
            self.origin_t = self.clock()
            return
        if not self.scrolling:
            if self.clock() - self.origin_t > SCROLL_START_WINDOW:
                self.origin = self.previous = point
                self.origin_t = self.clock()
                return
            distance = math.hypot(
                (point[0] - self.origin[0]) / SOURCE_RES_X,
                (point[1] - self.origin[1]) / SOURCE_RES_Y,
            )
            if distance >= SCROLL_START_MM:
                self.scrolling = True
                self.last_motion_t = self.clock()
                self.pad.begin()
                self.previous = point
            return
        dx = point[0] - self.previous[0]
        dy = point[1] - self.previous[1]
        motion = math.hypot(dx / SOURCE_RES_X, dy / SOURCE_RES_Y)
        if motion < SIGNIFICANT_MOTION_MM and self.clock() - self.last_motion_t >= SCROLL_IDLE_TIMEOUT:
            self.end_scroll_at(point)
            return
        if dx or dy:
            self.pad.move_raw(dx, dy)
            self.previous = point
            if motion >= SIGNIFICANT_MOTION_MM:
                self.last_motion_t = self.clock()

    def end_scroll_at(self, point):
        self.pad.end()
        self.scrolling = False
        self.last_motion_t = None
        self.origin = self.previous = point
        self.origin_t = self.clock()

    def reset_contact(self):
        self.pad.end()
        self.contact_slot = None
        self.origin = None
        self.previous = None
        self.origin_t = None
        self.scrolling = False
        self.last_motion_t = None

    def reset(self):
        self.reset_contact()
        self.slots.clear()
        self.current_slot = 0
        self.buttons_down.clear()


async def run():
    while True:
        source = find_device()
        if source is None:
            await asyncio.sleep(1)
            continue
        log.info("observing %s without grabbing", source.path)
        touchpad_ui = make_touchpad()
        engine = ScrollEngine(VirtualTouchpad(touchpad_ui))
        dropping = False
        try:
            async for event in source.async_read_loop():
                if event.type == e.EV_SYN and event.code == e.SYN_DROPPED:
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
                    engine.frame()
        except OSError:
            log.warning("device disappeared, will rediscover")
        finally:
            engine.reset()
            touchpad_ui.close()
            source.close()


if __name__ == "__main__":
    asyncio.run(run())
