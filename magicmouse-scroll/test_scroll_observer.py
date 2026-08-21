import importlib.util
from pathlib import Path
import unittest

from evdev import ecodes as e

SPEC = importlib.util.spec_from_file_location("scroll_observer", Path(__file__).with_name("scroll_observer.py"))
observer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(observer)


class Clock:
    def __init__(self):
        self.now = 1.0

    def __call__(self):
        return self.now


class Pad:
    def __init__(self):
        self.active = False
        self.moves = []

    def begin(self):
        self.active = True

    def move_raw(self, dx, dy):
        self.moves.append((dx, dy))

    def end(self):
        self.active = False


def contact(engine, y):
    engine.handle_abs(e.ABS_MT_SLOT, 0)
    engine.handle_abs(e.ABS_MT_TRACKING_ID, 1)
    engine.handle_abs(e.ABS_MT_POSITION_X, 0)
    engine.handle_abs(e.ABS_MT_POSITION_Y, y)
    engine.frame()


class ScrollEngineTests(unittest.TestCase):
    def test_surface_motion_starts_touchpad_scroll(self):
        pad = Pad()
        engine = observer.ScrollEngine(pad, Clock())
        contact(engine, 0)
        engine.handle_abs(e.ABS_MT_POSITION_Y, observer.SOURCE_RES_Y)
        engine.frame()
        self.assertTrue(engine.scrolling)
        self.assertTrue(pad.active)

    def test_physical_button_cancels_scroll_without_forwarding_it(self):
        pad = Pad()
        engine = observer.ScrollEngine(pad, Clock())
        contact(engine, 0)
        engine.handle_abs(e.ABS_MT_POSITION_Y, observer.SOURCE_RES_Y)
        engine.frame()

        engine.handle_button(e.BTN_RIGHT, 1)

        self.assertFalse(engine.scrolling)
        self.assertFalse(pad.active)
        self.assertEqual(engine.buttons_down, {e.BTN_RIGHT})

    def test_button_hold_blocks_centroid_motion_from_scrolling(self):
        pad = Pad()
        engine = observer.ScrollEngine(pad, Clock())
        engine.handle_button(e.BTN_LEFT, 1)
        contact(engine, 0)
        engine.handle_abs(e.ABS_MT_POSITION_Y, observer.SOURCE_RES_Y * 2)
        engine.frame()
        self.assertFalse(engine.scrolling)


    def test_second_finger_hands_motion_to_the_gesture_daemon(self):
        pad = Pad()
        engine = observer.ScrollEngine(pad, Clock())
        contact(engine, 0)
        engine.handle_abs(e.ABS_MT_POSITION_Y, observer.SOURCE_RES_Y)
        engine.frame()
        self.assertTrue(engine.scrolling)

        engine.handle_abs(e.ABS_MT_SLOT, 1)
        engine.handle_abs(e.ABS_MT_TRACKING_ID, 2)
        engine.handle_abs(e.ABS_MT_POSITION_X, 0)
        engine.handle_abs(e.ABS_MT_POSITION_Y, 0)
        engine.frame()
        self.assertFalse(engine.scrolling)
        self.assertFalse(pad.active)

        emitted = len(pad.moves)
        engine.handle_abs(e.ABS_MT_POSITION_Y, observer.SOURCE_RES_Y * 3)
        engine.frame()
        self.assertEqual(len(pad.moves), emitted)


class FakeInfo:
    def __init__(self, vendor, product):
        self.vendor = vendor
        self.product = product


class FakeDevice:
    def __init__(self, path, name, vendor, product, multitouch=True):
        self.path = path
        self.name = name
        self.info = FakeInfo(vendor, product)
        self.multitouch = multitouch
        self.closed = False

    def capabilities(self):
        codes = []
        if self.multitouch:
            codes = [(e.ABS_MT_POSITION_X, None), (e.ABS_MT_POSITION_Y, None)]
        return {e.EV_ABS: codes}

    def close(self):
        self.closed = True


class FindDeviceTests(unittest.TestCase):
    def find_among(self, devices):
        by_path = {device.path: device for device in devices}
        saved = observer.list_devices, observer.InputDevice
        observer.list_devices = lambda: list(by_path)
        observer.InputDevice = lambda path: by_path[path]
        try:
            return observer.find_device()
        finally:
            observer.list_devices, observer.InputDevice = saved

    def test_renamed_mouse_is_still_found_by_id(self):
        # Regression: the Bluetooth alias is user-editable, and matching on the
        # name "Magic Mouse" meant renaming the mouse stopped scrolling working.
        mouse = FakeDevice("/dev/input/event23", "Dark Work Mouse", 0x004C, 0x0269)
        noise = FakeDevice("/dev/input/event0", "AT keyboard", 0x0001, 0x0001, multitouch=False)
        self.assertIs(self.find_among([noise, mouse]), mouse)

    def test_apple_device_without_multitouch_is_ignored(self):
        keyboard = FakeDevice(
            "/dev/input/event7", "Silver Apple Keyboard", 0x004C, 0x0322, multitouch=False
        )
        self.assertIsNone(self.find_among([keyboard]))

    def test_unrelated_devices_are_closed(self):
        noise = FakeDevice("/dev/input/event0", "AT keyboard", 0x0001, 0x0001, multitouch=False)
        mouse = FakeDevice("/dev/input/event23", "Dark Work Mouse", 0x004C, 0x0269)
        self.find_among([noise, mouse])
        self.assertTrue(noise.closed)
        self.assertFalse(mouse.closed)


if __name__ == "__main__":
    unittest.main()
