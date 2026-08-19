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

-- Per-device override so mouse sensitivity doesn't affect the trackpad.
-- This is the Apple Magic Mouse, paired over Bluetooth as "Jonathan's Magic
-- Mouse" — Hyprland derives the device name from that Bluetooth name, so it
-- has to match exactly (curly apostrophe included) or this override silently
-- matches nothing. Its scroll surface is wheel-emulated by the kernel's
-- hid_magicmouse driver (see /etc/modprobe.d/hid_magicmouse.conf for the
-- scroll_speed/scroll_acceleration tuning), so libinput sees plain wheel
-- ticks rather than smooth touchpad motion. scroll_factor here softens
-- those ticks to feel closer to the trackpad's scroll_factor = 0.4.
--
-- accel_profile = "flat" drops libinput's own acceleration curve, which
-- ramps up far more aggressively on fast flicks than macOS's does — that
-- mismatch is most of what makes the pointer feel "too fast" by comparison.
-- Hyprland/libinput don't expose a true custom curve for pointer motion
-- (only for scroll), so flat + a plain speed multiplier is the closest
-- approximation available, not a byte-for-byte match. Retune sensitivity
-- to taste (-1 slowest, 1 fastest).
hl.device({
  name = "jonathan’s-magic-mouse",
  accel_profile = "flat",
  sensitivity = -0.5,
  scroll_factor = 0.4,
})

-- While magicmouse-scroll-daemon (see ../../magicmouse-scroll/) is running,
-- it exclusively grabs the physical device above so it can compute momentum
-- scrolling from the raw touch surface -- libinput then only ever sees the
-- synthetic device it creates, so the pointer tuning has to be duplicated
-- here under that device's name or the cursor silently reverts to
-- libinput's un-tuned defaults. Scroll isn't re-tuned here: the daemon
-- already converts touch movement to wheel notches at a calibrated scale
-- (and inverts direction itself -- setting natural_scroll here had no
-- observed effect on this synthetic device, so an additional scroll_factor
-- or natural_scroll would just double up on what the daemon already does).
hl.device({
  name = "magicmouse-scroll-daemon",
  accel_profile = "flat",
  sensitivity = -0.5,
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
