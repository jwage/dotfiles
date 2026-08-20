#!/bin/bash
# Build Chrome theme assets (icons + frame/toolbar/tab/ntp images).
# Uses visibly blue brand colors (#0984e3 / #34c3ff) — dark navy reads as gray.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THEME_DIR="$REPO_DIR/mac/chrome/traderspost-theme"
WALLPAPER="$REPO_DIR/omarchy/themes/traderspost/backgrounds/traderspost.png"
ICONS_DIR="$THEME_DIR/icons"
IMAGES_DIR="$THEME_DIR/images"

mkdir -p "$ICONS_DIR" "$IMAGES_DIR"

python3 - <<PY
import struct
import zlib
from pathlib import Path

theme_dir = Path("${THEME_DIR}")
images = theme_dir / "images"
images.mkdir(parents=True, exist_ok=True)

# TradersPost brand from colors.toml
PRIMARY = (9, 132, 227)       # #0984e3
PRIMARY_DARK = (9, 84, 160)
CYAN = (52, 195, 255)         # #34c3ff
NAVY = (9, 40, 90)            # blue-tinted tab strip (not flat gray)
DARK = (14, 20, 26)           # #0e141a
INSET = (21, 31, 39)          # #151f27


def write_png(path: Path, width: int, height: int, rgb: tuple[int, int, int]) -> None:
    red, green, blue = rgb
    row = b"\x00" + bytes([red, green, blue]) * width
    raw = row * height

    def chunk(tag: bytes, data: bytes) -> bytes:
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    path.write_bytes(png)


def write_gradient_png(
    path: Path,
    width: int,
    height: int,
    top: tuple[int, int, int],
    bottom: tuple[int, int, int],
) -> None:
    rows = []
    for y in range(height):
        t = y / max(height - 1, 1)
        rgb = tuple(
            int(top[index] + (bottom[index] - top[index]) * t)
            for index in range(3)
        )
        rows.append(b"\x00" + bytes(rgb) * width)
    raw = b"".join(rows)

    def chunk(tag: bytes, data: bytes) -> bytes:
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    path.write_bytes(png)


write_png(images / "theme_frame.png", 800, 36, NAVY)
write_gradient_png(images / "theme_toolbar.png", 800, 88, PRIMARY, PRIMARY_DARK)
write_png(images / "theme_tab_background.png", 256, 36, DARK)
write_png(images / "theme_tab_background_inactive.png", 256, 36, DARK)
write_png(images / "theme_button_background.png", 64, 64, CYAN)
PY

if [[ -f "$WALLPAPER" ]]; then
  for size in 16 48 128; do
    sips -z "$size" "$size" "$WALLPAPER" --out "$ICONS_DIR/icon${size}.png" >/dev/null
  done
  sips -Z 1200 "$WALLPAPER" --out "$IMAGES_DIR/ntp_background.png" >/dev/null
else
  python3 - <<PY
import struct
import zlib
from pathlib import Path

path = Path("${IMAGES_DIR}") / "ntp_background.png"

def write_png(path, width, height, rgb):
    red, green, blue = rgb
    row = b"\x00" + bytes([red, green, blue]) * width
    raw = row * height
    def chunk(tag, data):
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    path.write_bytes(png)

write_png(path, 1920, 1080, (14, 20, 26))
PY
fi

required=(
  "$THEME_DIR/manifest.json"
  "$THEME_DIR/background.js"
  "$ICONS_DIR/icon16.png"
  "$ICONS_DIR/icon48.png"
  "$ICONS_DIR/icon128.png"
  "$IMAGES_DIR/theme_frame.png"
  "$IMAGES_DIR/theme_toolbar.png"
  "$IMAGES_DIR/theme_tab_background.png"
  "$IMAGES_DIR/ntp_background.png"
)

for file in "${required[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "fail    missing Chrome theme asset: $file" >&2
    exit 1
  fi
done

echo "built   Chrome theme assets in $THEME_DIR"
