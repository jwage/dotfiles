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
  "hypr/monitors.lua:$HOME/.config/hypr/monitors.lua"
  "foot/foot.ini:$HOME/.config/foot/foot.ini"
  "omarchy/shell.json:$HOME/.config/omarchy/shell.json"
  "omarchy/shell.toml:$HOME/.config/omarchy/shell.toml"
  "omarchy/defaults/agent:$HOME/.config/omarchy/defaults/agent"
  "omarchy/plugins/jwage.workspaces/manifest.json:$HOME/.config/omarchy/plugins/jwage.workspaces/manifest.json"
  "omarchy/plugins/jwage.workspaces/Workspaces.qml:$HOME/.config/omarchy/plugins/jwage.workspaces/Workspaces.qml"
  "omarchy/plugins/jwage.workspaces/find-agent-process:$HOME/.config/omarchy/plugins/jwage.workspaces/find-agent-process"
  "omarchy/plugins/jwage.battery-sleep/manifest.json:$HOME/.config/omarchy/plugins/jwage.battery-sleep/manifest.json"
  "omarchy/plugins/jwage.battery-sleep/Service.qml:$HOME/.config/omarchy/plugins/jwage.battery-sleep/Service.qml"
  "omarchy/plugins/jwage.clock/manifest.json:$HOME/.config/omarchy/plugins/jwage.clock/manifest.json"
  "omarchy/plugins/jwage.clock/BarWidget.qml:$HOME/.config/omarchy/plugins/jwage.clock/BarWidget.qml"
  "omarchy/plugins/jwage.clock/Model.js:$HOME/.config/omarchy/plugins/jwage.clock/Model.js"
  "omarchy/plugins/jwage.clock/Panel.qml:$HOME/.config/omarchy/plugins/jwage.clock/Panel.qml"
  "omarchy/themes/traderspost/colors.toml:$HOME/.config/omarchy/themes/traderspost/colors.toml"
  "omarchy/themes/traderspost/backgrounds/traderspost.png:$HOME/.config/omarchy/themes/traderspost/backgrounds/traderspost.png"
  "magicmouse-scroll/daemon.py:$HOME/.local/bin/magicmouse-scroll-daemon"
  "magicmouse-scroll/magicmouse-scroll.service:$HOME/.config/systemd/user/magicmouse-scroll.service"
  "bluetooth-hid-reconnect/reconnect.sh:$HOME/.local/bin/bluetooth-hid-reconnect"
  "bluetooth-hid-reconnect/bluetooth-hid-reconnect.service:$HOME/.config/systemd/user/bluetooth-hid-reconnect.service"
  "bash/bashrc:$HOME/.bashrc"
  "XCompose:$HOME/.XCompose"
  "environment.d/ssh-agent.conf:$HOME/.config/environment.d/ssh-agent.conf"
)

for entry in "${SHARED_LINKS[@]}"; do
  link_one "$entry"
done

if [[ "$OS" == "Darwin" ]]; then
  echo "skip    Linux-only Hyprland/Omarchy/bashrc/XCompose"
  # Same TradersPost wallpaper as the Omarchy theme -- PNG only; colors.toml
  # is Hyprland/Omarchy-specific and stays Linux-only above.
  MAC_WALLPAPER="$HOME/Pictures/Wallpapers/traderspost.png"
  link_one "omarchy/themes/traderspost/backgrounds/traderspost.png:$MAC_WALLPAPER"
  if osascript -e "tell application \"System Events\" to tell every desktop to set picture to \"$(realpath "$MAC_WALLPAPER")\""; then
    echo "set     macOS desktop wallpaper -> $MAC_WALLPAPER"
  else
    echo "skip    macOS desktop wallpaper (osascript failed -- pick $MAC_WALLPAPER in System Settings)" >&2
  fi
  bash "$REPO_DIR/mac/apply-theme.sh"
else
  for entry in "${LINUX_LINKS[@]}"; do
    link_one "$entry"
  done
fi

# Root-owned system config (kernel module options, udev rules). Linux only
# -- macOS has no modprobe.d/udev equivalent. Needs sudo, unlike everything
# else here, so it's kept separate from link_one. Only symlinks: reload the
# module/udev rules yourself (rmmod+modprobe, udevadm control --reload-rules,
# or reboot) for a changed option to actually take effect -- doing that
# automatically here could yank input out from under whoever's running this
# script with that exact keyboard/mouse.
if [[ "$OS" != "Darwin" ]]; then
  for entry in \
    "etc/modprobe.d/hid_apple.conf:/etc/modprobe.d/hid_apple.conf" \
    "etc/modprobe.d/hid_magicmouse.conf:/etc/modprobe.d/hid_magicmouse.conf" \
    "etc/udev/rules.d/99-uinput.rules:/etc/udev/rules.d/99-uinput.rules"
  do
    src="$REPO_DIR/${entry%%:*}"
    dest="${entry#*:}"
    if [[ -L "$dest" && "$(sudo realpath "$dest" 2>/dev/null)" == "$(realpath "$src")" ]]; then
      echo "ok      $dest"
      continue
    fi
    # sudo can't prompt for a password without a TTY (e.g. run from an
    # agent) -- report and move on instead of letting set -e abort the
    # rest of the script (dconf, git/config, Cursor extensions) over a
    # skippable step the user can just rerun from a real terminal.
    if ! sudo -n true 2>/dev/null && [[ ! -t 0 ]]; then
      echo "skip    $dest (sudo needs a password and no TTY is available; rerun from a terminal)"
      continue
    fi
    if sudo test -e "$dest" -o -L "$dest"; then
      sudo mv "$dest" "$dest.orig"
      echo "backed up $dest -> $dest.orig"
    fi
    sudo ln -sf "$src" "$dest"
    echo "linked  $dest -> $src (reload the module/udev rules or reboot to apply)"
  done
fi

# dconf/GSettings live in a private binary database (~/.config/dconf/user),
# not a plain file, so there's nothing to symlink -- dump/load is the
# standard way to version-control it. Safe to always re-apply: same values
# in, no-op; this only covers the interface keys we've deliberately tuned
# (text scaling, theme, cursor), not a full dconf dump.
if [[ "$OS" != "Darwin" ]] && command -v dconf >/dev/null; then
  dconf load /org/gnome/desktop/interface/ < "$REPO_DIR/dconf/interface.ini"
  echo "loaded  /org/gnome/desktop/interface/ <- dconf/interface.ini"
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

echo "PHP:     run $REPO_DIR/php/setup.sh for host PHP + extensions (php/README.md)"
