import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  // org.omarchy.agent is the fixed app id every `omarchy agent` terminal
  // session launches under (see omarchy-agent), regardless of which CLI is
  // actually running inside it — it has no .desktop entry of its own, so
  // reuse the marks the agent-usage panel already ships. Which mark applies
  // to a given window is resolved per window by find-agent-process, since
  // two agent windows can be running different CLIs at once; the configured
  // default agent is only a fallback while that resolution is pending or
  // for a CLI with no shipped mark.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property string defaultAgentId: ""
  readonly property var agentIconIds: ["claude", "codex", "fireworks"]
  // Agents omarchy ships no assets/<id>.svg for, mapped to an icon their
  // own desktop app installed into the icon theme. Keeps a resolved agent
  // from falling all the way through to the generic executable glyph just
  // because the agents panel has no mark for it. A missing entry (or an
  // uninstalled app) simply falls through, so this stays additive.
  readonly property var agentThemeIconNames: ({ "grok": "grok-bot" })
  // Keyed by the window's Hyprland address. An address is stable for the
  // lifetime of its window, but it is a heap pointer, so Hyprland hands the
  // same one out again for a later window — see the pruning Connections
  // below, without which a new Codex window inherits a closed Claude
  // window's cached answer.
  property var resolvedAgentByAddress: ({})
  // Plain in-flight tracker, mutated in place: nothing binds to this, it
  // just stops a window from being probed by more than one retry chain at once.
  property var probingAddresses: ({})
  readonly property int maxProbeAttempts: 12
  readonly property int probeIntervalMs: 350
  readonly property int probeTimeoutMs: 2000
  // Several agent windows opening together (a fresh shell start, a burst of
  // `omarchy agent` launches) queued their find-agent-process probes as
  // concurrent dynamically-created Process objects, which intermittently
  // cross-wired results between windows. One probe in flight at a time
  // sidesteps that entirely; resolution is still fast since each probe is a
  // cheap `ps` + `awk`.
  property var _probeQueue: []
  property bool _probeBusy: false

  Process {
    id: defaultAgentProc
    command: ["omarchy-default-agent"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.defaultAgentId = text.trim()
    }
  }

  Component.onCompleted: defaultAgentProc.running = true

  // Drop a window's cached agent as it closes. objectRemovedPre (rather than
  // Post, or a sweep of the live set) is deliberate: it still has the
  // toplevel, so the address is readable, and the entry is gone before
  // Hyprland can reissue that address to a new window — which is what makes
  // reuse unable to serve a stale answer at all, rather than merely
  // unlikely to.
  Connections {
    target: Hyprland.toplevels

    function onObjectRemovedPre(object, index) {
      var address = object ? object["address"] : ""
      if (!address) return
      delete root.probingAddresses[address]
      if (root.resolvedAgentByAddress[address] === undefined) return
      var updated = Object.assign({}, root.resolvedAgentByAddress)
      delete updated[address]
      root.resolvedAgentByAddress = updated
    }
  }

  // A window maps the moment its terminal forks, which can be well before
  // the CLI inside it has actually exec'd into a process find-agent-process
  // would recognize — mise re-execs, checks for updates, etc. So a single
  // probe that comes up empty doesn't get cached as the answer; it retries
  // on a short timer until one lands or the attempt budget
  // (maxProbeAttempts * probeIntervalMs, a few seconds) runs out, which is
  // the only case an empty result is cached for good.
  function resolveAgentForWindow(address) {
    if (!address || root.resolvedAgentByAddress[address] !== undefined || root.probingAddresses[address]) return
    root.probingAddresses[address] = true
    root._probeQueue.push({ address: address, attempt: 0 })
    root._pumpProbeQueue()
  }

  function _pumpProbeQueue() {
    if (root._probeBusy || root._probeQueue.length === 0) return
    root._probeBusy = true
    var job = root._probeQueue.shift()
    root._runProbe(job.address, job.attempt)
  }

  // A stuck or lost `streamFinished` (a process that fails to spawn, a
  // signal that never arrives) would otherwise wedge _probeBusy forever and
  // silently stall every window still waiting behind it in the queue. The
  // timeout is the failsafe: whichever of it or the real result arrives
  // first wins, via the `settled` guard, and either way the queue keeps
  // moving.
  function _runProbe(address, attempt) {
    var settled = false
    var proc = Qt.createQmlObject(
      'import Quickshell.Io; Process { stdout: StdioCollector { waitForEnd: true } }',
      root, "agentPidResolver")
    proc.command = [Qt.resolvedUrl("find-agent-process").toString().replace("file://", ""), String(address)]

    var timeoutTimer = Qt.createQmlObject(
      'import QtQuick; Timer { interval: ' + root.probeTimeoutMs + '; running: true; repeat: false }',
      root, "agentPidTimeout")

    var settle = function(result) {
      if (settled) return
      settled = true
      timeoutTimer.destroy()
      proc.destroy()
      root._probeBusy = false

      if (result || attempt >= root.maxProbeAttempts) {
        delete root.probingAddresses[address]
        var updated = Object.assign({}, root.resolvedAgentByAddress)
        updated[address] = result
        root.resolvedAgentByAddress = updated
      } else {
        root._scheduleProbeRetry(address, attempt + 1)
      }
      root._pumpProbeQueue()
    }

    proc.stdout.streamFinished.connect(function() { settle(proc.stdout.text.trim()) })
    timeoutTimer.triggered.connect(function() { settle("") })
    proc.running = true
  }

  function _scheduleProbeRetry(address, attempt) {
    var timer = Qt.createQmlObject(
      'import QtQuick; Timer { interval: ' + root.probeIntervalMs + '; running: true; repeat: false }',
      root, "agentPidRetry")
    timer.triggered.connect(function() {
      timer.destroy()
      root._probeQueue.push({ address: address, attempt: attempt })
      root._pumpProbeQueue()
    })
  }

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  function workspaceIds() {
    var ids = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  function focusWindow(address) {
    if (!root.bar || !address) return
    var hex = String(address).replace(/^0x/i, "")
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ window = \"address:0x" + hex + "\" })"))
  }

  function workspaceToplevels(workspace) {
    if (!workspace) return []
    try {
      return workspace.toplevels.values
    } catch (e) {
      return []
    }
  }

  // A HyprlandToplevel has no "class" of its own; the app id lives on its
  // nested Wayland toplevel handle.
  function windowAppId(toplevel) {
    if (!toplevel || !toplevel.wayland) return ""
    return String(toplevel.wayland.appId || "")
  }

  // App icons come from the window's app id. A window's app id and its
  // .desktop file's Icon= often differ (e.g. appId "cursor" but
  // Icon=co.anysphere.cursor, appId "signal" but Icon=signal-desktop), so
  // resolve the desktop entry first via Quickshell's own heuristic matcher
  // before trying the app id directly, then fall back to a generic icon.
  function windowIconSource(appId, address) {
    var name = String(appId || "").trim()
    if (!name) return Quickshell.iconPath("application-x-executable", true)

    if (name === "org.omarchy.agent") {
      // Deferred: resolveAgentForWindow mutates reactive state (the probe
      // queue, _probeBusy) that this same function also reads through
      // nested calls. Doing that synchronously inside source's own
      // evaluation is a textbook Qt binding loop — "source" ends up
      // depending on a property it just wrote — and QML's loop recovery
      // then leaves source holding a stale/incorrect icon rather than
      // erroring loudly. Qt.callLater pushes the mutation to the next event
      // loop turn, fully outside this evaluation.
      Qt.callLater(function() { root.resolveAgentForWindow(address) })
      var resolved = root.resolvedAgentByAddress[address]
      // Only guess the default agent's mark while resolution is still
      // pending (resolved === undefined). Once it lands, trust it: a CLI
      // that resolved cleanly but ships no mark of its own (grok, gemini, …)
      // should fall through to a generic icon, not borrow another agent's.
      var agentId = resolved === undefined ? root.defaultAgentId : resolved
      if (root.agentIconIds.indexOf(agentId) !== -1)
        return Util.fileUrl(root.omarchyPath + "/shell/plugins/agents/assets/" + agentId + ".svg")

      var themeIconName = root.agentThemeIconNames[agentId]
      if (themeIconName) {
        var agentThemeIcon = Quickshell.iconPath(themeIconName, true)
        if (agentThemeIcon.length > 0) return agentThemeIcon
      }
    }

    var entry = DesktopEntries.heuristicLookup(name)
    if (entry && entry.icon) {
      var entryIcon = Quickshell.iconPath(entry.icon, true)
      if (entryIcon.length > 0) return entryIcon
    }

    var themed = Quickshell.iconPath(name, true)
    return themed.length > 0 ? themed : Quickshell.iconPath("application-x-executable", true)
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)
  readonly property int iconSize: Math.round(root.barSize * 0.6)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      WidgetButton {
        id: workspaceButton
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property var toplevels: root.workspaceToplevels(workspace)
        readonly property bool occupied: toplevels.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData
        readonly property string numberText: modelData === 10 ? "0" : String(modelData)
        // The icon row only fits in the horizontal bar; the vertical
        // (sidebar) layout has no room for it and just keeps the number.
        readonly property bool showIcons: !root.vertical && occupied

        bar: root.bar
        text: numberText
        labelVisible: false
        opacity: occupied || focused ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : content.implicitWidth + Style.space(12)
        fixedHeight: root.barSize
        onPressed: function() { root.focusWorkspace(modelData) }

        Row {
          id: content
          anchors.centerIn: parent
          spacing: Style.space(3)

          // The current workspace keeps its number but gets a pill behind
          // it, rather than being replaced by a generic marker glyph.
          Rectangle {
            id: numberBadge
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(height, numberLabel.implicitWidth + Style.space(6))
            height: Style.space(16)
            radius: height / 2
            color: workspaceButton.focused ? Color.accent : "transparent"

            Text {
              id: numberLabel
              anchors.centerIn: parent
              text: workspaceButton.numberText
              color: workspaceButton.focused ? Color.background : (root.bar ? root.bar.barForeground : Color.foreground)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
            }
          }

          Repeater {
            // A plain integer model (rather than a freshly allocated array
            // on every evaluation) is what lets Qt add/remove delegates
            // incrementally as the count changes; a new array identity each
            // time was forcing a full destroy-and-recreate of every icon on
            // every Hyprland event, which was intermittently corrupting the
            // agent icon resolution below (visible as sporadic "Binding loop
            // detected for property source" warnings).
            model: workspaceButton.showIcons ? workspaceButton.toplevels.length : 0

            Image {
              id: windowIcon
              required property int index
              readonly property var toplevel: workspaceButton.toplevels[index]

              anchors.verticalCenter: parent.verticalCenter
              width: root.iconSize
              height: root.iconSize
              fillMode: Image.PreserveAspectFit
              sourceSize.width: width * Screen.devicePixelRatio
              sourceSize.height: height * Screen.devicePixelRatio
              source: root.windowIconSource(root.windowAppId(toplevel), toplevel ? toplevel["address"] : "")

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: function(mouse) {
                  mouse.accepted = true
                  if (windowIcon.toplevel) root.focusWindow(windowIcon.toplevel["address"])
                }
              }
            }
          }
        }
      }
    }
  }
}
