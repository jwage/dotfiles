# hypr-kinetic-scroll

Kinetic (momentum) scrolling for the touchpad, as a Hyprland plugin.

Vendored from [savonovv/hypr-kinetic-scroll](https://github.com/savonovv/hypr-kinetic-scroll)
at the commit in [`UPSTREAM_COMMIT`](UPSTREAM_COMMIT); upstream's own docs are
kept as [`README.upstream.md`](README.upstream.md). Build and install with:

```sh
./build.sh            # release build
./build.sh --debug    # plus per-event logging to /tmp/hypr-kinetic-scroll.log
```

`hypr/input.lua` loads the built `.so` from `~/.local/lib/hypr/` and owns the
per-app allowlist (momentum off by default, on in `foot` and
`org.omarchy.agent`) -- see the long comment there for why it is an allowlist
and not a blocklist.

## Why it is vendored rather than installed with hyprpm

`hyprpm` shells out to `sudo` and clones the whole Hyprland source to build
against, which is unnecessary when the plugin builds fine against the installed
`hyprland` package's headers. Vendoring also means the local patches below
travel with this repo instead of living in a working copy somewhere, and that a
fresh install does not depend on the upstream repo still existing.

## A rebuilt plugin does not take effect until you log out

This is the most surprising thing here, and it costs the most time if you do
not know it.

Hyprland's `hyprctl plugin unload` drops the plugin from its own list, but the
shared object **stays mapped in the compositor** -- `dlclose` never brings the
refcount to zero. A later `dlopen` of the same path therefore hands back the
library already resident under that name and never looks at the new file on
disk. Every unload/load cycle reports `ok`, and every one of them keeps running
the old code. Confirmed by comparing `/proc/<hyprland-pid>/maps` against the
file: the compositor served an inode that had been replaced twenty minutes
earlier.

`build.sh` detects this by inode and says so instead of printing a reassuring
"loaded" over stale code. When it reports `STALE`, the build on disk is correct
and will be picked up at the next login; nothing else will pick it up. Config
and per-app rules *do* reload live -- this applies only to changes in the
compiled code.

To iterate on the C++ without logging out each time, load each build under a
name of its own, which sidesteps the resident-by-name lookup:

```sh
make EXTRA_CXXFLAGS=-DKINETIC_DEBUG_DEFAULT=1
cp hypr-kinetic-scroll.so ~/.local/lib/hypr/ks-$(date +%s).so
hyprctl plugin load ~/.local/lib/hypr/ks-$(date +%s).so   # same name as above
```

Each attempt leaks a ~5 MB mapping until the next login, and the file can be
deleted right after loading (the mapping keeps the inode alive). `input.lua`
loads one fixed path, so this is a development trick, not how it is installed.

## Rebuild after every Hyprland upgrade

A Hyprland plugin is compiled against one Hyprland ABI, and a stale `.so` will
fail at a symbol rather than politely refusing to load -- see the note on the
version check in `main.cpp`. So after any Hyprland upgrade:

```sh
./build.sh   # then log out and back in
```

## Local patches

Both marked `LOCAL PATCH` in `main.cpp`.

1. **Touchpad hooks are (re)built on demand instead of once at init.** This is
   the one that made the feature work at all. Upstream registered its
   per-device `frame`/`motion`/`holdBegin` listeners from `PLUGIN_INIT`, but
   Hyprland enumerates input devices *after* it parses the config, and
   `hl.plugin.load()` runs during that parse -- so at init the pointer list is
   empty and nothing gets hooked. The per-device `frame` signal is the only way
   to see the axis-less frame libinput sends when the fingers lift, so without
   it `onPointerFrame()` never runs, `m_cancelOnStopTimer` is never cleared,
   and every gesture ends in `stopKinetic("gestureIdle")` instead of momentum.
   Scrolling still worked, it just never glided -- which reads like a tuning
   problem rather than a plugin that is structurally inert. It also explains
   why loading the plugin by hand with `hyprctl plugin load` looked fine: by
   then the devices exist.

   The rescan additionally picks up touchpads that appear later, which this
   machine needs: `magicmouse-scroll`'s virtual touchpad is created by a user
   service that starts after the compositor.

   The fix is visible in the debug log as `beginDecay reason=fallbackTimeout`
   followed by `stopKinetic reason=decayDone` where there used to be nothing
   but `stopKinetic reason=gestureIdle`.

2. **`plugin:kinetic-scroll:debug` defaults to a compile-time constant**
   (`KINETIC_DEBUG_DEFAULT`, set by `build.sh --debug`). On Hyprland 0.56.2
   there is no way to turn this on at runtime: `hyprctl keyword` rejects
   plugin-registered keys outright ("can't work with non-legacy parsers") and
   the Lua config validator rejects them from both the nested `plugin = {}`
   form and the flat string-key form, so neither `input.lua` nor `hyprctl eval`
   can reach it. Rebuilding is the only switch there is, and the debug log is
   the only window into why a gesture did or did not glide.

Upstream's commented-out API-version check was briefly re-enabled and then put
back as it was -- it rejects a plugin built against this machine's own
installed headers, so it only guarantees the plugin never loads. The comment on
it in `main.cpp` has the details.

## Never copy over the installed `.so` in place

`build.sh` unloads the plugin, writes to a temporary name, and `mv`s it into
place. That order is load-bearing, not tidiness.

On 2026-08-22 a rebuild was copied straight over the `.so` the running
compositor still had mmap'd. Overwriting a mapped shared object in place
invalidates the mapping underneath the process, and Hyprland took a fatal
signal inside the dynamic linker on the next symbol resolution --
`dlsym` -> `ld-linux` -> `SIGSEGV` -> Hyprland's crash handler -> `abort`,
killing every window in the session. `rename(2)` is atomic and swaps the
directory entry rather than the file's contents, so a still-mapped inode is
left intact -- which, per the section above, is exactly what the compositor
goes on using until you log out.

## How it is installed

`install.sh` calls `build.sh` from its Linux branch, after the symlink pass.
It is the only component in this repo that is compiled rather than symlinked,
which is why it gets a build call instead of a `LINUX_LINKS` entry.
