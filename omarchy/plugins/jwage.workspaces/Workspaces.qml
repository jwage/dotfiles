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
  // to a given window is resolved per pid by find-agent-process, since two
  // agent windows can be running different CLIs at once; the configured
  // default agent is only a fallback while that resolution is pending or
  // for a CLI with no shipped mark.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property string defaultAgentId: ""
  readonly property var agentIconIds: ["claude", "codex", "fireworks"]
  property var resolvedAgentByPid: ({})

  Process {
    id: defaultAgentProc
    command: ["omarchy-default-agent"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.defaultAgentId = text.trim()
    }
  }

  Component.onCompleted: defaultAgentProc.running = true

  // Fire-and-forget: kicks off find-agent-process for a pid the first time
  // it's seen and caches the result (including a "found nothing" empty
  // string) so a window never gets probed twice. property var change
  // notification is identity-based, so the cache is replaced with a new
  // object each time rather than mutated in place — writing back the same
  // reference would silently not notify the bindings that read it.
  function resolveAgentForPid(pid) {
    if (!pid || root.resolvedAgentByPid[pid] !== undefined) return

    var cache = Object.assign({}, root.resolvedAgentByPid)
    cache[pid] = null
    root.resolvedAgentByPid = cache

    var proc = Qt.createQmlObject(
      'import Quickshell.Io; Process { stdout: StdioCollector { waitForEnd: true } }',
      root, "agentPidResolver-" + pid)
    proc.command = [Qt.resolvedUrl("find-agent-process").toString().replace("file://", ""), String(pid)]
    proc.stdout.streamFinished.connect(function() {
      var result = proc.stdout.text.trim()
      var updated = Object.assign({}, root.resolvedAgentByPid)
      updated[pid] = result
      root.resolvedAgentByPid = updated
      proc.destroy()
    })
    proc.running = true
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

  // Repeater exposes each key of an object-array model as a named context
  // property instead of populating `modelData`, so iterating toplevels
  // directly leaves modelData undefined. Iterating plain indexes here and
  // looking the object up inside the delegate sidesteps that.
  function indexes(count) {
    var out = []
    for (var i = 0; i < count; i++) out.push(i)
    return out
  }

  // A HyprlandToplevel has no "class" of its own; the app id lives on its
  // nested Wayland toplevel handle.
  function windowAppId(toplevel) {
    if (!toplevel || !toplevel.wayland) return ""
    return String(toplevel.wayland.appId || "")
  }

  // lastIpcObject is the raw `hyprctl clients -j` entry for this toplevel;
  // it carries fields (like pid) that HyprlandToplevel doesn't expose as
  // dedicated properties.
  function windowPid(toplevel) {
    if (!toplevel) return 0
    var ipc = toplevel["lastIpcObject"]
    return ipc && ipc.pid ? Number(ipc.pid) : 0
  }

  // App icons come from the window's app id. A window's app id and its
  // .desktop file's Icon= often differ (e.g. appId "cursor" but
  // Icon=co.anysphere.cursor, appId "signal" but Icon=signal-desktop), so
  // resolve the desktop entry first via Quickshell's own heuristic matcher
  // before trying the app id directly, then fall back to a generic icon.
  function windowIconSource(appId, pid) {
    var name = String(appId || "").trim()
    if (!name) return Quickshell.iconPath("application-x-executable", true)

    if (name === "org.omarchy.agent") {
      root.resolveAgentForPid(pid)
      var resolved = root.resolvedAgentByPid[pid]
      var agentId = root.agentIconIds.indexOf(resolved) !== -1 ? resolved : root.defaultAgentId
      if (root.agentIconIds.indexOf(agentId) !== -1)
        return Util.fileUrl(root.omarchyPath + "/shell/plugins/agents/assets/" + agentId + ".svg")
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
            model: workspaceButton.showIcons ? root.indexes(workspaceButton.toplevels.length) : []

            Image {
              id: windowIcon
              required property int modelData
              readonly property var toplevel: workspaceButton.toplevels[modelData]

              anchors.verticalCenter: parent.verticalCenter
              width: root.iconSize
              height: root.iconSize
              fillMode: Image.PreserveAspectFit
              sourceSize.width: width * Screen.devicePixelRatio
              sourceSize.height: height * Screen.devicePixelRatio
              source: root.windowIconSource(root.windowAppId(toplevel), root.windowPid(toplevel))

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
