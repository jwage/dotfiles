import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// TradersPost production health as a single dot on the bar, with the numbers
// behind it one click away.
//
// The poll lives here rather than in Panel.qml on purpose: the dot is the whole
// point of the widget, so it has to keep updating while the panel is shut. The
// panel reads this widget's `health` rather than fetching anything itself.
//
// Left click opens the cockpit, middle click forces a refresh, right click
// sends the one-line summary as a notification -- the same shape the weather
// widget uses, so the gestures are already in muscle memory.
BarWidget {
  id: root
  moduleName: "jwage.traderspost"

  // ---- State. Last good data is kept through a failed poll: a stale number
  //      labelled stale beats an empty panel, and the dot goes grey on its own
  //      once the data is too old to act on.
  property var health: Model.parseHealth("")
  property double lastSuccess: 0
  property double now: Date.now()
  property bool polling: false
  property string lastError: ""

  readonly property int pollInterval: Model.pollIntervalMs(setting("pollSeconds", 60))
  readonly property bool showLatency: setting("showLatency", true) === true && !vertical

  readonly property double dataAge: lastSuccess > 0 ? now - lastSuccess : Number.POSITIVE_INFINITY
  readonly property bool stale: lastSuccess <= 0 || Model.isStale(dataAge, pollInterval)

  // Grey beats a confident green when the numbers stopped arriving, so
  // staleness outranks whatever the last payload said.
  readonly property string effectiveStatus: stale ? "unknown" : String(health.status || "unknown")
  readonly property string ageText: lastSuccess > 0 ? Model.ageText(dataAge) : "never"

  // Traffic-light semantics are the point of an ops widget, so ok/warning are
  // explicit colours rather than theme tokens -- there is no green or amber in
  // the Omarchy palette to borrow. Critical defers to the theme's own alarm
  // colour so the loudest state still matches the desktop, and both greens are
  // desaturated to sit against a dark bar without glowing.
  function statusColor(grade) {
    if (grade === "critical") return Color.urgent
    if (grade === "warning") return "#d8a021"
    if (grade === "ok") return "#7aa25c"
    if (grade === "info") return root.bar ? root.bar.foreground : Color.foreground
    return Color.muted
  }

  readonly property color statusForeground: statusColor(effectiveStatus)
  readonly property string label: Model.barLabel(health, showLatency)
  readonly property string tooltip: {
    if (root.stale && root.lastSuccess > 0) return Model.summaryLine(health) + " · stale, " + ageText
    if (!health.ok) return "TradersPost: " + (health.error || "unavailable")
    return Model.summaryLine(health) + " · " + ageText
  }

  function refresh() {
    if (healthProc.running) return
    root.polling = true
    healthProc.running = true
  }

  function applyResult(raw) {
    var parsed = Model.parseHealth(raw)
    root.polling = false
    if (parsed.ok) {
      root.health = parsed
      root.lastSuccess = Date.now()
      root.now = root.lastSuccess
      root.lastError = ""
      return
    }
    // Keep the previous good payload on screen; only the error line and the
    // greying clock change. A first-ever failure has nothing to keep, so the
    // panel shows the reason instead of a row of dashes.
    root.lastError = parsed.error
    if (root.lastSuccess <= 0) root.health = parsed
  }

  function notifySummary() {
    if (!root.bar) return
    // Single-quoted for the shell, with any embedded quote defanged: broker
    // hostnames and New Relic issue titles both end up in this string.
    var line = Model.summaryLine(root.health).replace(/'/g, "'\\''")
    root.bar.run("omarchy-notification-send '" + line + "'")
  }

  function openDashboard() {
    if (!root.bar) return
    root.bar.run("omarchy-launch-browser 'https://one.newrelic.com/nr1-core?account=6271700'")
  }

  // ---- Panel plumbing. Shape contract for shell.summon/hide/toggle routing:
  //      Bar.findPanelWidget requires open/close/opened on the bar-widget root.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  // Forwarded so this widget can stand in for the panel as the bar's popout
  // identity: Bar.requestPopout prefers closeForPopoutSwitch over close, and
  // KeyboardPanel reads popoutSwitchClosing back off its owner.
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Component.onCompleted: refresh()

  Process {
    id: healthProc
    // Resolved next to this QML rather than looked up on PATH: the widget and
    // the script version together, so a repo edit takes effect on the next
    // poll without depending on ~/.local/bin being linked yet.
    command: ["python3", Qt.resolvedUrl("traderspost-health").toString().replace("file://", ""), "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyResult(String(text || ""))
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      // The collector already handled a JSON body, including the helper's own
      // {"ok":false,...}. This only catches the case where nothing parseable
      // arrived at all -- python missing, script unreadable.
      root.polling = false
      if (exitCode !== 0 && root.health.ok && root.lastSuccess <= 0)
        root.lastError = "traderspost-health exited " + exitCode
    }
  }

  Timer {
    interval: root.pollInterval
    running: true
    repeat: true
    triggeredOnStart: false
    onTriggered: root.refresh()
  }

  // Drives the age text and the staleness flag between polls, so a widget whose
  // fetches have stopped visibly ages instead of sitting on a confident colour.
  Timer {
    interval: 5000
    running: true
    repeat: true
    onTriggered: root.now = Date.now()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "jwage.traderspost"

    function refresh(): void { root.refresh() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function status(): string { return Model.summaryLine(root.health) }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "" : root.label
    labelVisible: !root.vertical
    hasVisualContent: true
    // The panel is the detail view, so the tooltip stays a one-liner rather
    // than repeating it.
    tooltipText: root.tooltip
    horizontalMargin: 8.75
    verticalPadding: 8.75
    // Colour is the signal here, so it overrides the bar's own foreground --
    // including on hover, where a themed highlight would wash the status out.
    foreground: root.statusForeground

    onPressed: function(b) {
      if (b === Qt.RightButton) root.notifySummary()
      else if (b === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }

    // Vertical bars have icon-sized slots and no room for a number, so the
    // dot stands alone.
    OpticalGlyph {
      visible: root.vertical
      anchors.fill: parent
      text: "●"
      fontFamily: button.fontFamily
      fontSize: button.fontSize
      color: root.statusForeground
    }
  }
}
