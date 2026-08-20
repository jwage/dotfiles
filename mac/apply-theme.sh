#!/bin/bash
# macOS TradersPost theme bits install.sh cannot symlink: system appearance,
# Terminal.app profile, and optional iTerm2 preset. Palette values match
# omarchy/themes/traderspost/colors.toml.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERMINAL_PREFS="$HOME/Library/Preferences/com.apple.Terminal.plist"
TERMINAL_PROFILE_NAME="TradersPost"
TERMINAL_FALLBACK_PROFILE="Basic"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "skip    mac/apply-theme.sh (not macOS)"
  exit 0
fi

link_theme_file() {
  local repo_relative="$1"
  local dest="$2"
  local src="$REPO_DIR/$repo_relative"

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

copy_theme_dir() {
  local repo_relative="$1"
  local dest="$2"
  local src="$REPO_DIR/$repo_relative"

  mkdir -p "$(dirname "$dest")"

  if [[ -e "$dest" || -L "$dest" ]]; then
    rm -rf "$dest"
  fi

  mkdir -p "$dest"
  rsync -a --delete "$src/" "$dest/"
  echo "copied  $dest <- $src"
}

# Dark mode + blue accent (closest preset to --color-primary-500 / #0984e3).
defaults write -g AppleInterfaceStyle Dark 2>/dev/null || true
defaults write -g AppleAccentColor -int 5 2>/dev/null || true
# Blue text selection/highlight in native lists (pairs with accent).
defaults write -g AppleHighlightColor -string "5 3290559999 352321535" 2>/dev/null || true
defaults write -g AppleSidebarIconTintingEnabled -bool true 2>/dev/null || true
# Menu bar can pick up TradersPost wallpaper tint when enabled in System Settings.
defaults write -g AppleEnableMenuBarTint -bool true 2>/dev/null || true

if osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true' 2>/dev/null; then
  echo "set     macOS appearance -> Dark, accent -> Blue"
else
  echo "set     macOS appearance defaults (log out/in if accent does not update)"
fi

if ! xcrun swift "$REPO_DIR/mac/build-terminal-profile.swift"; then
  echo "skip    Terminal.app profile build failed (install Xcode Command Line Tools)" >&2
  exit 0
fi

TERMINAL_PROFILE="$HOME/Documents/traderspost.terminal"
link_theme_file "mac/traderspost.terminal" "$TERMINAL_PROFILE"

terminal_profile_exists() {
  [[ -f "$TERMINAL_PREFS" ]] \
    && /usr/libexec/PlistBuddy -c "Print :'Window Settings':$TERMINAL_PROFILE_NAME" "$TERMINAL_PREFS" >/dev/null 2>&1
}

terminal_default_profile() {
  defaults read com.apple.Terminal "Default Window Settings" 2>/dev/null || true
}

if [[ "$(terminal_default_profile)" == "$TERMINAL_PROFILE_NAME" ]] && ! terminal_profile_exists; then
  defaults write com.apple.Terminal "Default Window Settings" -string "$TERMINAL_FALLBACK_PROFILE"
  defaults write com.apple.Terminal "Startup Window Settings" -string "$TERMINAL_FALLBACK_PROFILE"
  echo "reset   Terminal.app default -> $TERMINAL_FALLBACK_PROFILE (missing $TERMINAL_PROFILE_NAME profile)"
fi

if ! terminal_profile_exists; then
  open "$TERMINAL_PROFILE"
  echo "import  Terminal.app profile -> $TERMINAL_PROFILE_NAME (opened $TERMINAL_PROFILE)"
else
  open "$TERMINAL_PROFILE"
  echo "refresh Terminal.app profile -> $TERMINAL_PROFILE_NAME"
fi

defaults write com.apple.Terminal "Default Window Settings" -string "$TERMINAL_PROFILE_NAME"
defaults write com.apple.Terminal "Startup Window Settings" -string "$TERMINAL_PROFILE_NAME"
echo "set     Terminal.app default profile -> $TERMINAL_PROFILE_NAME"

ITERM_PRESET="$HOME/Documents/traderspost.itermcolors"
if [[ -d "/Applications/iTerm.app" || -d "$HOME/Applications/iTerm.app" ]]; then
  link_theme_file "mac/traderspost.itermcolors" "$ITERM_PRESET"
  echo "iTerm2:  Profiles -> Colors -> Color Presets -> Import -> $ITERM_PRESET"
fi

if bash "$REPO_DIR/mac/build-chrome-theme.sh"; then
  CHROME_THEME="$HOME/Documents/traderspost-chrome-theme"
  copy_theme_dir "mac/chrome/traderspost-theme" "$CHROME_THEME"
  echo "chrome:  chrome://extensions -> Developer mode -> Load unpacked -> $CHROME_THEME"
  echo "chrome:  if TradersPost is already loaded, click Reload on that card (v1.2.0)"
  echo "chrome:  the toolbar should be TradersPost primary blue (#0984e3), not gray"
  echo "chrome:  turn off Settings -> Appearance -> Chrome colors (it overrides themes)"
  if [[ -d "/Applications/Google Chrome.app" ]]; then
    open -a "Google Chrome" "chrome://extensions/" 2>/dev/null || true
  fi
fi

echo "system:  Settings -> Appearance -> enable menu bar tint if the bar stays flat gray"
