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


if __name__ == "__main__":
    unittest.main()
