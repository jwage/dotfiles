# Agent notes

This repo is personal dotfiles for macOS and Omarchy (Arch), not an
application. `install.sh` is OS-aware and only symlinks config.

- **PHP on the host** (Composer, phpunit): read [`php/README.md`](php/README.md)
  and run `php/setup.sh`. Do not put `extension=` in shared `php/cli.ini`.
- **Magic Mouse** is split across two daemons, both tracked here and both
  symlinked by `install.sh`: momentum scrolling from `magicmouse-scroll/`
  (one finger) and swipe navigation from `magic-mouse-gestures/` (two
  fingers), a vendored fork of the upstream repo of that name. Read the
  Magic Mouse section in [`README.md`](README.md) and
  [`magic-mouse-gestures/README.md`](magic-mouse-gestures/README.md) before
  touching either; the finger-count split and `emulate_scroll_wheel=0` are
  what keep them from fighting. Do not re-run upstream's installer — it
  copies into `/opt` and would shadow the fork.
- **TradersPost health widget** (`omarchy/plugins/jwage.traderspost/`) reads
  the New Relic NerdGraph API. Its thresholds are a deliberate copy of the
  conditions in New Relic's `TradersPost Policy` -- if you change one, change
  the other, or the bar dot stops agreeing with the pager. QML changes need
  `omarchy restart shell`; a plugin file save is not enough. Read
  [`omarchy/plugins/jwage.traderspost/README.md`](omarchy/plugins/jwage.traderspost/README.md).
- **Linux desktop files** are Omarchy/Hyprland only — never add them to the
  shared `install.sh` link list.
- Do not commit secrets (`~/.config/mcp-secrets.env`, SSH keys, `gh` hosts).
- If you edit a live config file, check whether it is a symlink into this
  repo and commit here.

Global Claude Code instructions: [`claude/CLAUDE.md`](claude/CLAUDE.md).
