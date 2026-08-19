import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.UPower

// Suspends after an idle timeout, but only while on battery. On AC this
// never fires, independent of the built-in idle service's screensaver/lock
// cycle (services/idle/Service.qml) — that keeps locking and starting the
// screensaver on schedule either way, so agents on AC keep running behind a
// locked screen instead of the machine going to sleep out from under them.
Item {
  id: root

  // Idle-on-battery time before suspending. Longer than the built-in
  // lock (5 min) and screensaver (2.5 min) defaults, so by the time this
  // fires the screen is already locked. Edit to taste.
  readonly property int suspendTimeoutSeconds: 600

  readonly property string stayAwakeStatePath: Quickshell.env("HOME") + "/.local/state/omarchy/indicators/stay-awake"
  readonly property string stayAwakeStateDir: Quickshell.env("HOME") + "/.local/state/omarchy/indicators"
  property bool stayAwake: false

  function suspend() {
    if (suspendProcess.running) return
    console.log("jwage.battery-sleep " + new Date().toISOString() + " idle on battery, suspending")
    suspendProcess.command = ["systemctl", "suspend"]
    suspendProcess.running = true
  }

  function refreshStayAwake() {
    if (!stayAwakeProbe.running) stayAwakeProbe.running = true
  }

  // Manually enabling "stay awake" (e.g. presenting on battery) should hold
  // this off too, the same way it holds off the built-in idle cycle.
  IdleMonitor {
    id: idleMonitor
    enabled: UPower.onBattery && !root.stayAwake
    timeout: root.suspendTimeoutSeconds
    respectInhibitors: true
    onIsIdleChanged: if (isIdle) root.suspend()
  }

  Process { id: suspendProcess }

  Process {
    id: stayAwakeProbe
    command: ["bash", "-c", "[[ -f \"" + root.stayAwakeStatePath + "\" ]] && echo yes || echo no"]
    stdout: SplitParser {
      onRead: function(line) { root.stayAwake = String(line).trim() === "yes" }
    }
  }

  FileView {
    id: stayAwakeStateDirWatcher
    path: root.stayAwakeStateDir
    watchChanges: true
    printErrors: false
    onFileChanged: root.refreshStayAwake()
    onLoaded: root.refreshStayAwake()
    onLoadFailed: root.refreshStayAwake()
  }

  Component.onCompleted: refreshStayAwake()
}
