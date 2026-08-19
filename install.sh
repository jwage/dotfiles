#!/bin/bash
# Symlinks each file in this repo to its real location under $HOME,
# backing up whatever is already there (once) as <file>.orig.
#
# Safe to re-run: if the destination is already the correct symlink, it's
# left alone. A destination that isn't a symlink gets backed up before being
# replaced.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# repo path -> destination path
LINKS=(
  "hypr/bindings.lua:$HOME/.config/hypr/bindings.lua"
  "hypr/input.lua:$HOME/.config/hypr/input.lua"
  "hypr/hyprland.lua:$HOME/.config/hypr/hyprland.lua"
  "hypr/looknfeel.lua:$HOME/.config/hypr/looknfeel.lua"
  "hypr/autostart.lua:$HOME/.config/hypr/autostart.lua"
  "omarchy/shell.json:$HOME/.config/omarchy/shell.json"
  "omarchy/defaults/agent:$HOME/.config/omarchy/defaults/agent"
  "omarchy/plugins/jwage.workspaces/manifest.json:$HOME/.config/omarchy/plugins/jwage.workspaces/manifest.json"
  "omarchy/plugins/jwage.workspaces/Workspaces.qml:$HOME/.config/omarchy/plugins/jwage.workspaces/Workspaces.qml"
  "omarchy/plugins/jwage.battery-sleep/manifest.json:$HOME/.config/omarchy/plugins/jwage.battery-sleep/manifest.json"
  "omarchy/plugins/jwage.battery-sleep/Service.qml:$HOME/.config/omarchy/plugins/jwage.battery-sleep/Service.qml"
  "bash/bashrc:$HOME/.bashrc"
  "XCompose:$HOME/.XCompose"
  "claude/CLAUDE.md:$HOME/.claude/CLAUDE.md"
  "gh/config.yml:$HOME/.config/gh/config.yml"
  "mise/config.toml:$HOME/.config/mise/config.toml"
  "ssh/config:$HOME/.ssh/config"
  "cursor/keybindings.json:$HOME/.config/Cursor/User/keybindings.json"
)

for entry in "${LINKS[@]}"; do
  src="$REPO_DIR/${entry%%:*}"
  dest="${entry#*:}"

  if [[ -L "$dest" && "$(readlink -f "$dest")" == "$(readlink -f "$src")" ]]; then
    echo "ok      $dest"
    continue
  fi

  mkdir -p "$(dirname "$dest")"

  if [[ -e "$dest" || -L "$dest" ]]; then
    mv "$dest" "$dest.orig"
    echo "backed up $dest -> $dest.orig"
  fi

  ln -s "$src" "$dest"
  echo "linked  $dest -> $src"
done

# git/config is NOT symlinked: `gh auth setup-git` writes a machine-specific
# credential helper into it, and a plain symlink would put that straight into
# the tracked repo file. Instead the live file just [include]s the tracked
# one, leaving room for local-only additions (like the credential helper)
# below the include.
GIT_CONFIG="$HOME/.config/git/config"
if [[ ! -f "$GIT_CONFIG" ]] || ! grep -qF "$REPO_DIR/git/config" "$GIT_CONFIG"; then
  if [[ -e "$GIT_CONFIG" || -L "$GIT_CONFIG" ]]; then
    mv "$GIT_CONFIG" "$GIT_CONFIG.orig"
    echo "backed up $GIT_CONFIG -> $GIT_CONFIG.orig"
  fi
  mkdir -p "$(dirname "$GIT_CONFIG")"
  cat > "$GIT_CONFIG" <<EOF
# Machine-local additions only (credential helpers, etc.) go below this
# include — everything portable lives in the dotfiles repo itself. See
# $REPO_DIR/git/config and its README for why these two are kept separate.
[include]
	path = $REPO_DIR/git/config
EOF
  echo "wrote   $GIT_CONFIG (includes $REPO_DIR/git/config)"
else
  echo "ok      $GIT_CONFIG"
fi
