#!/usr/bin/env python3
"""Momentum (kinetic) scrolling for the Apple Magic Mouse on Linux/Wayland.

Why this exists: the kernel's hid_magicmouse driver can either emulate a
scroll wheel from the touch surface (discrete ticks -- no velocity info
survives, so nothing downstream can produce momentum) or expose the raw
multitouch protocol. libinput only runs its two-finger/kinetic-scroll gesture
logic on devices it classifies as a touchpad at the udev level; this device
is classified as a mouse, so the raw touch data is present but libinput never
looks at it for scrolling. There's no config knob that closes that gap --
this process closes it instead.

Approach: grab the physical device exclusively (EVIOCGRAB), forward pointer
motion and button clicks untouched to a synthetic uinput device, drop the
kernel's emulated wheel ticks, and instead compute our own scroll from the
raw ABS_MT touch positions -- live 1:1 while a finger is moving, decaying
into momentum after it lifts (like macOS), cancellable by touching again.

The synthetic device shows up to Hyprland/libinput as an ordinary wheel
mouse, so natural_scroll/scroll_factor/accel_profile still apply normally --
see the "magicmouse-scroll-daemon" hl.device block in ../hypr/input.lua.

If this process isn't running, EVIOCGRAB is released automatically (it's
tied to the fd), so the OS falls back to the kernel's tick-based scrolling
transparently -- there is no scenario where the mouse stops scrolling
because this daemon crashed.
"""

import asyncio
import logging
import time

from evdev import InputDevice, UInput, ecodes as e, list_devices

DEVICE_NAME_SUBSTR = "Magic Mouse"
UINPUT_NAME = "magicmouse-scroll-daemon"

# --- Tuning constants -------------------------------------------------
# Raw ABS_MT_POSITION units of touch movement per REL_WHEEL_HI_RES notch
# (120 units = one logical wheel click). Smaller = more scroll per swipe.
# The touch surface reports position at ~70 units/mm (Y axis resolution),
# so 120 here is roughly one notch per 1.7mm of finger travel.
SCALE = 120.0

TICK_HZ = 60.0
TICK_INTERVAL = 1.0 / TICK_HZ

# Total coast distance/duration are computed once from the release velocity
# via constant-deceleration kinematics -- position(t) = v0*t - 0.5*a*t^2,
# hitting exactly zero velocity at t_stop = v0/a -- rather than decaying
# until an arbitrary velocity threshold. This is the core idea behind
# Android's OverScroller and Chromium's fling curve (verified from their
# real source): a harder flick travels quadratically farther and glides
# proportionally longer, instead of every release just being a bigger
# version of the same exponential-decay shape, and the coast always ends at
# a clean computed stop rather than an indefinite decaying tail.
# Raw ABS_MT_POSITION units per second^2.
DECELERATION = 3000.0

# Hard cap on how long a single coast can run regardless of release speed
# (mirrors Chromium's kMaxCurveDurationForFlinging) -- without this a very
# hard flick would coast for an uncomfortably long time. When this cap
# binds, the effective deceleration is recomputed so velocity still hits
# exactly zero at the cap instead of stopping abruptly mid-motion.
MAX_COAST_DURATION = 1.5

# A release below this velocity doesn't launch momentum at all -- treats a
# deliberate slow stop (resting the finger) like macOS does, instead of
# turning every lift-off into a coast.
FLICK_MIN_VELOCITY = 6.0

# Smoothing factor for the live velocity estimate (higher = more responsive,
# lower = steadier, less prone to launching momentum off one noisy sample).
VELOCITY_EMA_ALPHA = 0.5

# A touch that starts while the mouse was physically moving within this
# many seconds beforehand never counts as a scroll touch for its whole
# lifetime. A deliberate scroll swipe happens with the mouse sitting still
# on the desk; a finger resting on the shell while gripping/dragging the
# mouse around is what this filters out, regardless of where on the shell
# it happens to land.
POINTER_STILL_DEBOUNCE = 0.15

# Raw ABS_MT_POSITION units a touch must travel (cumulative straight-line
# distance from where it landed) before it's treated as a deliberate swipe
# rather than incidental/barely-there contact. Also the main defense (along
# with the debounce above) against a light touch producing scroll output.
ARM_DISTANCE = 100

HI_RES_PER_NOTCH = 120

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
log = logging.getLogger("magicmouse-scroll")


def find_device():
    for path in list_devices():
        dev = InputDevice(path)
        if DEVICE_NAME_SUBSTR in dev.name:
            return dev
        dev.close()
    return None


def make_uinput(source):
    caps = source.capabilities()
    key_codes = caps.get(e.EV_KEY, [])
    events = {
        e.EV_KEY: key_codes,
        e.EV_REL: [
            e.REL_X,
            e.REL_Y,
            e.REL_WHEEL,
            e.REL_HWHEEL,
            e.REL_WHEEL_HI_RES,
            e.REL_HWHEEL_HI_RES,
        ],
    }
    return UInput(events, name=UINPUT_NAME, vendor=0x004C, product=0x0323, version=1)


class ScrollState:
    """Protocol-B multitouch tracking for a single active (scroll) touch."""

    def __init__(self, ui):
        self.ui = ui
        self.current_slot = 0
        # slot -> {"id", "x", "y", "origin_x", "origin_y", "ignored", "armed"}
        self.slots = {}
        self.pending_dx = 0
        self.pending_dy = 0
        self.last_frame_t = None
        self.touching = False
        self.vel_x = 0.0
        self.vel_y = 0.0
        self.accum_hi_x = 0.0
        self.accum_hi_y = 0.0
        self.momentum_task = None
        self.last_pointer_move_t = None

    def note_pointer_move(self):
        self.last_pointer_move_t = time.monotonic()

    def cancel_momentum(self):
        # Matches macOS: moving the pointer (to another window, say) kills
        # an in-flight coast immediately rather than letting it keep
        # scrolling whatever's now under the cursor.
        if self.momentum_task is not None:
            self.momentum_task.cancel()
            self.momentum_task = None

    def primary_slot(self):
        active = [
            s
            for s, info in self.slots.items()
            if info.get("id", -1) != -1 and info.get("armed") and not info.get("ignored")
        ]
        return min(active) if active else None

    def handle_abs(self, code, value):
        if code == e.ABS_MT_SLOT:
            self.current_slot = value
            return
        info = self.slots.setdefault(self.current_slot, {})
        if code == e.ABS_MT_TRACKING_ID:
            if value == -1:
                info.clear()
                info["id"] = -1
            else:
                info.clear()
                info["id"] = value
        elif code == e.ABS_MT_POSITION_X:
            prev = info.get("x")
            info["x"] = value
            self._maybe_arm(info)
            if prev is not None and info.get("armed") and not info.get("ignored"):
                if self.current_slot == self.primary_slot():
                    self.pending_dx += value - prev
        elif code == e.ABS_MT_POSITION_Y:
            prev = info.get("y")
            info["y"] = value
            self._maybe_arm(info)
            if prev is not None and info.get("armed") and not info.get("ignored"):
                if self.current_slot == self.primary_slot():
                    self.pending_dy += value - prev

    def _recently_moved(self):
        return (
            self.last_pointer_move_t is not None
            and time.monotonic() - self.last_pointer_move_t < POINTER_STILL_DEBOUNCE
        )

    def _maybe_arm(self, info):
        if "x" not in info or "y" not in info or info.get("id", -1) == -1:
            return
        if "origin_x" not in info:
            info["origin_x"] = info["x"]
            info["origin_y"] = info["y"]
            info["ignored"] = self._recently_moved()
            info["armed"] = False
            return
        if info.get("armed"):
            return
        if info["ignored"]:
            if self._recently_moved():
                return
            # The debounce window has expired while this touch is still
            # down -- a touch that starts right as the mouse stops moving
            # shouldn't be penalized for the rest of its lifetime just
            # because of when it happened to land. Treat it as a fresh
            # candidate from here, resetting the origin so arming distance
            # is measured from now rather than jumping on the stale delta.
            info["ignored"] = False
            info["origin_x"] = info["x"]
            info["origin_y"] = info["y"]
            return
        dist = ((info["x"] - info["origin_x"]) ** 2 + (info["y"] - info["origin_y"]) ** 2) ** 0.5
        if dist >= ARM_DISTANCE:
            info["armed"] = True

    def handle_syn(self):
        primary = self.primary_slot()
        now = time.monotonic()

        if primary is not None:
            if self.momentum_task is not None:
                self.momentum_task.cancel()
                self.momentum_task = None
            self.touching = True

            dt = (now - self.last_frame_t) if self.last_frame_t else TICK_INTERVAL
            dt = max(dt, 1e-3)

            if self.pending_dx or self.pending_dy:
                self.emit_scroll(self.pending_dx, self.pending_dy)
                inst_vx = self.pending_dx / dt * TICK_INTERVAL
                inst_vy = self.pending_dy / dt * TICK_INTERVAL
                self.vel_x = VELOCITY_EMA_ALPHA * inst_vx + (1 - VELOCITY_EMA_ALPHA) * self.vel_x
                self.vel_y = VELOCITY_EMA_ALPHA * inst_vy + (1 - VELOCITY_EMA_ALPHA) * self.vel_y
                self.pending_dx = 0
                self.pending_dy = 0
        elif self.touching:
            self.touching = False
            speed = (self.vel_x ** 2 + self.vel_y ** 2) ** 0.5
            if speed >= FLICK_MIN_VELOCITY:
                self.momentum_task = asyncio.ensure_future(self.coast(self.vel_x, self.vel_y))
            self.vel_x = 0.0
            self.vel_y = 0.0

        self.last_frame_t = now

    def emit_scroll(self, dx, dy):
        # ABS_MT_POSITION_Y increases downward (finger moving down the
        # shell). Hyprland's natural_scroll on the synthetic device didn't
        # actually invert this in testing, so the flip is done explicitly
        # here instead: swipe down -> scroll up, matching macOS.
        self.accum_hi_x += dx / SCALE * HI_RES_PER_NOTCH
        self.accum_hi_y += -dy / SCALE * HI_RES_PER_NOTCH
        self._flush_hi_res()

    def _flush_hi_res(self):
        ix = int(self.accum_hi_x)
        iy = int(self.accum_hi_y)
        if ix:
            self.accum_hi_x -= ix
            self.ui.write(e.EV_REL, e.REL_HWHEEL_HI_RES, ix)
        if iy:
            self.accum_hi_y -= iy
            self.ui.write(e.EV_REL, e.REL_WHEEL_HI_RES, iy)
        if ix or iy:
            self._flush_legacy(ix, iy)
            self.ui.syn()

    def _flush_legacy(self, hi_x, hi_y):
        # Emit legacy REL_WHEEL/REL_HWHEEL too, scaled down, for anything
        # that only understands the non-hi-res wheel axis.
        self._legacy_x = getattr(self, "_legacy_x", 0.0) + hi_x
        self._legacy_y = getattr(self, "_legacy_y", 0.0) + hi_y
        lx = int(self._legacy_x / HI_RES_PER_NOTCH)
        ly = int(self._legacy_y / HI_RES_PER_NOTCH)
        if lx:
            self._legacy_x -= lx * HI_RES_PER_NOTCH
            self.ui.write(e.EV_REL, e.REL_HWHEEL, lx)
        if ly:
            self._legacy_y -= ly * HI_RES_PER_NOTCH
            self.ui.write(e.EV_REL, e.REL_WHEEL, ly)

    async def coast(self, vx0, vy0):
        # Position is integrated analytically from real elapsed time
        # (dist(t) = v0*t - 0.5*a*t^2, the constant-deceleration solution of
        # v' = -a) rather than stepping per tick, so a late/early
        # asyncio.sleep wakeup changes *when* a frame lands but not the
        # total distance/duration of the coast.
        speed0 = (vx0 * vx0 + vy0 * vy0) ** 0.5
        if speed0 < 1e-9:
            self.momentum_task = None
            return
        ux, uy = vx0 / speed0, vy0 / speed0
        speed0_per_sec = speed0 * TICK_HZ

        t_stop = speed0_per_sec / DECELERATION
        decel = DECELERATION
        if t_stop > MAX_COAST_DURATION:
            t_stop = MAX_COAST_DURATION
            decel = speed0_per_sec / t_stop  # still hits zero velocity exactly at t_stop

        start = time.monotonic()
        last_dist = 0.0
        try:
            while True:
                elapsed = time.monotonic() - start
                if elapsed >= t_stop:
                    break
                dist = speed0_per_sec * elapsed - 0.5 * decel * elapsed * elapsed
                delta = dist - last_dist
                last_dist = dist
                self.emit_scroll(ux * delta, uy * delta)
                await asyncio.sleep(TICK_INTERVAL)
        except asyncio.CancelledError:
            pass
        finally:
            self.momentum_task = None


async def run():
    while True:
        source = find_device()
        if source is None:
            await asyncio.sleep(1.0)
            continue

        log.info("found %s, grabbing exclusively", source.path)
        source.grab()
        ui = make_uinput(source)
        state = ScrollState(ui)

        try:
            async for event in source.async_read_loop():
                if event.type == e.EV_REL and event.code in (
                    e.REL_WHEEL,
                    e.REL_HWHEEL,
                    e.REL_WHEEL_HI_RES,
                    e.REL_HWHEEL_HI_RES,
                ):
                    continue  # drop kernel's emulated wheel ticks
                if event.type == e.EV_REL:
                    if event.code in (e.REL_X, e.REL_Y) and event.value:
                        state.cancel_momentum()
                        state.note_pointer_move()
                    ui.write(e.EV_REL, event.code, event.value)
                elif event.type == e.EV_KEY:
                    ui.write(e.EV_KEY, event.code, event.value)
                elif event.type == e.EV_ABS:
                    state.handle_abs(event.code, event.value)
                elif event.type == e.EV_SYN and event.code == e.SYN_REPORT:
                    state.handle_syn()
                    ui.syn()
        except OSError:
            log.warning("device disappeared, will rediscover")
        finally:
            if state.momentum_task:
                state.momentum_task.cancel()
            ui.close()
            try:
                source.ungrab()
            except OSError:
                pass
            source.close()


if __name__ == "__main__":
    asyncio.run(run())
