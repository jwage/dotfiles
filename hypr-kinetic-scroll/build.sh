#!/bin/bash
# Builds the vendored hypr-kinetic-scroll source next to this script and
# installs the result to ~/.local/lib/hypr/hypr-kinetic-scroll.so, which is the
# path hypr/input.lua loads.
#
#   ./build.sh            release build; debug logging off
#   ./build.sh --debug    plugin:kinetic-scroll:debug defaults to 1, which
#                         appends a line per scroll event and per state change
#                         to /tmp/hypr-kinetic-scroll.log. There is no way to
#                         turn that on at runtime on 0.56.2 -- see the comment
#                         on KINETIC_DEBUG_DEFAULT in main.cpp.
#
# Re-run after any Hyprland upgrade. The plugin checks Hyprland's API hash at
# init and refuses to load when it was built against a different one, so the
# symptom of a stale build is a touchpad that stops gliding, reported in the
# Hyprland log -- not a broken session.
#
# THE INSTALL ORDER BELOW IS LOAD-BEARING. On 2026-08-22 this plugin was
# rebuilt and copied straight over the .so that the running compositor still
# had mmap'd, and Hyprland died on the spot: overwriting a mapped shared object
# in place invalidates the mapping under the process, and the next symbol
# resolution took a fatal signal inside the dynamic linker (dlsym ->
# ld-linux -> SIGSEGV -> Hyprland's crash handler -> abort). That kills every
# window in the session. So: unload first, then write to a temporary name in
# the destination directory, then rename it into place. rename(2) is atomic and
# swaps the directory entry rather than the file contents, so even a copy that
# races a running compositor cannot corrupt an inode that is still mapped.
# Never `cp` or `install` directly onto the destination path.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="$HOME/.local/lib/hypr"
DEST="$DEST_DIR/hypr-kinetic-scroll.so"

EXTRA_CXXFLAGS=""
case "${1:-}" in
  --debug) EXTRA_CXXFLAGS="-DKINETIC_DEBUG_DEFAULT=1" ;;
  "")      ;;
  *)       echo "usage: $(basename "$0") [--debug]" >&2; exit 2 ;;
esac

if [[ "$(uname -s)" == "Darwin" ]]; then
  echo "skip    hypr-kinetic-scroll (Hyprland is Linux only)"
  exit 0
fi

# Hyprland's headers come from the hyprland package itself, so this doubles as
# a check that Hyprland is installed at all.
if ! pkg-config --exists hyprland 2>/dev/null; then
  echo "skip    hypr-kinetic-scroll (no hyprland pkg-config; install hyprland first)"
  exit 0
fi

# Build somewhere disposable. Building in $SRC_DIR would leave a 5 MB .so in
# the repo (it is gitignored, but it would also go stale silently), and more
# importantly the destination must never be a compiler output path.
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT
cp "$SRC_DIR"/*.cpp "$SRC_DIR"/*.hpp "$SRC_DIR/Makefile" "$BUILD_DIR/"

echo "build   hypr-kinetic-scroll${EXTRA_CXXFLAGS:+ (debug)}"
make -C "$BUILD_DIR" EXTRA_CXXFLAGS="$EXTRA_CXXFLAGS" all >/dev/null

# Is a compositor running that we have to get out of the way of? hyprctl exits
# non-zero when there is no instance to talk to (a TTY install, or install.sh
# run before first login), in which case there is nothing mapped and nothing
# to reload.
COMPOSITOR_UP=0
if command -v hyprctl >/dev/null && hyprctl version >/dev/null 2>&1; then
  COMPOSITOR_UP=1
fi

if (( COMPOSITOR_UP )) && hyprctl plugin list 2>/dev/null | grep -q hypr-kinetic-scroll; then
  echo "unload  $DEST (before replacing the file it is mapped from)"
  hyprctl plugin unload "$DEST" >/dev/null
fi

mkdir -p "$DEST_DIR"
cp "$BUILD_DIR/hypr-kinetic-scroll.so" "$DEST.new"
mv -f "$DEST.new" "$DEST"
echo "install $DEST"

if (( COMPOSITOR_UP )); then
  # Both steps are needed, in this order.
  #
  # `hyprctl plugin load` is what actually loads it: hypr/input.lua's
  # hl.plugin.load() only takes effect on the initial config parse at
  # compositor startup, and is a silent no-op during a reload -- so a reload on
  # its own leaves the plugin unloaded and the touchpad with no momentum at all.
  #
  # The reload afterwards is what restores the per-app allowlist. Unloading
  # destroyed the rule table, and Hyprland resets it on every config
  # pre-reload anyway; the allowlist lives in input.lua and nowhere else, so
  # without this the plugin would come back with its default of momentum on
  # everywhere, stacking on top of the fling GTK and Chromium already do. It
  # has to come second because input.lua's hl.plugin.kinetic_scroll.* calls
  # only resolve once the plugin is loaded.
  hyprctl plugin load "$DEST" >/dev/null
  hyprctl reload >/dev/null
  if hyprctl plugin list 2>/dev/null | grep -q hypr-kinetic-scroll; then
    # "Loaded" does not mean "loaded the file that was just built". Hyprland's
    # unload drops the plugin from its own list but the shared object stays
    # mapped -- dlclose does not bring the refcount to zero -- so a later
    # dlopen of the same path hands back the library already resident under
    # that name and never looks at the new file. Verified by comparing
    # /proc/<hyprland>/maps against the file: the compositor kept serving an
    # inode that had been replaced on disk twenty minutes earlier, while every
    # unload/load cycle reported success.
    #
    # So compare inodes and say so plainly, rather than printing a reassuring
    # "loaded" over stale code. Renaming the plugin per build would dodge this,
    # but input.lua loads one fixed path, so a fresh compositor is the honest
    # answer for a code change.
    # Compare by inode, not by path. The rename above unlinks whatever inode is
    # still mapped, so the compositor's own mapping of $DEST shows up in
    # /proc/<pid>/maps with a " (deleted)" suffix -- which is why this matches
    # on awk's $6 rather than anchoring a grep at end of line.
    hypr_pid="$(pgrep -x Hyprland | head -1 || true)"
    disk_inode="$(stat -c %i "$DEST")"
    mapped_inodes=""
    if [[ -n "$hypr_pid" && -r "/proc/$hypr_pid/maps" ]]; then
      mapped_inodes="$(awk -v path="$DEST" '$6 == path { print $5 }' \
                       "/proc/$hypr_pid/maps" | sort -u)"
    fi
    if [[ -n "$mapped_inodes" ]] && ! grep -qx "$disk_inode" <<<"$mapped_inodes"; then
      echo "loaded  hypr-kinetic-scroll (STALE: the running compositor is still"
      echo "        serving the previous build from a mapping it never released."
      echo "        Log out and back in to pick up this one.)"
    else
      echo "loaded  hypr-kinetic-scroll"
    fi
  else
    echo "WARNING: plugin did not load. Check the Hyprland log:" >&2
    echo "  grep -i kinetic /run/user/$(id -u)/hypr/*/hyprland.log" >&2
    exit 1
  fi
else
  echo "note    no running Hyprland; it will load at next login via hypr/input.lua"
fi
