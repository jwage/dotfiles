# macOS TradersPost theme

macOS has no Omarchy-style `colors.toml` that recolors the whole desktop.
These files apply as much of the TradersPost palette as macOS and our shared
tooling allow. Source of truth for hex values:
`omarchy/themes/traderspost/colors.toml`.

## Automated (`install.sh`)

| What | How |
|---|---|
| Desktop wallpaper | Symlink + `osascript` (see root `install.sh`) |
| Dark mode + blue accent | `mac/apply-theme.sh` via `defaults` + System Events |
| **Terminal.app profile** | Import `traderspost.terminal`, set as default/startup profile |
| Cursor integrated terminal | Shared `cursor/settings.json` (`[Sunburst]` overrides) |
| Shell prompt colors | Shared `starship/starship.toml` |
| iTerm2 preset (optional) | Only if iTerm.app is installed — symlinked to `~/Documents/traderspost.itermcolors` |

## Terminal.app

`install.sh` symlinks `mac/traderspost.terminal` to
`~/Documents/traderspost.terminal`, imports it on first run (`open`), and sets
it as the default + startup profile via `defaults write com.apple.Terminal`.

Open a **new** Terminal window (or restart Terminal) after `install.sh` to see
the TradersPost colors. Existing windows keep their old profile.

## Manual (one-time)

**iTerm2** (only if you switch away from Terminal.app):

1. iTerm2 → Settings → Profiles → Colors
2. Color Presets → Import…
3. Pick `~/Documents/traderspost.itermcolors`
4. Set the preset on your default profile

**System Settings** (if `defaults` did not stick):

- Appearance → Dark
- Accent color → Blue (closest to TradersPost primary `#0984e3`)

## Not possible on macOS

Finder, menu bar, and most native apps ignore custom brand palettes.
Only wallpaper, accent preset, dark mode, and per-app theming (Terminal,
Cursor, Starship) are covered here.
