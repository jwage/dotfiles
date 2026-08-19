# dotfiles

Personal config shared between this Mac and [Omarchy](https://omarchy.org)
(Arch + Hyprland). Tracked so a distro switch, an Omarchy reset, or a new Mac
doesn't mean starting over.

`install.sh` is OS-aware: it installs the shared editor/dev files on both
machines and skips Linux desktop files on macOS (and skips the macOS zshrc
on Linux).

Only actual customizations are tracked here, not Omarchy's stock defaults.
Each Linux desktop file was diffed against Omarchy's shipped default/skel
before being added, so this repo is the *delta*, not a full config mirror.

## What's here

Shared (macOS + Linux):

| Path | What it is |
|---|---|
| `cursor/settings.json` | Cursor editor settings (theme, PHP tooling, Composer UI) |
| `cursor/keybindings.json` | Cursor keybindings: agent/sidebar chords (`cmd` + `ctrl`) plus Linux `Ctrl+C` copies a terminal selection |
| `cursor/extensions.txt` | Cursor extension IDs installed by `install.sh` |
| `claude/CLAUDE.md` | Global Claude Code instructions (incl. keeping this repo in sync) |
| `git/config` | Git aliases and behavior (not credentials — see below) |
| `gh/config.yml` | GitHub CLI preferences |
| `mise/config.toml` | Tool version manifest |
| `ssh/config` | Host aliases |
| `shell/env.sh` | PATH + optional `~/.config/mcp-secrets.env` (sourced by both shells) |

Linux / Omarchy only:

| Path | What it is |
|---|---|
| `hypr/*.lua` | Hyprland: keybinds, input, per-app workspaces, autostart, look & feel |
| `omarchy/shell.json` | Bar widget layout |
| `omarchy/defaults/agent` | Default coding agent |
| `omarchy/plugins/jwage.workspaces/` | Custom bar widget: per-workspace app icons + window switching |
| `omarchy/plugins/jwage.battery-sleep/` | Suspends after idle on battery only; never sleeps on AC |
| `bash/bashrc` | Omarchy bashrc (sources Arch bootstrap, then `shell/env.sh`) |
| `XCompose` | Compose key sequences |

macOS only:

| Path | What it is |
|---|---|
| `zsh/zshrc` | Login shell; sources `shell/env.sh` only (no Omarchy paths) |

## What's deliberately excluded

- Secrets and keys: `~/.config/mcp-secrets.env`, `~/.ssh/id_*`, `gh/hosts.yml`
- The `[credential ...]` blocks `gh auth setup-git` writes into `git/config`
  (pin an absolute path to a specific `mise`-installed `gh` version — not
  portable; just re-run `gh auth setup-git` on a fresh machine)
- macOS `~/.gitconfig` (git-lfs, this machine's `user.email`, extra
  `safe.directory` entries). Portable aliases live in the tracked file;
  overlapping keys in `~/.gitconfig` win
- Terminal emulator configs (alacritty/foot/ghostty/kitty), tmux, btop,
  starship — verified identical to Omarchy's stock skel, so a fresh install
  already gives you these
- Cursor history, workspace storage, MCP secrets, crash-reporter IDs, and
  machine-local PHP binary paths (`/usr/local/bin/php` vs `/usr/bin/php`) —
  those last ones stay off the tracked file so both machines use `php` from
  PATH

## Install

```sh
git clone https://github.com/jwage/dotfiles.git ~/Repositories/dotfiles
~/Repositories/dotfiles/install.sh
```

Safe to re-run on either machine. Destinations that aren't already the
correct symlink are backed up as `<file>.orig` first.

Cursor settings land in `~/Library/Application Support/Cursor/User` on macOS
and `~/.config/Cursor/User` on Linux. Install Cursor first so the extension
step can run; if the `cursor` CLI is missing, settings still get linked and
extensions are skipped.

`~/.config/git/config` is the one exception — it's not symlinked directly.
`gh auth setup-git` writes a machine-specific credential helper straight into
whatever `~/.config/git/config` points at, and a plain symlink would put that
into the tracked repo file instead of staying local. So `install.sh` instead
writes a small local file that `[include]`s the tracked one:

```
[include]
	path = /home/you/Repositories/dotfiles/git/config
```

Anything added below that `[include]` line (like the credential helper)
stays local and untracked. On macOS, existing `~/.gitconfig` is not moved
or replaced.

After installing on a fresh machine, also run:

```sh
gh auth login
gh auth setup-git
```

to populate that local credential helper.
