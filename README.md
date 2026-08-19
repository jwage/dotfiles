# dotfiles

Personal config shared between this Mac and [Omarchy](https://omarchy.org)
(Arch + Hyprland). Tracked so a distro switch, an Omarchy reset, or a new Mac
doesn't mean starting over.

`install.sh` is OS-aware: it installs the shared editor/dev/shell files on
both machines and skips Linux desktop files on macOS.

Only actual customizations are tracked here, not Omarchy's stock defaults.
Each Linux desktop file was diffed against Omarchy's shipped default/skel
before being added, so this repo is the *delta*, not a full config mirror.

## What's here

Shared (macOS + Linux):

| Path | What it is |
|---|---|
| `cursor/settings.json` | Cursor editor settings (theme, PHP tooling, Composer UI) |
| `cursor/keybindings.json` | Cursor keybindings: agent/sidebar chords (`cmd` + `ctrl`) plus Linux `Ctrl+C` copies a terminal selection |
| `cursor/extensions.txt` | Cursor extension IDs (`install.sh` installs them; UI names are in comments — Twig is `whatwedo.twig`) |
| `claude/CLAUDE.md` | Global Claude Code instructions (incl. keeping this repo in sync) |
| `AGENTS.md` | Cursor/agent entry: PHP setup points at `php/README.md` |
| `git/config` | Git aliases and behavior (not credentials — see below) |
| `gh/config.yml` | GitHub CLI preferences |
| `mise/config.toml` | Tool version manifest |
| `ssh/config` | Host aliases |
| `shell/env.sh` | MCP env file, `~/.local/bin` + Composer PATH, OS-aware PHP CLI ini scan dir, `command_not_found_handler`/`handle` fallback to local `bin`/`vendor/bin` |
| `zsh/zshrc` | Shared zshrc: Omarchy bootstrap (no-op on macOS) + `shell/env.sh` + oh-my-zsh plugins + Starship prompt |
| `starship/starship.toml` | Omarchy's stock Starship prompt (directory + branch + `❯`) so macOS matches |
| `php/cli.ini` | Shared PHP CLI overrides (`memory_limit = -1` only) |
| `php/setup.sh` / `php/README.md` | Host PHP 8.5 + extensions for Composer/phpunit (agents: start at `php/README.md`) |

Linux / Omarchy only:

| Path | What it is |
|---|---|
| `php/linux/` | Arch-only `extension=` enables (CLI); macOS never scans this dir |
| `hypr/*.lua` | Hyprland: keybinds, input, per-app workspaces, autostart, look & feel |
| `omarchy/shell.json` | Bar widget layout |
| `omarchy/defaults/agent` | Default coding agent |
| `omarchy/plugins/jwage.workspaces/` | Custom bar widget: per-workspace app icons + window switching |
| `omarchy/plugins/jwage.battery-sleep/` | Suspends after idle on battery only; never sleeps on AC |
| `bash/bashrc` | Kept as a fallback for non-interactive/bash-specific tooling (sources Arch bootstrap, then `shell/env.sh`); zsh is the default login shell |
| `XCompose` | Compose key sequences |
| `etc/modprobe.d/hid_apple.conf` | `fnmode=1` so the Apple keyboard's F-row acts as media/brightness keys by default (macOS-style); hold Fn for literal F1-F12 |
| `omarchy/plugin-patches/quickshell.spotify-ipc-media-controls.patch` | Adds `playPause`/`next`/`previous` IPC methods to the third-party `quickshell.spotify` plugin (not itself tracked here — it's `omarchy plugin add`'s own git clone at `~/.config/omarchy/plugins/quickshell.spotify/`), so `hypr/bindings.lua` can route F7/F8/F9 at Spotify instead of Omarchy's generic MPRIS-based media service (which otherwise picks Chrome). `omarchy plugin update quickshell.spotify` overwrites the live file; reapply with `cd ~/.config/omarchy/plugins/quickshell.spotify && git apply <this file>`, then `omarchy-shell shell rescanPlugins` (plain file-save hot-reload can race and half-apply — rescan forces a clean reload) |
| `etc/modprobe.d/hid_magicmouse.conf` | Magic Mouse scroll tuning (`scroll_acceleration=0 scroll_speed=32`) — see `hypr/input.lua` for why |

## What's deliberately excluded

- Secrets and keys: `~/.config/mcp-secrets.env`, `~/.ssh/id_*`, `gh/hosts.yml`
- The `[credential ...]` blocks `gh auth setup-git` writes into `git/config`
  (pin an absolute path to a specific `mise`-installed `gh` version — not
  portable; just re-run `gh auth setup-git` on a fresh machine)
- macOS `~/.gitconfig` (git-lfs, this machine's `user.email`, extra
  `safe.directory` entries). Portable aliases live in the tracked file;
  overlapping keys in `~/.gitconfig` win
- Terminal emulator configs (alacritty/foot/ghostty/kitty), tmux, btop —
  verified identical to Omarchy's stock skel, so a fresh install already
  gives you these. Starship's *binary* is the same; the prompt *config* is
  tracked in `starship/starship.toml` so this Mac does not keep Oh My Zsh's
  `robbyrussell` theme.
- Cursor history, workspace storage, MCP secrets, crash-reporter IDs, and
  machine-local PHP binary paths (`/usr/local/bin/php` vs `/usr/bin/php`) and
  `php/local/*.ini` (PIE-built `pg_query.so`) — binaries stay off the tracked
  files so both machines use `php` from PATH

## Install

```sh
git clone https://github.com/jwage/dotfiles.git ~/Repositories/dotfiles
~/Repositories/dotfiles/install.sh
```

Safe to re-run on either machine. Destinations that aren't already the
correct symlink are backed up as `<file>.orig` first.

On Linux, `install.sh` will prompt for `sudo` once to symlink
`etc/modprobe.d/*.conf` into `/etc/modprobe.d/` (everything else it does
needs no elevated privileges). Symlinking doesn't apply a changed kernel
module option by itself — reload the module or reboot:

```sh
sudo rmmod hid_apple && sudo modprobe hid_apple
```

Cursor settings land in `~/Library/Application Support/Cursor/User` on macOS
and `~/.config/Cursor/User` on Linux. Install Cursor **before** the first
`install.sh` (or re-run it afterward) so extensions from
`cursor/extensions.txt` actually install. If the `cursor` CLI is missing,
settings still get linked and extensions are skipped with a visible
`skip` line; a failed install prints `ext FAIL <id>` instead of being
swallowed.

### Extensions install.sh can't install

`whatwedo.twig` and `gerane.theme-sunburst` always fail with "not found",
on either machine — they're not published to Cursor's own marketplace
(`marketplace.cursorapi.com`; confirmed via its extensionquery API, zero
results for either ID), not an Omarchy-vs-Mac difference. They must have
been sideloaded originally from the real VS Code Marketplace. Re-sideload
the VSIX on any new machine:

```sh
curl -sL --compressed \
  "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/<publisher>/vsextensions/<name>/latest/vspackage" \
  -o /tmp/ext.vsix
cursor --install-extension /tmp/ext.vsix
```

e.g. publisher/name `whatwedo`/`twig` and `gerane`/`theme-sunburst`.

### PHP

**Agents:** follow [`php/README.md`](php/README.md) and run `php/setup.sh`.
Do not put `extension=` in the shared `php/cli.ini`.

PHP is installed via each OS's package manager (`pacman` on Omarchy, `brew`
on macOS) — not mise — so you keep native extensions (Xdebug, etc.) instead
of a from-source mise build. Keep both machines on PHP 8.5.x manually
(`php --version`); this repo does not enforce it. `install.sh` does not
install PHP.

Shared CLI settings live in `php/cli.ini` (`memory_limit = -1` only, so
phpunit/Composer on a large codebase do not hit a web-request-sized
default). Arch `extension=` lines live in `php/linux/` so Homebrew PHP is
not double-loaded. `pg_query` is enabled from gitignored `php/local/`
after `setup.sh` builds the `.so`. All of that is loaded via
`PHP_INI_SCAN_DIR` in `shell/env.sh`, not by editing the system php.ini:
that variable is only set from an interactive shell, so php-fpm/Apache
(systemd/launchd) never see it.

`zsh/zshrc` expects zsh, oh-my-zsh, Starship, and mise. `install.sh` only
symlinks config; on Omarchy those tools are already installed. On macOS:

```sh
brew install starship mise
mise trust ~/.config/mise/config.toml
mise install
```

Oh My Zsh (plugins, not the prompt):

```sh
# zsh: `pacman -S zsh` on Omarchy, preinstalled on macOS
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended --keep-zshrc
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
chsh -s "$(command -v zsh)"
```

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
