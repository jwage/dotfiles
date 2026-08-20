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
| **Terminal.app profile** | Built from `traderspost.itermcolors` via `build-terminal-profile.swift`, imported, set as default |
| Cursor integrated terminal | Shared `cursor/settings.json` (`[Sunburst]` overrides) |
| Shell prompt colors | Shared `starship/starship.toml` |
| iTerm2 preset (optional) | Only if iTerm.app is installed — symlinked to `~/Documents/traderspost.itermcolors` |

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
