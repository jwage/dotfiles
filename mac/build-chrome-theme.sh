#!/bin/bash
# Build Chrome theme icons and new-tab background from the TradersPost wallpaper.
# Safe to re-run; writes into mac/chrome/traderspost-theme/.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THEME_DIR="$REPO_DIR/mac/chrome/traderspost-theme"
WALLPAPER="$REPO_DIR/omarchy/themes/traderspost/backgrounds/traderspost.png"
ICONS_DIR="$THEME_DIR/icons"
IMAGES_DIR="$THEME_DIR/images"

mkdir -p "$ICONS_DIR" "$IMAGES_DIR"

if [[ ! -f "$WALLPAPER" ]]; then
  echo "skip    Chrome theme assets (wallpaper missing at $WALLPAPER)" >&2
  exit 0
fi

for size in 16 48 128; do
  sips -z "$size" "$size" "$WALLPAPER" --out "$ICONS_DIR/icon${size}.png" >/dev/null
done

sips -Z 1200 "$WALLPAPER" --out "$IMAGES_DIR/ntp_background.png" >/dev/null

echo "built   Chrome theme icons + ntp_background.png"
