-- Keep only your personal input overrides here. Uncommented settings below
-- replace Omarchy's defaults.

-- Keyboard layout and options.
-- See https://wiki.hypr.land/Configuring/Basics/Variables/#input
hl.config({
  input = {
    -- Omarchy's default is "compose:caps,shift:both_capslock_cancel" (see
    -- default/hypr/input.lua). Both are dropped here.
    --
    -- compose:caps rewrites Caps Lock to Multi_key at every level, so the key
    -- emits no Caps_Lock at all and cannot toggle caps in either direction.
    -- shift:both_capslock_cancel then makes both Shifts together the *only*
    -- way caps can switch on -- easy to hit by accident, with no obvious way
    -- back, since the one key you would reach for is now Compose.
    --
    -- Empty means plain xkb behaviour: Caps Lock is Caps Lock.
    kb_options = "",

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
  -- Per-device kb_options *replaces* the global list rather than extending
  -- it, so this has to restate everything this keyboard should have -- which
  -- is now just the swap.
  kb_options = "altwin:swap_alt_win",
})

-- Magic Mouse pointer acceleration curve.
--
-- The goal is the macOS pointer feel: creep the mouse and the cursor barely
-- moves, so a small target is easy to land on, but flick it and the cursor
-- crosses the screen. libinput's stock "adaptive" profile cannot do that. Its
-- gain saturates at the profile's maximum once the hand passes roughly
-- 33 mm/s, which is slower than almost any deliberate movement, so nearly
-- everything above a crawl gets the same constant gain. Lowering `sensitivity`
-- does not restore the range -- the speed setting *lowers that ceiling* (and
-- raises the threshold), so the -0.45 that used to be here was making fast and
-- slow movement more alike, not less. That is the "hard to click things"
-- feeling: no fine-control region, just one flat gain everywhere.
--
-- libinput's "custom" profile replaces the curve outright with a piecewise
-- linear one defined here. It is the only option that changes the *shape* of
-- the response rather than its overall level. `sensitivity` is ignored while
-- this profile is active -- libinput keeps the value but stops applying it --
-- which is why it is gone from the rule below rather than kept alongside.
--
-- The curve is f(x): x is hand speed in device units per millisecond and f(x)
-- is the resulting pointer speed, so the gain at any speed is f(x)/x. libinput
-- assumes 1000 dpi when udev's hwdb has no MOUSE_DPI entry for a device, and
-- it has none for the Magic Mouse, so 1 unit/ms is about 25 mm/s.
--
-- Tune by editing GAIN -- {hand speed, gain} pairs, linearly interpolated.
-- Only the gain column normally needs touching:
--   whole pointer too slow or too fast -> scale every gain
--   overshooting small targets         -> lower the first few gains
--   flicks do not cross the screen     -> raise the last few gains
-- The last pair repeats the previous gain on purpose. Past the final point
-- libinput extrapolates from the last two, so a flat tail caps the gain for
-- movements faster than the table covers instead of letting it run away.
local GAIN = {
  { 0.0, 0.40 }, --   0 mm/s -- fine positioning; pointer moves less than the hand
  { 0.5, 0.45 }, --  13 mm/s
  { 1.0, 0.60 }, --  25 mm/s
  { 2.0, 0.90 }, --  51 mm/s
  { 4.0, 1.30 }, -- 102 mm/s -- ordinary aiming, about where the old flat gain sat
  { 8.0, 1.85 }, -- 203 mm/s
  { 16.0, 2.55 }, -- 406 mm/s
  { 24.0, 3.00 }, -- 610 mm/s -- flicks across the screen
  { 31.5, 3.00 }, -- 800 mm/s -- flat tail, see above
}

-- Sample GAIN into the uniformly spaced points libinput wants: a step, then
-- f() at 0, step, 2*step, ... 64 points is libinput's maximum. Keep the last
-- GAIN speed equal to (npoints - 1) * step so the table covers the whole curve
-- and the flat tail lands where the extrapolation starts.
local function accel_profile(step, npoints)
  local function gain_at(x)
    if x <= GAIN[1][1] then
      return GAIN[1][2]
    end
    for i = 1, #GAIN - 1 do
      local x0, g0 = GAIN[i][1], GAIN[i][2]
      local x1, g1 = GAIN[i + 1][1], GAIN[i + 1][2]
      if x <= x1 then
        return g0 + (g1 - g0) * (x - x0) / (x1 - x0)
      end
    end
    return GAIN[#GAIN][2]
  end

  local points = {}
  for i = 0, npoints - 1 do
    local x = i * step
    points[#points + 1] = string.format("%.4f", x * gain_at(x))
  end
  return string.format("custom %.3f %s", step, table.concat(points, " "))
end

-- Only the pointer curve is set, not scroll_points: Magic Mouse surface
-- scrolling does not come through this device at all. It arrives on the
-- virtual touchpad below, which has its own acceleration.
--
-- "dark-work-mouse" is the Magic Mouse's *Bluetooth alias*, lowercased and
-- hyphenated. That alias is user-editable, and Hyprland device rules can only
-- match on the name -- rename the mouse in Bluetooth settings and this rule
-- stops applying, silently. (magicmouse-scroll matches on the USB/BT vendor and
-- product IDs instead, for exactly this reason, but that option does not exist
-- here.) If the pointer feel ever reverts on its own, check the alias first:
--   bluetoothctl devices | grep -i mouse
hl.device({
  name = "dark-work-mouse",
  accel_profile = accel_profile(0.5, 64),
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

-- Touchpad scroll speed in the coding-agent terminal.
--
-- Omarchy's default input.lua already boosts terminals with
--   o.window("(Alacritty|kitty|foot)", { scroll_touchpad = 1.5 })
-- but that rule matches on *class*, and `omarchy agent` launches foot with
-- --app-id=org.omarchy.agent. So the agent window is a foot window that the
-- terminal rule never matches, and it scrolls at a bare 1.0 while every other
-- foot window gets the boost.
--
-- Set higher than the 1.5 the terminal rule would have given, because 1.5 on
-- its own does not make the agent window feel like the other terminals --
-- foot/foot.ini's `[scrollback] multiplier=7.0` does not appear to reach the
-- touchpad's high-resolution axis events the way it reaches discrete wheel
-- clicks. 4.0 is tuned by feel, not derived.
--
-- Tune this number alone if the speed is off; it multiplies the touchpad
-- scroll delta before the window sees it.
o.window("org.omarchy.agent", { scroll_touchpad = 4.0 })

-- Enable touchpad gestures for changing workspaces.
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Gestures/
-- hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

-- Enable touchpad gestures for moving focus (helpful on scrolling layout).
-- hl.gesture({ fingers = 3, direction = "left", action = function() hl.dispatch(hl.dsp.focus({ direction = "l" })) end })
-- hl.gesture({ fingers = 3, direction = "right", action = function() hl.dispatch(hl.dsp.focus({ direction = "r" })) end })
