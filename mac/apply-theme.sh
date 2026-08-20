#!/bin/bash
# macOS TradersPost theme bits install.sh cannot symlink: system appearance,
# accent color, and an iTerm2 preset path. Palette values match
# omarchy/themes/traderspost/colors.toml.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "skip    mac/apply-theme.sh (not macOS)"
  exit 0
fi

# Dark mode + blue accent (closest preset to --color-primary-500 / #0984e3).
defaults write -g AppleInterfaceStyle Dark 2>/dev/null || true
defaults write -g AppleAccentColor -int 5 2>/dev/null || true

if osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true' 2>/dev/null; then
  echo "set     macOS appearance -> Dark, accent -> Blue"
else
  echo "set     macOS appearance defaults (log out/in if accent does not update)"
fi

ITERM_PRESET="$HOME/Documents/traderspost.itermcolors"
mkdir -p "$(dirname "$ITERM_PRESET")"
if [[ -L "$ITERM_PRESET" && "$(realpath "$ITERM_PRESET")" == "$(realpath "$REPO_DIR/mac/traderspost.itermcolors")" ]]; then
  echo "ok      $ITERM_PRESET"
elif [[ -e "$ITERM_PRESET" || -L "$ITERM_PRESET" ]]; then
  mv "$ITERM_PRESET" "$ITERM_PRESET.orig"
  echo "backed up $ITERM_PRESET -> $ITERM_PRESET.orig"
  ln -s "$REPO_DIR/mac/traderspost.itermcolors" "$ITERM_PRESET"
  echo "linked  $ITERM_PRESET -> $REPO_DIR/mac/traderspost.itermcolors"
else
  ln -s "$REPO_DIR/mac/traderspost.itermcolors" "$ITERM_PRESET"
  echo "linked  $ITERM_PRESET -> $REPO_DIR/mac/traderspost.itermcolors"
fi

echo "iTerm2:  Profiles -> Colors -> Color Presets -> Import -> $ITERM_PRESET"
