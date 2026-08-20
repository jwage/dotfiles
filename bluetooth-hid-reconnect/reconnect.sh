#!/bin/bash
# Reconnect trusted classic-Bluetooth HID peripherals (the Apple Keyboard,
# the Magic Mouse) after login.
#
# BlueZ's own auto-reconnect (the policy plugin's ReconnectUUIDs, see
# [Policy] in /etc/bluetooth/main.conf) only covers audio profile UUIDs --
# handsfree/A2DP -- by default. HID is deliberately left out, so a
# keyboard/mouse that was connected before a reboot or suspend just sits
# paired-but-disconnected until something explicitly asks BlueZ to connect
# it. This does that asking, once, shortly after the graphical session
# starts, which is why the Apple Keyboard/Magic Mouse otherwise required
# opening Bluetooth settings and clicking Connect by hand after every boot.
set -euo pipefail

HID_UUID="00001124-0000-1000-8000-00805f9b34fb"

is_hid() {
  bluetoothctl info "$1" 2>/dev/null | grep -qi "$HID_UUID"
}

is_connected() {
  bluetoothctl info "$1" 2>/dev/null | grep -q "Connected: yes"
}

# bluetoothd may still be settling in (adapter power-on, SDP records) for a
# few seconds right after the session starts -- wait for it rather than
# racing it.
for _ in $(seq 1 10); do
  if bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then
    break
  fi
  sleep 1
done

bluetoothctl devices Trusted | while read -r _ mac _; do
  if is_hid "$mac" && ! is_connected "$mac"; then
    # The peripheral itself also needs to be awake -- a couple of retries
    # with a short pause covers the first attempt landing before it's out
    # of its own post-boot sleep.
    for _ in 1 2 3; do
      if bluetoothctl connect "$mac" >/dev/null 2>&1; then
        break
      fi
      sleep 2
    done
  fi
done
