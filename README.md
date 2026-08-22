# dotfiles

Personal config shared between this Mac and [Omarchy](https://omarchy.org)
(Arch + Hyprland). Tracked so a distro switch, an Omarchy reset, or a new Mac
doesn't mean starting over.

`install.sh` is OS-aware: it installs the shared editor/dev/shell files on
both machines and skips Linux desktop files on macOS. On macOS it still
applies the TradersPost wallpaper, system dark mode + blue accent, Terminal
and **Google Chrome** theming, Cursor/Starship colors — see
[`mac/README.md`](mac/README.md) for what macOS cannot recolor (Finder, etc.).

Only actual customizations are tracked here, not Omarchy's stock defaults.
Each Linux desktop file was diffed against Omarchy's shipped default/skel
before being added, so this repo is the *delta*, not a full config mirror.

## What's here

Shared (macOS + Linux):

| Path | What it is |
|---|---|
| `cursor/settings.json` | Cursor editor settings (Sunburst + TradersPost `[Sunburst]` chrome/terminal overrides from `colors.toml`, PHP tooling) |
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
| `starship/starship.toml` | Starship prompt (TradersPost cyan/blue palette on both machines) |
| `php/cli.ini` | Shared PHP CLI overrides (`memory_limit = -1` only) |
| `php/setup.sh` / `php/README.md` | Host PHP 8.5 + extensions for Composer/phpunit (agents: start at `php/README.md`) |

Linux / Omarchy only:

| Path | What it is |
|---|---|
| `php/linux/` | Arch-only `extension=` enables (CLI); macOS never scans this dir |
| `hypr/*.lua` | Hyprland: keybinds, input, per-app workspaces, autostart, look & feel, monitors (output names/scale in `monitors.lua` are specific to this machine's laptop panel + external display) |
| `omarchy/shell.json` | Bar widget layout |
| `omarchy/defaults/agent` | Default coding agent |
| `omarchy/plugins/jwage.workspaces/` | Custom bar widget: per-workspace app icons + window switching. Icons are ordered by where the windows actually sit on screen (top row first, then left to right). Gmail is special-cased: both accounts' app windows fold into one mail icon showing the combined unread count, read live from each window's own title (no Gmail API, no polling) — hover for the per-account split, click to jump to whichever inbox has mail |
| `webapps/` | Gmail as two Chrome app windows, one per account, plus the Google Mail icon the bar resolves through `StartupWMClass`. They have to be app windows rather than tabs: Hyprland only exposes a browser window's *active tab* title, so tabbed accounts can never report an unread count. `hypr/autostart.lua` launches both onto workspace 1 with the other comms apps |
| `omarchy/plugins/jwage.battery-sleep/` | Suspends after idle on battery only; never sleeps on AC |
| `omarchy/plugins/jwage.traderspost/` | Bar widget: TradersPost production health from the New Relic NerdGraph API — a traffic-light dot plus an ops cockpit popup in three sections: the trading execution pipeline in travel order (receive webhook, outbox, handle webhook, live and paper trades, each with rate/run/queue-wait), traffic around the application, and every external service called, slowest first. Thresholds mirror the four conditions in New Relic's own `TradersPost Policy` rather than being invented; see [its README](omarchy/plugins/jwage.traderspost/README.md). Needs `~/.config/mcp-secrets.env` (untracked) for the API key |
| `omarchy/themes/traderspost/` | Custom Omarchy theme using TradersPost's real brand palette (pulled from traderspost.io's CSS — see `colors.toml` comments for which values are verified brand colors vs. filled in) and a wallpaper combining an AI-generated futuristic candlestick-chart background with the real TradersPost logo composited on top |
| `bash/bashrc` | Kept as a fallback for non-interactive/bash-specific tooling (sources Arch bootstrap, then `shell/env.sh`); zsh is the default login shell |
| `environment.d/10-omarchy-fcitx.conf` | Empty on purpose — shadows Omarchy's same-named file so its `QT_IM_MODULE`/`XMODIFIERS`/`SDL_IM_MODULE=fcitx` never get set. fcitx5 existed only to expand `~/.XCompose`, whose sequences were written by Omarchy's installer and never used, so the XCompose file, the fcitx5 service (masked by `install.sh`) and these variables were all removed together |
| `etc/modprobe.d/hid_apple.conf` | `fnmode=1` so the Apple keyboard's F-row acts as media/brightness keys by default (macOS-style); hold Fn for literal F1-F12 |
| `etc/modprobe.d/hid_magicmouse.conf` | Keeps native Magic Mouse clicks but disables kernel wheel emulation (`emulate_scroll_wheel=0`) so surface scrolling comes from `magicmouse-scroll`'s virtual touchpad instead of stacking with it |
| `etc/modules-load.d/uinput.conf` | Loads the `uinput` module at boot. It is not builtin and nothing else pulls it in, and it cannot autoload on demand because opening a char device whose driver is not registered just fails. Without it `99-uinput.rules` below is dead too: udev applies GROUP/MODE when it processes the device's uevent, so with no module there is no device, no uevent, and the node stays `root:root 0600` |
| `etc/udev/rules.d/99-uinput.rules` | Lets the scroll observer create its virtual touchpad as the normal user; physical pointer and button events never use it |
| `etc/udev/rules.d/70-magic-mouse.rules` | Gives the active seat user an ACL on the Magic Mouse's raw HID node so the gesture daemon can read it without root — replaces upstream's world-readable `MODE="0666"` rule |
| `magicmouse-scroll/` | Non-exclusive, scroll-only Magic Mouse observer — this is what gives the mouse momentum/kinetic scrolling. Pointer motion and buttons go directly to Hyprland; only surface motion is emitted, as a Dell-XPS-shaped virtual touchpad |
| `magic-mouse-gestures/` | Vendored fork of [brenoperucchi/magic-mouse-gestures](https://github.com/brenoperucchi/magic-mouse-gestures) (MIT) — two-finger horizontal swipes become `Alt+Left`/`Alt+Right`. Forked so it installs by symlink like everything else here instead of upstream's `sudo`-and-`/opt` installer, and so the defaults can be edited in place; see [its README](magic-mouse-gestures/README.md) |
| `dconf/interface.ini` | GTK/GNOME interface settings (theme, cursor, `text-scaling-factor`) — dconf lives in a private binary database, not a plain file, so this is a `dconf dump`/`dconf load` snapshot rather than a symlink; `install.sh` applies it with `dconf load` |

macOS only:

| Path | What it is |
|---|---|
| `mac/build-chrome-theme.sh` | Builds Chrome theme icons + new-tab wallpaper from `traderspost.png` |
| `mac/chrome/traderspost-theme/` | Unpacked Google Chrome theme (load once from `~/Documents/traderspost-chrome-theme`) |
| `mac/build-terminal-profile.swift` | Builds `traderspost.terminal` from `traderspost.itermcolors` (required on macOS 26+) |
| `mac/apply-theme.sh` | Dark mode, blue accent, Terminal profile build/import/default (`install.sh` calls this) |
| `mac/traderspost.terminal` | Terminal.app profile (imported from `~/Documents/traderspost.terminal`) |
| `mac/traderspost.itermcolors` | Optional iTerm2 preset if iTerm is installed |
| `mac/README.md` | What macOS can and cannot theme vs Omarchy |

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

On Linux, `install.sh` will prompt for `sudo` once to install
`etc/modprobe.d/*.conf` and `etc/udev/rules.d/*` into `/etc` (everything else
it does needs no elevated privileges).

Those four files are **copied, not symlinked**, unlike everything else here,
and it matters. `/home` is its own btrfs subvolume mounted at the Local File
Systems target, but kmod and udev read their config directories before that,
so a symlink into `$HOME` is still dangling when they look:

```
libkmod: ERROR: conf_files_filter_out: Cannot stat directory entry:
         /etc/modprobe.d/hid_apple.conf
```

kmod skips the whole file and the module gets kernel defaults — which is how
`hid_apple` ran at `fnmode=3` while `fnmode=1` sat here looking applied.
`hid_magicmouse` escaped it only because a Bluetooth mouse connects long
after `/home` is mounted, and the udev rules only because udev had re-read
its rules since boot.

Two consequences. Editing one of these files in the repo no longer changes
the installed copy, so **re-run `install.sh` after editing one**. And
installing it still doesn't apply a changed kernel module option — reload the
module or reboot:

```sh
sudo rmmod hid_apple && sudo modprobe hid_apple
```

Check that an option actually took, rather than assuming:

```sh
cat /sys/module/hid_apple/parameters/fnmode      # want 1, not the kernel's 3
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

### Magic Mouse

**Agents:** both halves of Magic Mouse support are tracked here now and
`install.sh` symlinks both — a new machine gets them from this repo, with
no upstream installer involved. `magic-mouse-gestures/` is a **vendored
fork** of [brenoperucchi/magic-mouse-gestures](https://github.com/brenoperucchi/magic-mouse-gestures)
(MIT); its own [README](magic-mouse-gestures/README.md) records the fork
commit, every local change, and how to re-sync with upstream. Read that
before editing the daemon.

The surface is split by finger count, and the two daemons never overlap:

| Fingers | Owner | Result |
|---|---|---|
| 1 | `magicmouse-scroll/` | scroll, with kinetic fling |
| 2 | `magic-mouse-gestures/` | `Alt+Left` / `Alt+Right` (browser Back/Forward) |

That split is load-bearing in both directions. `MIN_FINGERS = 2` in the
fork keeps the gesture daemon off one-finger scrolling (upstream defaults
to 1, which fires Back constantly — a finger rests on that surface
whenever the mouse moves), and `MAX_SCROLL_CONTACTS = 1` in
`scroll_observer.py` keeps the scroll observer off two-finger swipes.
Without both, one two-finger flick would scroll sideways *and* navigate
back. Neither daemon grabs the device (one reads evdev, the other hidraw,
both non-exclusively), so they coexist and the physical mouse keeps
delivering its own pointer motion and clicks. Neither emits the other's
event type: the gesture daemon sends no scroll events at all, which is why
momentum has to come from `magicmouse-scroll/`.

`install.sh` only installs files — it never starts units. Enable them once per
machine, after installing `python` and `wtype` from `pacman`:

```sh
systemctl --user daemon-reload
systemctl --user enable --now magicmouse-scroll magic-mouse-gestures
```

`etc/udev/rules.d/70-magic-mouse.rules` is what lets the gesture daemon
read the mouse's raw HID node as a normal user. It replaces upstream's
`99-magic-mouse.rules`, which set `MODE="0666"` and exposed every touch
and button to any local process; a per-user ACL is enough. The number
matters — the rule must sort below `73-seat-late.rules`, which is what
turns the `uaccess` tag into an ACL, so a `99-` file adds it too late.
`MODE` is stated explicitly because udev only applies a mode when a rule
asks for one, so dropping upstream's `0666` rule does **not** by itself
take world access back off a node that already exists.

This rule is copied into `/etc`, not symlinked (see [Install](#install)), so
re-run `install.sh` after editing it and then apply the change with `udevadm
control --reload-rules && udevadm trigger --action=add
--subsystem-match=hidraw`, which avoids a Bluetooth reconnect. On a node created before the swap, fix the leftover mode with
`setfacl -m u:$USER:rw /dev/hidrawN` — not `chmod`, which zeroes the ACL
mask and silently nullifies the ACL (`getfacl` then shows `#effective:---`
while an already-running daemon keeps working off its open fd, so it looks
fine until the next restart). Verify with `getfacl`: want `other::---` and
no `#effective:---`.

Why a virtual touchpad rather than synthesized fling: `hid-magicmouse`
digests the surface into plain wheel ticks (`REL_WHEEL`), and GTK/Chromium/
Qt only apply inertia to finger-source scroll from a real multitouch
device. Replaying touches through a uinput multitouch touchpad — shaped to
the XPS's measured geometry — makes libinput report finger-source scroll
with a true touch-end, so the toolkits supply the fling themselves. An
earlier revision hand-rolled a decay curve instead; that is what `be2c504`
replaced, and the toolkit path feels closer to macOS.

This is also why `etc/modprobe.d/hid_magicmouse.conf` sets
`emulate_scroll_wheel=0` and why that file owns the module options.
Upstream ships its own `modprobe/hid-magicmouse.conf`, deliberately not
vendored into the fork: two `options` lines for one module leave the
winner decided by which filename sorts last in `/etc/modprobe.d` (`-`
before `_`). If a machine somehow has both, delete the upstream copy. The parameter is runtime-writable, so it can be flipped
without `rmmod`/`modprobe` or a Bluetooth reconnect:

```sh
echo 0 | sudo tee /sys/module/hid_magicmouse/parameters/emulate_scroll_wheel
```

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
