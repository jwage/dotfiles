-- Keep only your personal input overrides here. Uncommented settings below
-- replace Omarchy's defaults.

-- Keyboard layout and options.
-- See https://wiki.hypr.land/Configuring/Basics/Variables/#input
hl.config({
  input = {
    -- Invert mouse scroll direction to match macOS "natural" scrolling.
    natural_scroll = true,

    touchpad = {
      -- Invert touchpad scroll direction to match macOS "natural" scrolling.
      natural_scroll = true,
    },
  },
})

-- hl.config({
--   input = {
--     -- Use multiple keyboard layouts and switch between them with Left Alt + Right Alt.
--     kb_layout = "us,dk,eu",
--     kb_options = "compose:caps,shift:both_capslock_cancel,grp:alts_toggle",
--
--     -- Use a specific keyboard variant if needed (e.g. intl for international keyboards).
--     kb_variant = "intl",
--
--     -- Change speed of keyboard repeat.
--     repeat_rate = 40,
--     repeat_delay = 250,
--
--     -- Start with numlock on by default.
--     numlock_by_default = true,
--
--     -- Increase sensitivity for mouse/trackpad (default: 0).
--     sensitivity = 0.35,
--
--     -- Turn off mouse acceleration (default: adaptive).
--     accel_profile = "flat",
--
--     touchpad = {
--       -- Use natural (inverse) scrolling.
--       natural_scroll = true,
--
--       -- Use two-finger clicks for right-click instead of lower-right corner.
--       clickfinger_behavior = true,
--
--       -- Control the speed of your scrolling.
--       scroll_factor = 0.4,
--
--       -- Enable the touchpad while typing.
--       disable_while_typing = false,
--
--       -- Left-click-and-drag with three fingers.
--       drag_3fg = 1,
--     },
--   },
-- })

-- Swap Alt and Super on the Dell XPS 14's built-in keyboard so the key next
-- to the spacebar sends Super. This matches where Cmd sits on a real Mac and
-- on the Apple "Magic Keyboard" (which already maps Cmd -> Super and
-- Option -> Alt via the hid_apple driver defaults, so it needs no override).
-- Without this, the same physical reach (key next to spacebar) would fire
-- Alt on the laptop keyboard but Super everywhere else.
hl.device({
  name = "at-translated-set-2-keyboard",
  kb_options = "compose:caps,shift:both_capslock_cancel,altwin:swap_alt_win",
})

-- The virtual touchpad that magicmouse-scroll emits Magic Mouse surface
-- scrolling through. Replaying the surface as a real multitouch touchpad is
-- what buys momentum: libinput then reports finger-source scroll with a true
-- touch-end, so GTK/Chromium/Qt apply their own kinetic fling. The kernel's
-- own wheel emulation (emulate_scroll_wheel) is off so the two do not stack.
--
-- It must have no click path. Omarchy enables touchpad tapping globally, and
-- this device's scroll gestures are a generated two-finger sequence that
-- tapping would turn into stray clicks. The physical mouse keeps providing
-- every button directly; nothing here recreates or delays a click.
hl.device({
  name = "magicmouse-scroll-touchpad",
  tap_to_click = false,
  tap_and_drag = false,
  clickfinger_behavior = false,
})

-- App-specific touchpad scroll speeds.
-- o.window("(Alacritty|kitty|foot)", { scroll_touchpad = 1.5 })
-- o.window("com.mitchellh.ghostty", { scroll_touchpad = 0.2 })

-- Enable touchpad gestures for changing workspaces.
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Gestures/
-- hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

-- Enable touchpad gestures for moving focus (helpful on scrolling layout).
-- hl.gesture({ fingers = 3, direction = "left", action = function() hl.dispatch(hl.dsp.focus({ direction = "l" })) end })
-- hl.gesture({ fingers = 3, direction = "right", action = function() hl.dispatch(hl.dsp.focus({ direction = "r" })) end })
