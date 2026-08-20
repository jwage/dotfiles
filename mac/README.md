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
| Cursor / VS Code chrome + integrated terminal | Shared `cursor/settings.json` (`[Sunburst]` overrides) |
| Shell prompt colors | Shared `starship/starship.toml` |
| iTerm2 preset file | Symlinked to `~/Documents/traderspost.itermcolors` |

## Manual (one-time)

**iTerm2** (if you use it instead of Cursor's terminal):

1. iTerm2 → Settings → Profiles → Colors
2. Color Presets → Import…
3. Pick `~/Documents/traderspost.itermcolors`
4. Set the preset on your default profile

**System Settings** (if `defaults` did not stick):

- Appearance → Dark
- Accent color → Blue (closest to TradersPost primary `#0984e3`)

## Not possible on macOS

Finder, menu bar, and most native apps ignore custom brand palettes.
Only wallpaper, accent preset, dark mode, and per-app theming (Cursor,
iTerm2, Starship) are covered here.
