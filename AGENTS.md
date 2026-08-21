# Agent notes

This repo is personal dotfiles for macOS and Omarchy (Arch), not an
application. `install.sh` is OS-aware and only symlinks config.

- **PHP on the host** (Composer, phpunit): read [`php/README.md`](php/README.md)
  and run `php/setup.sh`. Do not put `extension=` in shared `php/cli.ini`.
- **Magic Mouse** support is external and untracked: see the Magic Mouse
  section in [`README.md`](README.md) and follow the upstream repo's own
  install instructions. Its installer needs a real terminal for `sudo`.
- **Linux desktop files** are Omarchy/Hyprland only — never add them to the
  shared `install.sh` link list.
- Do not commit secrets (`~/.config/mcp-secrets.env`, SSH keys, `gh` hosts).
- If you edit a live config file, check whether it is a symlink into this
  repo and commit here.

Global Claude Code instructions: [`claude/CLAUDE.md`](claude/CLAUDE.md).
