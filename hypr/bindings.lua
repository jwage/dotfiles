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

o.bind("SUPER + TAB", "Focus on next window", hl.dsp.window.cycle_next())
o.bind("SUPER + SHIFT + TAB", "Focus on previous window", hl.dsp.window.cycle_next({ next = false }))
o.bind("SUPER + TAB", "Reveal active window on top", hl.dsp.window.bring_to_top())
o.bind("SUPER + SHIFT + TAB", "Reveal active window on top", hl.dsp.window.bring_to_top())

o.bind("ALT + TAB", "Next workspace", hl.dsp.focus({ workspace = "e+1" }))
o.bind("ALT + SHIFT + TAB", "Previous workspace", hl.dsp.focus({ workspace = "e-1" }))

-- Make SUPER consistently play the role Cmd does on macOS for common app
-- shortcuts (new tab, refresh, save), instead of switching to Ctrl for those.
-- Mirrors the "send a synthetic Ctrl+key to the focused surface" mechanism
-- Omarchy already uses for SUPER+C/V/X (see default/hypr/bindings/clipboard.lua).
local function send_ctrl_shortcut_once(key)
  return function()
    hl.dispatch(hl.dsp.send_key_state({ mods = "CTRL", key = key, state = "down" }))

    hl.timer(function()
      hl.dispatch(hl.dsp.send_key_state({ mods = "CTRL", key = key, state = "up" }))
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

-- SUPER+SHIFT+M was "Music" (the default web-app player) -- the
-- quickshell.spotify plugin (Omarchy Spotify) replaces that with its own
-- lighter, theme-matching player. See omarchy/plugins/quickshell.spotify/.
hl.unbind("SUPER + SHIFT + M")
o.bind("SUPER + SHIFT + M", "Omarchy Spotify",
  "omarchy shell -q quickshell.spotify.player togglePlayer")
