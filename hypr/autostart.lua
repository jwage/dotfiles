-- Extra autostart processes.
-- o.launch_on_start("my-service")

-- Registers a Bluetooth pairing agent so passkey/PIN prompts show as a
-- tray dialog (bluetoothctl's own agent flow otherwise fails silently
-- for devices needing passkey entry, like Apple keyboards).
o.launch_on_start("blueman-applet")

-- Default startup layout: land each app on its usual workspace at login.
-- Uses exec_cmd's one-shot workspace rule, tied to the process this exec
-- spawns, so it only affects this startup launch -- opening the app again
-- later in the day is unaffected, and windows can be dragged anywhere once
-- they open.
local function launch_on_workspace(command, workspace)
  hl.on("hyprland.start", function()
    hl.dispatch(hl.dsp.exec_cmd(command, { workspace = workspace .. " silent" }))
  end)
end

launch_on_workspace(o.launch("foot"), "2")
launch_on_workspace(o.launch("cursor"), "3")
launch_on_workspace("omarchy-launch-signal", "4")
launch_on_workspace(o.launch("slack --gtk-version=3 -s"), "4")

-- Chrome is a single-instance app that restores multiple windows from one
-- process, so exec_cmd's per-process rule can't split them across
-- workspaces -- match by initial window title instead. This is a static
-- effect evaluated once when a window opens, so it never snaps a window
-- back after you move it.
o.launch_on_start("google-chrome-stable")
o.window({ title = ".*Mail.*" }, { workspace = "1 silent" })
o.window({ title = ".*TradersPost.*" }, { workspace = "3 silent" })
