#!/bin/bash
# Symlinks each file in this repo to its real location under $HOME,
# backing up whatever is already there (once) as <file>.orig.
#
# Safe to re-run: if the destination is already the correct symlink, it's
# left alone. A destination that isn't a symlink gets backed up before being
# replaced.
#
# Shared files (Cursor, git, gh, mise, ssh, Claude, shell env, zsh) install on
# both macOS and Linux. Hyprland / Omarchy / XCompose / bashrc only install
# on Linux (bash is kept there as a fallback for non-interactive/bash-specific
# tooling; zsh is the default login shell on both machines).

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS="$(uname -s)"

if [[ "$OS" == "Darwin" ]]; then
  CURSOR_USER="$HOME/Library/Application Support/Cursor/User"
else
  CURSOR_USER="$HOME/.config/Cursor/User"
fi

link_one() {
  local src="$REPO_DIR/${1%%:*}"
  local dest="${1#*:}"

  if [[ -L "$dest" && "$(realpath "$dest")" == "$(realpath "$src")" ]]; then
    echo "ok      $dest"
    return
  fi

  mkdir -p "$(dirname "$dest")"

  if [[ -e "$dest" || -L "$dest" ]]; then
    mv "$dest" "$dest.orig"
    echo "backed up $dest -> $dest.orig"
  fi

  ln -s "$src" "$dest"
  echo "linked  $dest -> $src"
}

# Portable across macOS and Linux.
SHARED_LINKS=(
  "cursor/settings.json:$CURSOR_USER/settings.json"
  "cursor/keybindings.json:$CURSOR_USER/keybindings.json"
  "claude/CLAUDE.md:$HOME/.claude/CLAUDE.md"
  "gh/config.yml:$HOME/.config/gh/config.yml"
  "mise/config.toml:$HOME/.config/mise/config.toml"
  "ssh/config:$HOME/.ssh/config"
  "zsh/zshrc:$HOME/.zshrc"
  "starship/starship.toml:$HOME/.config/starship.toml"
)

# Omarchy / Hyprland / bash fallback. Never install these on macOS.
LINUX_LINKS=(
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
)

for entry in "${SHARED_LINKS[@]}"; do
  link_one "$entry"
done

if [[ "$OS" == "Darwin" ]]; then
  echo "skip    Linux-only Hyprland/Omarchy/bashrc/XCompose"
else
  for entry in "${LINUX_LINKS[@]}"; do
    link_one "$entry"
  done
fi

# git/config is NOT symlinked: `gh auth setup-git` writes a machine-specific
# credential helper into it, and a plain symlink would put that straight into
# the tracked repo file. Instead the live file just [include]s the tracked
# one, leaving room for local-only additions (like the credential helper)
# below the include.
#
# On macOS, ~/.gitconfig is left alone (git-lfs, a different user.email,
# extra safe.directory entries). Git still reads ~/.config/git/config, and
# ~/.gitconfig wins on overlapping keys.
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

# Extensions are installed by ID, not symlinked. Cursor itself must already
# be on PATH (`cursor`). Safe to re-run: already-installed extensions are
# left as-is.
CURSOR_BIN=""
if command -v cursor >/dev/null 2>&1; then
  CURSOR_BIN="cursor"
elif [[ -x "/Applications/Cursor.app/Contents/Resources/app/bin/cursor" ]]; then
  CURSOR_BIN="/Applications/Cursor.app/Contents/Resources/app/bin/cursor"
fi

if [[ -n "$CURSOR_BIN" ]]; then
  while IFS= read -r extension || [[ -n "$extension" ]]; do
    [[ -z "$extension" || "$extension" == \#* ]] && continue
    echo "ext     $extension"
    "$CURSOR_BIN" --install-extension "$extension" >/dev/null
  done < "$REPO_DIR/cursor/extensions.txt"
else
  echo "skip    cursor extensions (cursor CLI not found)"
fi
