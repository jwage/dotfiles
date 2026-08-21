# magic-mouse-gestures (vendored fork)

Two-finger horizontal swipes on the Magic Mouse 2 surface become `Alt+Left` /
`Alt+Right` (browser Back/Forward).

Forked from **[brenoperucchi/magic-mouse-gestures](https://github.com/brenoperucchi/magic-mouse-gestures)**
(MIT, Copyright (c) 2025 Breno Perucchi — see [`LICENSE`](LICENSE)) at commit
[`7210b2d`](https://github.com/brenoperucchi/magic-mouse-gestures/commit/7210b2d7f1115c83a1823712a6289c8847df66aa),
upstream `master` as of 2026-01-15.

It lives here rather than being installed from upstream because upstream's
`install.sh` copies the daemon into `/opt`, needs `sudo` and a real TTY, and
disconnects the mouse over Bluetooth mid-run — none of which fits how the rest
of this repo installs. `install.sh` here just symlinks the two files below, so
editing the daemon and `systemctl --user restart magic-mouse-gestures` is the
whole edit loop.

## What install.sh puts where

| Repo file | Installed as |
|---|---|
| `magic_mouse_gestures.py` | `~/.local/bin/magic-mouse-gestures` |
| `magic-mouse-gestures.service` | `~/.config/systemd/user/magic-mouse-gestures.service` |
| `../etc/udev/rules.d/70-magic-mouse.rules` | `/etc/udev/rules.d/70-magic-mouse.rules` (sudo) |

Enable it once on a new machine (`install.sh` only symlinks; it deliberately
does not start units):

```sh
systemctl --user daemon-reload
systemctl --user enable --now magic-mouse-gestures
```

Runtime dependencies, all from `pacman`: `python` and `wtype` (Wayland key
injection). Upstream also wants `bluez-utils`, but only its installer used it.

**Do not run `systemctl --user disable` or `reenable` on this unit.** The
installed unit is a symlink out of this repo, which systemd treats as a *linked*
unit — `disable` deletes the symlink itself, not just the `.wants` entry, and
`reenable` then fails with "Unit ... does not exist" having already removed it.
Re-run `install.sh` (or re-create the symlink) and `enable` it again to recover.
The same is true of `magicmouse-scroll.service`. To stop it temporarily, use
`systemctl --user stop`.

## Local changes vs upstream

Kept deliberately small so `diff` against a fresh upstream checkout stays
readable.

- **`MIN_FINGERS` defaults to 2, not 1.** One-finger horizontal motion fired
  browser Back constantly, because a finger rests on that surface whenever the
  mouse is moved. Two fingers matches macOS. This replaces what used to be a
  `systemctl --user edit` drop-in.
- **`magic-mouse-gestures.service`** runs the symlink in `~/.local/bin` instead
  of `/opt/magic-mouse-gestures/magic_mouse_gestures.py`, and is ordered
  `After=`/`WantedBy=graphical-session.target` rather than `default.target` —
  it needs a live Wayland session for `wtype`. It also sets
  `PYTHONUNBUFFERED=1`: the daemon logs with plain `print()`, and without it
  Python block-buffers stdout into the journal socket, so `journalctl --user -u
  magic-mouse-gestures` shows nothing at all until the buffer fills.
- **`70-magic-mouse.rules` replaces upstream's `99-magic-mouse.rules`.**
  Upstream sets `MODE="0666"` on the mouse's hidraw node, exposing every touch
  and button to any local process; a per-user ACL (`TAG+="uaccess"`) is enough.
  The number matters: `/usr/lib/udev/rules.d/73-seat-late.rules` is what turns
  that tag into an ACL, so a `99-` file adds it too late. `MODE="0600"` is
  stated explicitly because udev only applies a mode when a rule asks for one —
  dropping the `0666` rule does not by itself take world access back off a node
  that already exists.
- **Not vendored:** upstream's `install.sh`, `uninstall.sh`, `pyproject.toml`,
  `.github/`, `udev/99-magic-mouse.rules`, and `modprobe/hid-magicmouse.conf`.
  Module options are owned by `../etc/modprobe.d/hid_magicmouse.conf` instead —
  two `options` lines for one module leave the winner decided by which filename
  sorts last in `/etc/modprobe.d` (`-` before `_`), so upstream's copy must not
  be installed alongside it.

## Re-syncing with upstream

```sh
git clone https://github.com/brenoperucchi/magic-mouse-gestures /tmp/mmg
diff -u /tmp/mmg/magic_mouse_gestures.py magic_mouse_gestures.py
```

Everything that shows up should be one of the changes listed above; anything
else is new upstream work to consider pulling in. Update the commit hash at the
top of this file and the `Vendored fork` note in the daemon's docstring when you
re-sync.

## How this splits the surface with `magicmouse-scroll`

Momentum scrolling is **not** this daemon — it emits no scroll events at all.
That comes from [`../magicmouse-scroll/`](../magicmouse-scroll), and the two
divide the surface by finger count:

| Fingers | Owner | Result |
|---|---|---|
| 1 | `magicmouse-scroll` | scroll, with kinetic fling |
| 2 | `magic-mouse-gestures` | `Alt+Left` / `Alt+Right` |

That split is load-bearing in both directions: `MIN_FINGERS = 2` here keeps this
daemon off one-finger scrolling, and `MAX_SCROLL_CONTACTS = 1` in
`scroll_observer.py` keeps the scroll observer off two-finger swipes. Without
both, one two-finger flick would scroll sideways *and* navigate back. Neither
daemon grabs the device (one reads evdev, the other hidraw, both
non-exclusively), so they coexist and the physical mouse keeps delivering its
own pointer motion and clicks. The full rationale is in the Magic Mouse section
of [`../README.md`](../README.md).
