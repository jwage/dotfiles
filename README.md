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
| `git/config` | Git aliases and behavior (not credentials — see note in the file) |
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

After installing on a fresh machine, also run:

```sh
gh auth login
gh auth setup-git
```

to restore the git credential helper (see the note in `git/config`).
