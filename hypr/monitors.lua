-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and supported resolutions with: hyprctl monitors all
--
-- Output names/scales below are tuned for this specific machine: the Dell
-- XPS 14's built-in panel (eDP-1) plus a Dell S3222DGM external monitor
-- (DP-1). On different hardware, check `hyprctl monitors all` for the
-- real output names and retune scale to taste.

-- Per-monitor scale: laptop panel is 2880x1800 HiDPI, external Dell is
-- 2560x1440 at lower density, so they need different scale to match text
-- size. GDK_SCALE (a single global value forcing all GTK apps to one fixed
-- scale regardless of monitor) has been removed -- it can't vary per
-- output, so it would fight these per-monitor values. Modern GTK picks up
-- each monitor's real scale automatically via Wayland fractional-scaling.
hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 1.6 })
hl.monitor({ output = "DP-1", mode = "preferred", position = "auto", scale = 1.5 })

-- Configure a specific monitor.
-- hl.monitor({ output = "DP-2", mode = "2560x1440@144", position = "0x0", scale = 1 })

-- Portrait/rotated secondary monitor (transform: 1 = 90°, 3 = 270°).
-- hl.monitor({ output = "DP-2", mode = "preferred", position = "auto", scale = 1, transform = 1 })

-- Keep workspace 2 on the big external monitor instead of the laptop panel.
hl.workspace_rule({ workspace = "2", monitor = "DP-1" })
