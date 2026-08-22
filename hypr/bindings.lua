-- Keep only your personal keybinding overrides here. Add new bindings or
-- unbind defaults before replacing them.

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false

-- To disable all preinstalled app/webapp bindings, set:
--   omarchy_preinstalled_bindings = false

-- Add a new binding.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Change an existing binding by unbinding it first, then binding the key again.
-- This example changes SUPER+SPACE from the launcher to the Omarchy root menu.
-- hl.unbind("SUPER + SPACE")
-- o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu toggle root")

-- Disable a default binding without replacing it.
-- hl.unbind("SUPER + SHIFT + B")

-- Logitech MX Keys examples:
-- o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")
-- o.bind("SUPER + H", nil, "voxtype record toggle")
-- o.bind("SUPER + PERIOD", nil, "omarchy-shell shell toggle omarchy.emojis")

-- Swap Alt+Tab and Super+Tab so window switching feels like macOS Cmd+Tab.
-- Was: SUPER+TAB/SUPER+SHIFT+TAB = next/previous workspace,
--      ALT+TAB/ALT+SHIFT+TAB = next/previous window (+ reveal on top).
hl.unbind("SUPER + TAB")
hl.unbind("SUPER + SHIFT + TAB")
hl.unbind("ALT + TAB")
hl.unbind("ALT + SHIFT + TAB")

-- Cycle focus the way `cyclenext` does, but grow the incoming window *before*
-- revealing it.
--
-- `cyclenext` hands the workspace's fullscreen/maximized state to whatever it
-- focuses, so switching apps on a workspace where one app is maximized means
-- the incoming window changes size from its tile to the full screen. Hyprland
-- moves focus, raises the window and resizes it in the same frame, but the
-- client cannot repaint that fast: for the first few frames the compositor
-- stretches the buffer the app last painted at its small tiled size up to full
-- screen, and only then does the app re-layout. That is the jump -- the app
-- appears as a scaled-up copy of its narrow layout, then snaps to its wide one,
-- responsive breakpoints and all.
--
-- Two windows can hold a fullscreen state at the same time, so the resize can
-- be done while the outgoing window is still covering the screen: maximize the
-- target, let it repaint out of sight, and only then drop the outgoing window's
-- maximized state and move focus. Nothing on screen changes until the incoming
-- window has finished laying out. Same order as the bar's click handler
-- (~/.config/omarchy/plugins/jwage.workspaces/focus-window), which had to solve
-- this for icon clicks.
--
-- REVEAL_DELAY_MS is how long the incoming app gets to repaint off-screen. It
-- is dead time before the switch becomes visible, so keep it as low as the apps
-- allow: too low and the stretched frame leaks back into view, too high and
-- Super+Tab feels sluggish. Electron/Chromium apps (Slack, Signal, Chrome) are
-- the slow ones here.
local REVEAL_DELAY_MS = 80

-- Guard against a second Super+Tab landing between the maximize and the reveal,
-- which would hand the fullscreen state to a third window and leave two windows
-- maximized for good.
local cycle_in_progress = false

local function cycle_window(forward)
  return function()
    if cycle_in_progress then
      return
    end

    local source = hl.get_active_window()
    local workspace = source and source.workspace
    if not workspace then
      return
    end

    -- Deliberately unsorted: this is Hyprland's own window order, the same one
    -- `cyclenext` walks, so the cycle keeps the sequence it had before.
    local windows = {}
    local index
    for _, window in ipairs(hl.get_workspace_windows(workspace.id) or {}) do
      if window.mapped and not window.hidden then
        windows[#windows + 1] = window
        if window.address == source.address then
          index = #windows
        end
      end
    end

    if not index or #windows < 2 then
      return
    end

    local target = windows[((index - 1 + (forward and 1 or -1)) % #windows) + 1]
    local internal = source.fullscreen or 0
    local client = source.fullscreen_client or 0

    -- No fullscreen state to hand over means no resize, so nothing to hide.
    if internal == 0 and client == 0 then
      hl.dispatch(hl.dsp.focus({ window = "address:" .. target.address }))
      hl.dispatch(hl.dsp.window.bring_to_top())
      return
    end

    cycle_in_progress = true

    hl.dispatch(hl.dsp.window.fullscreen_state({
      internal = internal,
      client = client,
      window = "address:" .. target.address,
    }))

    hl.timer(function()
      hl.dispatch(hl.dsp.window.fullscreen_state({
        internal = 0,
        client = 0,
        window = "address:" .. source.address,
      }))
      hl.dispatch(hl.dsp.focus({ window = "address:" .. target.address }))
      hl.dispatch(hl.dsp.window.bring_to_top())
      cycle_in_progress = false
    end, { timeout = REVEAL_DELAY_MS, type = "oneshot" })
  end
end

o.bind("SUPER + TAB", "Focus on next window", cycle_window(true))
o.bind("SUPER + SHIFT + TAB", "Focus on previous window", cycle_window(false))

o.bind("ALT + TAB", "Next workspace", hl.dsp.focus({ workspace = "e+1" }))
o.bind("ALT + SHIFT + TAB", "Previous workspace", hl.dsp.focus({ workspace = "e-1" }))

-- Make SUPER consistently play the role Cmd does on macOS for common app
-- shortcuts (new tab, refresh, save), instead of switching to Ctrl for those.
-- Mirrors the "send a synthetic Ctrl+key to the focused surface" mechanism
-- Omarchy already uses for SUPER+C/V/X (see default/hypr/bindings/clipboard.lua).
local function send_ctrl_shortcut_once(key, mods)
  mods = mods or "CTRL"
  return function()
    hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down" }))

    hl.timer(function()
      hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up" }))
    end, { timeout = 50, type = "oneshot" })
  end
end

local function active_window_is_terminal()
  local window = hl.get_active_window()
  if not window then
    return false
  end

  for _, tag in ipairs(window.tags or {}) do
    if tag:gsub("%*$", "") == "terminal" then
      return true
    end
  end

  return false
end

-- Free (no default macOS meaning to protect): just forward.
o.bind("SUPER + R", "Refresh (Cmd+R)", send_ctrl_shortcut_once("R"))

-- Hard refresh (Cmd+Shift+R on macOS Chrome) -- Chrome on Linux uses the same
-- Ctrl+Shift+R chord, so just forward it.
o.bind("SUPER + SHIFT + R", "Hard refresh (Cmd+Shift+R)", send_ctrl_shortcut_once("R", "CTRL SHIFT"))

-- SUPER+T was "Toggle window floating/tiling" -- move that to SUPER+SHIFT+T
-- so SUPER+T can become new tab, matching Cmd+T.
hl.unbind("SUPER + T")
o.bind("SUPER + SHIFT + T", "Toggle window floating/tiling", hl.dsp.window.float({ action = "toggle" }))
o.bind("SUPER + T", "New tab (Cmd+T)", send_ctrl_shortcut_once("T"))

-- SUPER+S was "Toggle scratchpad" -- move that to SUPER+GRAVE (backtick, the
-- common quake-terminal-style scratchpad key elsewhere) so SUPER+S can become
-- save, matching Cmd+S. Ctrl+S in a real terminal triggers XOFF flow control
-- (freezes output), so skip forwarding when a terminal is focused -- Cmd+S
-- has no meaning in Terminal.app either.
hl.unbind("SUPER + S")
o.bind("SUPER + GRAVE", "Toggle scratchpad", hl.dsp.workspace.toggle_special("scratchpad"))
o.bind("SUPER + S", "Save (Cmd+S)", function()
  if not active_window_is_terminal() then
    send_ctrl_shortcut_once("S")()
  end
end)

-- SUPER+P was "Pseudo window" (a rarely-used dwindle-layout toggle) -- move
-- it to SUPER+ALT+P so SUPER+P can forward Ctrl+P (Quick Open in Cursor/VS
-- Code, Print in Chrome, etc).
hl.unbind("SUPER + P")
o.bind("SUPER + ALT + P", "Pseudo window", hl.dsp.window.pseudo())
o.bind("SUPER + P", "Cmd+P passthrough", send_ctrl_shortcut_once("P"))

-- SUPER+F was "Full screen" -- drop it (unused) so SUPER+F can forward
-- Ctrl+F (Find in Chrome, Cursor/VS Code, etc), matching Cmd+F on macOS.
-- SUPER+ALT+F ("Full width") is left as-is.
hl.unbind("SUPER + F")
o.bind("SUPER + F", "Find (Cmd+F)", send_ctrl_shortcut_once("F"))

-- Free (no default macOS meaning to protect): redo, to go with undo above.
o.bind("SUPER + SHIFT + Z", "Redo (Cmd+Shift+Z)", send_ctrl_shortcut_once("Z", "CTRL SHIFT"))

-- Every other SUPER+<letter> Omarchy doesn't already claim for a window-
-- manager action: forward as Ctrl+<letter>, so SUPER consistently plays the
-- role Cmd does on macOS instead of switching to Ctrl for ordinary app
-- shortcuts (Select All, New, Undo, Quit, etc). Letters already bound to a
-- WM action (F, W, J, O, C, V, X, L, G, K, plus T/S/R/P above) are untouched.
for _, key in ipairs({ "A", "B", "D", "E", "H", "I", "M", "N", "Q", "U", "Y", "Z" }) do
  o.bind("SUPER + " .. key, "Cmd+" .. key .. " passthrough", send_ctrl_shortcut_once(key))
end

local function active_window_is_slack()
  local window = hl.get_active_window()
  return window ~= nil and window.class == "slack"
end

-- Slack sends with Ctrl+Return on Linux (its own preference, not something
-- Slack lets you rebind to Super/Cmd there), while macOS Slack uses Cmd+Return.
-- Forward Super+Return as Ctrl+Return, but only while Slack is focused.
-- SUPER+RETURN was "Terminal" by default; unbind that so it doesn't fire
-- alongside this, and fall back to launching the terminal ourselves when
-- Slack isn't focused so the original shortcut keeps working everywhere else.
hl.unbind("SUPER + RETURN")
o.bind("SUPER + RETURN", "Send message (Cmd+Return, like macOS Slack)", function()
  if active_window_is_slack() then
    send_ctrl_shortcut_once("Return")()
  else
    hl.dispatch(hl.dsp.exec_cmd("omarchy-launch-terminal"))
  end
end)

local function active_window_is_chrome()
  local window = hl.get_active_window()
  return window ~= nil and window.class == "google-chrome"
end

-- New incognito window, matching Cmd+Shift+N on macOS Chrome. Chrome on Linux
-- puts this on Ctrl+Shift+N, so forward that -- which also means an existing
-- incognito session gets a new window rather than a second isolated one, the
-- same as pressing it on a Mac.
--
-- SUPER+SHIFT+N was "Editor" (omarchy-launch-editor). That binding is not
-- redundant, so rather than dropping it, fall back to it whenever Chrome is not
-- the focused window -- the same shape as SUPER+RETURN above, which forwards to
-- Slack when Slack is focused and otherwise still launches the terminal. Chrome
-- is the only place Cmd+Shift+N means anything, so the editor keeps the key
-- everywhere else.
hl.unbind("SUPER + SHIFT + N")
o.bind("SUPER + SHIFT + N", "New incognito window in Chrome (Cmd+Shift+N), else Editor", function()
  if active_window_is_chrome() then
    send_ctrl_shortcut_once("N", "CTRL SHIFT")()
  else
    hl.dispatch(hl.dsp.exec_cmd("omarchy-launch-editor"))
  end
end)
