# Dotfiles

Custom Omarchy/Hyprland/shell config is tracked in the private repo
`~/Repositories/dotfiles` (github.com/jwage/dotfiles) and symlinked into
place via its `install.sh` — see that repo's README for what's tracked and
why.

**Whenever you edit a config file, check whether it's a symlink into that
repo** (`realpath <path>` starts with `$HOME/Repositories/dotfiles`).
If it is, commit (and push) the change there once you've confirmed the
change works — don't leave the dotfiles repo behind live config edits.

`install.sh` skips Hyprland/Omarchy/bashrc/XCompose on macOS. Shared files
(including `zsh/zshrc`) install on both OS. Do not add a Linux-only path
to the shared link list.

## PHP

Host PHP for Composer and phpunit is **not** installed by `install.sh`.
Follow [`php/README.md`](../php/README.md) and run `php/setup.sh`.

- PHP 8.5.x via `pacman` / `brew`, never mise.
- Shared `php/cli.ini`: `memory_limit = -1` only. **Never** add
  `extension=` there (breaks Homebrew PHP with "already loaded").
- Arch enables modules in `php/linux/extensions.ini`. `pg_query` is
  gitignored `php/local/` after PIE, using `${HOME}` — no hardcoded
  `/home/jwage/...` paths.
- If `php --ini` does not list `dotfiles/php/cli.ini`, the process skipped
  zshrc; export `PHP_INI_SCAN_DIR` as in `php/README.md` before Composer.

Cursor editor settings live in `cursor/` in this same repo (`settings.json`,
`keybindings.json`, `extensions.txt`). Live paths are
`~/Library/Application Support/Cursor/User/` on macOS and
`~/.config/Cursor/User/` on Linux. Treat edits to those live files the same
way: if they are symlinks into this repo, commit the change here.

**If you create a new Omarchy/Hyprland customization that isn't tracked yet**
(a new plugin, a new hypr config file, etc.), bring it into the dotfiles repo
the same way the existing files are: copy it in, symlink the live path back
to the repo copy, add an entry to `install.sh`, commit, and push — rather
than leaving it as an untracked file that a fresh install/distro-switch would
lose.

Never commit secrets/keys into that repo (see its README for what's already
excluded and why).
