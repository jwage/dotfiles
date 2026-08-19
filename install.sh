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

# Root-owned system config (kernel module options). Linux only -- macOS has
# no modprobe.d equivalent. Needs sudo, unlike everything else here, so it's
# kept separate from link_one. Only symlinks: reload the module yourself
# (rmmod/modprobe, or reboot) for a changed option to actually take effect --
# doing that automatically here could yank input out from under whoever's
# running this script with that exact keyboard/mouse.
if [[ "$OS" != "Darwin" ]]; then
  for entry in \
    "etc/modprobe.d/hid_apple.conf:/etc/modprobe.d/hid_apple.conf" \
    "etc/modprobe.d/hid_magicmouse.conf:/etc/modprobe.d/hid_magicmouse.conf"
  do
    src="$REPO_DIR/${entry%%:*}"
    dest="${entry#*:}"
    if [[ -L "$dest" && "$(sudo realpath "$dest" 2>/dev/null)" == "$(realpath "$src")" ]]; then
      echo "ok      $dest"
      continue
    fi
    if sudo test -e "$dest" -o -L "$dest"; then
      sudo mv "$dest" "$dest.orig"
      echo "backed up $dest -> $dest.orig"
    fi
    sudo ln -sf "$src" "$dest"
    echo "linked  $dest -> $src (reload the module or reboot to apply)"
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
# be installed; `install.sh` looks for the `cursor` CLI. Safe to re-run:
# already-installed extensions are left as-is. Failures are printed (do not
# hide them) so a missing Twig/PHP extension on a new machine is obvious.
CURSOR_BIN=""
if command -v cursor >/dev/null 2>&1; then
  CURSOR_BIN="$(command -v cursor)"
else
  for candidate in \
    "/Applications/Cursor.app/Contents/Resources/app/bin/cursor" \
    "$HOME/.local/share/cursor/bin/cursor" \
    "$HOME/.local/bin/cursor" \
    "$HOME/.cursor/bin/cursor" \
    "/usr/bin/cursor" \
    "/opt/cursor/cursor" \
    "/opt/Cursor/cursor"
  do
    if [[ -x "$candidate" ]]; then
      CURSOR_BIN="$candidate"
      break
    fi
  done
fi

if [[ -n "$CURSOR_BIN" ]]; then
  echo "cursor  $CURSOR_BIN"
  while IFS= read -r extension || [[ -n "$extension" ]]; do
    [[ -z "$extension" || "$extension" == \#* ]] && continue
    if "$CURSOR_BIN" --install-extension "$extension"; then
      echo "ext ok  $extension"
    else
      echo "ext FAIL $extension" >&2
    fi
  done < "$REPO_DIR/cursor/extensions.txt"
else
  echo "skip    cursor extensions (cursor CLI not found — install Cursor, then re-run)"
fi
