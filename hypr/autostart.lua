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
-- -- match by initial window title instead.
--
-- --restore-last-session forces the previously open windows (and their
-- pinned tabs) back open on launch -- the Default profile's "on startup"
-- setting is left at its default (Open the New Tab page), which alone
-- would just open one blank window and never bring the second window back.
o.launch_on_start("google-chrome-stable --restore-last-session")
o.window({ title = ".*Mail.*" }, { workspace = "1 silent" })
o.window({ title = ".*TradersPost.*" }, { workspace = "3 silent" })
