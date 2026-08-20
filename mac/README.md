# macOS TradersPost theme

macOS has no Omarchy-style `colors.toml` that recolors the whole desktop.
These files apply as much of the TradersPost palette as macOS and our shared
tooling allow. Source of truth for hex values:
`omarchy/themes/traderspost/colors.toml`.

## What matches Omarchy vs what cannot

| Layer | TradersPost colors? | Notes |
|---|---|---|
| Wallpaper | Yes | Same PNG as Omarchy |
| Terminal.app | Yes | Full ANSI + background palette |
| Cursor | Yes | Sidebar, tabs, status bar, integrated terminal |
| Starship prompt | Yes | Cyan / blue / red from palette |
| **Google Chrome** | Yes | Unpacked theme extension (toolbar, tabs, omnibox, new tab) |
| macOS accent + highlights | Partial | Blue accent only — not custom navy chrome |
| Finder, Mail, Notes, etc. | **No** | Apple fixed dark gray; no public API for brand colors |
| Menu bar / Dock | Partial | Wallpaper tint + blue accent; not `#151f27` |

There is no supported way to paint every macOS window frame, sidebar, and
toolbar with TradersPost navy the way Hyprland + Omarchy do on Linux. Chrome
and Cursor are the main gaps we can close on the Mac.

## Automated (`install.sh`)

| What | How |
|---|---|
| Desktop wallpaper | Symlink + `osascript` (see root `install.sh`) |
| Dark mode + blue accent + highlights | `mac/apply-theme.sh` via `defaults` + System Events |
| **Terminal.app profile** | Built from `traderspost.itermcolors` via `build-terminal-profile.swift`, imported, set as default |
| **Google Chrome theme** | Built via `build-chrome-theme.sh`, symlinked to `~/Documents/traderspost-chrome-theme` |
| Cursor integrated terminal | Shared `cursor/settings.json` (`[Sunburst]` overrides) |
| Shell prompt colors | Shared `starship/starship.toml` |
| iTerm2 preset (optional) | Only if iTerm.app is installed |

## Google Chrome (one-time, then Reload after updates)

`install.sh` builds theme assets (frame/toolbar PNGs are required — colors
alone look like default black/gray on current Chrome) and **copies** the
extension folder to `~/Documents/traderspost-chrome-theme`.

1. Open `chrome://extensions`
2. Turn on **Developer mode**
3. **Load unpacked** → select `~/Documents/traderspost-chrome-theme`
4. Confirm **TradersPost** is enabled

After dotfiles updates: open `chrome://extensions` and click **Reload** on
TradersPost.

If the toolbar still looks like default gray/black:

1. **Chrome → Settings → Appearance** — reset/remove any **Chrome colors**
   theme (that overrides extension themes)
2. Confirm the TradersPost card on `chrome://extensions` has no errors
3. Re-run `~/Repositories/dotfiles/mac/apply-theme.sh` and **Load unpacked**
   again (or Reload)

The tab strip uses TradersPost navy (`#233644` toolbar, `#0984e3` accents);
it is intentionally dark, but should read as blue-navy rather than flat gray.

## Terminal.app

`install.sh` runs `mac/build-terminal-profile.swift` to generate a modern
`.terminal` file (NSKeyedArchiver color blobs — hand-written RGB dicts are
rejected as corrupt on current macOS). The profile is symlinked to
`~/Documents/traderspost.terminal`, imported with `open`, and set as the
default + startup profile.

Open a **new** Terminal window (or restart Terminal) after `install.sh` to
see the TradersPost colors. Existing windows keep their old profile.

To rebuild after palette changes, edit `traderspost.itermcolors` (or
`omarchy/themes/traderspost/colors.toml` and sync the iterm file), then:

```sh
~/Repositories/dotfiles/mac/build-terminal-profile.swift
~/Repositories/dotfiles/mac/apply-theme.sh
```

## System Settings worth checking

If the menu bar and window chrome still look flat black/gray:

1. **System Settings → Appearance**
   - Appearance: **Dark**
   - Accent color: **Blue**
   - Enable **Show colors in menu bar** / wallpaper tint if your macOS version
     offers it (pairs with the TradersPost wallpaper)
2. Log out and back in if accent/highlight defaults from `install.sh` did not
   apply to Finder selections immediately.

## Manual (optional)

**iTerm2** (only if you switch away from Terminal.app):

1. iTerm2 → Settings → Profiles → Colors
2. Color Presets → Import…
3. Pick `~/Documents/traderspost.itermcolors`
