# dotfiles

Personal config for my [Omarchy](https://omarchy.org) (Arch + Hyprland) setup —
tracked so a distro switch or an Omarchy reset doesn't mean starting over.

Only actual customizations are tracked here, not Omarchy's stock defaults.
Each file was diffed against Omarchy's shipped default/skel before being
added, so this repo is the *delta*, not a full config mirror.

## What's here

| Path | What it is |
|---|---|
| `hypr/*.lua` | Hyprland: keybinds, input (keyboard remaps, natural scroll), per-app workspace assignment, autostart, look & feel |
| `omarchy/shell.json` | Bar widget layout |
| `omarchy/defaults/agent` | Default coding agent |
| `omarchy/plugins/jwage.workspaces/` | Custom bar widget: per-workspace app icons + window switching |
| `omarchy/plugins/jwage.battery-sleep/` | Suspends after idle on battery only; never sleeps on AC |
| `bash/bashrc` | Shell PATH/env additions |
| `XCompose` | Compose key sequences |
| `git/config` | Git aliases and behavior (not credentials — see below) |
| `gh/config.yml` | GitHub CLI preferences |
| `mise/config.toml` | Tool version manifest |
| `ssh/config` | Host aliases |

## What's deliberately excluded

- Secrets and keys: `~/.config/mcp-secrets.env`, `~/.ssh/id_*`, `gh/hosts.yml`
- The `[credential ...]` blocks `gh auth setup-git` writes into `git/config`
  (pin an absolute path to a specific `mise`-installed `gh` version — not
  portable; just re-run `gh auth setup-git` on a fresh machine)
- Terminal emulator configs (alacritty/foot/ghostty/kitty), tmux, btop,
  starship — verified identical to Omarchy's stock skel, so a fresh install
  already gives you these

## Install

```sh
git clone https://github.com/jwage/dotfiles.git ~/Repositories/dotfiles
~/Repositories/dotfiles/install.sh
```

`install.sh` symlinks every tracked file into place, backing up whatever's
already there as `<file>.orig` first. Safe to re-run.

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
stays local and untracked.

After installing on a fresh machine, also run:

```sh
gh auth login
gh auth setup-git
```

to populate that local credential helper.
