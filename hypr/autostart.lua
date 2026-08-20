-- Extra autostart processes.
-- o.launch_on_start("my-service")

-- Registers a Bluetooth pairing agent so passkey/PIN prompts show as a
-- tray dialog (bluetoothctl's own agent flow otherwise fails silently
-- for devices needing passkey entry, like Apple keyboards).
o.launch_on_start("blueman-applet")

-- Default startup layout: land each app on its usual workspace at login.
-- Uses exec_cmd's one-shot workspace rule, tied to the pid this exec
-- spawns, so it only affects this startup launch -- opening the app again
-- later in the day is unaffected, and windows can be dragged anywhere once
-- they open. Only safe for apps that map their window from that same pid --
-- see the Electron note below for apps this doesn't work for.
local function launch_on_workspace(command, workspace)
  hl.on("hyprland.start", function()
    hl.dispatch(hl.dsp.exec_cmd(command, { workspace = workspace .. " silent" }))
  end)
end

launch_on_workspace(o.launch("foot"), "2")
launch_on_workspace("omarchy-agent", "2")

-- Electron/CEF apps (cursor, slack, signal, spotify) fork into a helper
-- process before mapping their real window, so the pid Hyprland tracks for
-- the one-shot
-- exec-workspace rule above isn't the pid that ends up owning the window --
-- the rule silently never fires and the window lands wherever. Match by
-- class instead, same as Chrome below: this fires whenever a matching
-- window opens (including if you open one manually later), but is the only
-- reliable option for apps that fork like this.
o.launch_on_start("cursor")
o.window({ class = "cursor" }, { workspace = "3 silent" })

o.launch_on_start("omarchy-launch-signal")
o.window({ class = "signal" }, { workspace = "4 silent" })

o.launch_on_start("slack --gtk-version=3 -s")
o.window({ class = "slack" }, { workspace = "4 silent" })

o.launch_on_start("spotify")
o.window({ class = "Spotify" }, { workspace = "5 silent" })

-- Chrome is also single-instance and restores multiple windows from one
-- process, so per-process rules can't split them across workspaces either
-- -- match by window title instead.
--
-- --restore-last-session forces the previously open windows (and their
-- pinned tabs) back open on launch -- the Default profile's "on startup"
-- setting is left at its default (Open the New Tab page), which alone
-- would just open one blank window and never bring the second window back.
o.launch_on_start("google-chrome-stable --restore-last-session")

-- A title-only static rule (o.window({ title = ... }, { workspace = ... }))
-- only fires if the window's *initial* title already matches at the moment
-- it maps (wiki: Window-Rules#static-effects) -- restore-last-session
-- doesn't always focus the Mail tab first, so on some reboots the first
-- window to map has some other tab's title (e.g. a GitHub page) and neither
-- the Mail nor TradersPost title rule matches. With no rule firing, the
-- window falls back to whatever workspace happened to be active, which is
-- how Chrome has ended up parked on workspace 5 next to Spotify instead of
-- its usual workspace 1.
--
-- Fix: match the fallback rule by class (always true for any Chrome window,
-- regardless of which tab is focused at map time) so there's always a
-- deterministic landing spot. Rules apply top to bottom with last-match-
-- winning, so the more specific TradersPost title rule comes after and
-- overrides it to workspace 3 for the cases where the title is already
-- known at map time.
o.window({ class = "google-chrome" }, { workspace = "1 silent" })
o.window({ title = ".*TradersPost.*" }, { workspace = "3 silent" })

-- Static rules only catch the title if it's already right at map time.
-- Back that up with a listener for the race where TradersPost's real tab
-- title arrives late (after the session-restored page finishes loading),
-- so a window that landed on workspace 1 by default still gets moved to 3
-- once its title reveals it. Guard by window address so a later title
-- change on an already-placed window (e.g. switching tabs) can't move it
-- again.

local placed_by_title = {}
local function place_chrome_window_by_title(needle, workspace)
  hl.on("window.title", function(w)
    if w == nil or w.class ~= "google-chrome" or placed_by_title[w.address] then
      return
    end
    if w.title:find(needle, 1, true) then
      placed_by_title[w.address] = true
      hl.dispatch(hl.dsp.window.move({ workspace = workspace, follow = false, window = w }))
    end
  end)
end

place_chrome_window_by_title("TradersPost", 3)
