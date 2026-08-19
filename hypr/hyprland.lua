-- Learn how to configure Hyprland: https://wiki.hypr.land/Configuring/Start/

-- Omarchy's bootstrap keeps path setup out of this user config.
dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")

-- Disable all Omarchy default bindings. Add your own in hypr/bindings.lua.
-- omarchy_default_bindings = false
--
-- Or disable only bindings for Omarchy's preinstalled apps/web apps while
-- keeping core window-manager bindings:
-- omarchy_preinstalled_bindings = false

-- Load Omarchy defaults.
require("default.hypr.omarchy")

-- Put your personal overrides in these files. They're loaded after Omarchy's
-- defaults so package updates can improve the defaults without rewriting your
-- ~/.config/hypr files.
require("hypr.monitors")
require("hypr.input")
require("hypr.bindings")
require("hypr.looknfeel")
require("hypr.autostart")

-- Toggle config flags dynamically.
require("default.hypr.toggles")

-- Add any other personal Hyprland configuration below.
-- o.window("qemu", { workspace = "5" })

-- Consistent per-app workspace assignment: opening one of these apps moves
-- it (and switches focus) to its assigned workspace, so the layout stays
-- the same across logins/relaunches instead of wherever it happened to open.
o.window("^cursor$", { workspace = "1" })
o.window("^google-chrome$", { workspace = "1" }) -- tiled alongside Cursor for live-reload dev workflow
o.window("^foot$", { workspace = "3" })
o.window("^org.omarchy.agent$", { workspace = "3" }) -- Claude Code sessions, grouped with the terminal
o.window("^slack$", { workspace = "4" })
o.window("^signal$", { workspace = "5" })
