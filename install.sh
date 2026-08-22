#!/bin/bash
# Symlinks each file in this repo to its real location under $HOME,
# backing up whatever is already there (once) as <file>.orig.
#
# Root-owned system config under /etc is the exception: it is copied, not
# symlinked, because kmod and udev read those directories before /home is
# mounted. See the comment on that block below. Re-run this script after
# editing one of those files.
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
  "webapps/Gmail Work.desktop:$HOME/.local/share/applications/Gmail Work.desktop"
  "webapps/Gmail Personal.desktop:$HOME/.local/share/applications/Gmail Personal.desktop"
  "webapps/gmail.png:$HOME/.local/share/icons/hicolor/256x256/apps/gmail.png"
  "omarchy/plugins/jwage.workspaces/manifest.json:$HOME/.config/omarchy/plugins/jwage.workspaces/manifest.json"
  "omarchy/plugins/jwage.workspaces/Workspaces.qml:$HOME/.config/omarchy/plugins/jwage.workspaces/Workspaces.qml"
  "omarchy/plugins/jwage.workspaces/find-agent-process:$HOME/.config/omarchy/plugins/jwage.workspaces/find-agent-process"
  "omarchy/plugins/jwage.battery-sleep/manifest.json:$HOME/.config/omarchy/plugins/jwage.battery-sleep/manifest.json"
  "omarchy/plugins/jwage.battery-sleep/Service.qml:$HOME/.config/omarchy/plugins/jwage.battery-sleep/Service.qml"
  "omarchy/plugins/jwage.clock/manifest.json:$HOME/.config/omarchy/plugins/jwage.clock/manifest.json"
  "omarchy/plugins/jwage.traderspost/manifest.json:$HOME/.config/omarchy/plugins/jwage.traderspost/manifest.json"
  "omarchy/plugins/jwage.traderspost/BarWidget.qml:$HOME/.config/omarchy/plugins/jwage.traderspost/BarWidget.qml"
  "omarchy/plugins/jwage.traderspost/Panel.qml:$HOME/.config/omarchy/plugins/jwage.traderspost/Panel.qml"
  "omarchy/plugins/jwage.traderspost/Model.js:$HOME/.config/omarchy/plugins/jwage.traderspost/Model.js"
  "omarchy/plugins/jwage.traderspost/traderspost-health:$HOME/.config/omarchy/plugins/jwage.traderspost/traderspost-health"
  "omarchy/plugins/jwage.clock/BarWidget.qml:$HOME/.config/omarchy/plugins/jwage.clock/BarWidget.qml"
  "omarchy/plugins/jwage.clock/Model.js:$HOME/.config/omarchy/plugins/jwage.clock/Model.js"
  "omarchy/plugins/jwage.clock/Panel.qml:$HOME/.config/omarchy/plugins/jwage.clock/Panel.qml"
  "omarchy/themes/traderspost/colors.toml:$HOME/.config/omarchy/themes/traderspost/colors.toml"
  "omarchy/themes/traderspost/backgrounds/traderspost.png:$HOME/.config/omarchy/themes/traderspost/backgrounds/traderspost.png"
  "magicmouse-scroll/scroll_observer.py:$HOME/.local/bin/magicmouse-scroll-observer"
  "magicmouse-scroll/magicmouse-scroll.service:$HOME/.config/systemd/user/magicmouse-scroll.service"
  "magic-mouse-gestures/magic_mouse_gestures.py:$HOME/.local/bin/magic-mouse-gestures"
  "magic-mouse-gestures/magic-mouse-gestures.service:$HOME/.config/systemd/user/magic-mouse-gestures.service"
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

  # hicolor already carries a gtk icon cache (omarchy-webapp-install writes
  # one), and a stale cache hides a newly linked icon from Qt's theme lookup
  # entirely -- which is the difference between the Gmail app windows showing
  # their real icon in the bar and falling back to the generic executable
  # glyph. Cheap and idempotent, so just always refresh it.
  if command -v gtk-update-icon-cache >/dev/null; then
    gtk-update-icon-cache "$HOME/.local/share/icons/hicolor" &>/dev/null || true
    echo "cached  $HOME/.local/share/icons/hicolor"
  fi
fi

# Root-owned system config (kernel module options, udev rules). Linux only
# -- macOS has no modprobe.d/udev equivalent. Needs sudo, unlike everything
# else here, so it's kept separate from link_one.
#
# Copied rather than symlinked, and that part is load-bearing. /home is its
# own btrfs subvolume mounted at the Local File Systems target, but kmod and
# udev read their config directories well before that -- systemd-modules-load
# and systemd-udevd both run while a symlink into $HOME is still dangling.
# kmod does not fail quietly about it either:
#
#   libkmod: ERROR: conf_files_filter_out: Cannot stat directory entry:
#            /etc/modprobe.d/hid_apple.conf
#
# It skips the whole file and the module falls back to kernel defaults. That
# is how hid_apple ran at fnmode=3 while fnmode=1 sat in this repo looking
# applied. hid_magicmouse got away with the same bug only because a Bluetooth
# mouse connects long after /home is mounted; tether one over USB at boot and
# its options disappear the same way. The udev rules are no safer -- both
# happened to be live only because udev had re-read its rules since boot. A
# plain file under /etc is readable from the moment root is mounted, which is
# earlier than any reader here.
#
# The tradeoff is that editing a file in this repo no longer changes the
# installed copy: re-run this script after editing one. Applying a changed
# option still needs a module or udev reload (rmmod+modprobe, udevadm control
# --reload-rules, or a reboot). This script deliberately does not do that for
# you -- it could yank input out from under whoever is running it with that
# exact keyboard or mouse.
if [[ "$OS" != "Darwin" ]]; then
  for entry in \
    "etc/modprobe.d/hid_apple.conf:/etc/modprobe.d/hid_apple.conf" \
    "etc/modprobe.d/hid_magicmouse.conf:/etc/modprobe.d/hid_magicmouse.conf" \
    "etc/udev/rules.d/99-uinput.rules:/etc/udev/rules.d/99-uinput.rules" \
    "etc/udev/rules.d/70-magic-mouse.rules:/etc/udev/rules.d/70-magic-mouse.rules"
  do
    src="$REPO_DIR/${entry%%:*}"
    dest="${entry#*:}"

    # Checked before the sudo probe so an already-installed machine gets
    # through this loop without asking for a password at all.
    if [[ -f "$dest" && ! -L "$dest" ]] && cmp -s "$src" "$dest"; then
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

    # A symlink at this path is an older run of this script, so there is
    # nothing in it worth preserving. Back up only a real file, which is
    # someone else's config (Omarchy writes hid_apple.conf itself).
    if sudo test -L "$dest"; then
      sudo rm "$dest"
      echo "unlinked $dest (was a symlink into this repo, which loads too late)"
    elif sudo test -e "$dest"; then
      sudo mv "$dest" "$dest.orig"
      echo "backed up $dest -> $dest.orig"
    fi

    sudo install -D -m 0644 -o root -g root "$src" "$dest"
    echo "copied  $dest (reload the module/udev rules or reboot to apply)"
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
