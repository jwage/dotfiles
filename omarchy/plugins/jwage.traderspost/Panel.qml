import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The cockpit itself: a verdict at the top, then the numbers behind it.
//
// Ordered so it reads from "what pages you" down to "what the system is
// doing" -- the three queue waits and the error rate are the signals
// TradersPost Policy actually alerts on, so they come first and carry the
// threshold they are measured against. Volume and dependencies sit below,
// because they explain a bad number rather than being one.
//
// BarWidget.qml owns the poll and the bar dot; this panel only renders what it
// already has, so opening the panel never waits on a request.
Panel {
  id: root
  moduleName: "jwage.traderspost"
  ipcTarget: "jwage.traderspost"
  manageIpc: false

  property var anchorItem: null

  // The bar tracks the widget mounted in its slot -- BarWidget.qml -- not this
  // nested panel. Everything the bar identifies a panel by has to be that
  // widget: the popout coordinator (and with it the open-panel dot under the
  // pill) compares against `slot.activeItem`, and switchPanelFrom looks the
  // slot up the same way.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property var health: hostWidget ? hostWidget.health : Model.parseHealth("")
  readonly property string status: hostWidget ? hostWidget.effectiveStatus : "unknown"
  readonly property bool stale: hostWidget ? hostWidget.stale : true
  readonly property string ageText: hostWidget ? hostWidget.ageText : "never"
  readonly property bool polling: hostWidget ? hostWidget.polling : false
  readonly property string lastError: hostWidget ? hostWidget.lastError : ""
  readonly property int queueWaitCritical: 1000

  // Guarded so the panel renders before the bar is injected (the bar-widget
  // contract instantiates it bare).
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  function statusColor(grade) {
    return hostWidget ? hostWidget.statusColor(grade) : Color.muted
  }

  // The signals the alert policy pages on, then everything that explains them.
  readonly property var pagedKeys: ["liveQueueWait", "paperQueueWait", "webhookQueueWait", "errorRate", "synthetic"]
  readonly property var contextKeys: ["webThroughput", "webDuration", "webhooksReceived", "tradesProcessed", "slowestBroker"]

  function rowsFor(keys) {
    var out = []
    var rows = (health && health.rows) || []
    for (var i = 0; i < rows.length; i++)
      if (keys.indexOf(rows[i].key) !== -1) out.push(rows[i])
    return out
  }

  readonly property var pagedRows: rowsFor(pagedKeys)
  readonly property var contextRows: rowsFor(contextKeys)

  function open() {
    root.controller.show()
    // Opening is the moment the numbers are about to be read, so make them
    // current rather than however old the last tick left them.
    if (hostWidget) hostWidget.refresh()
    // Set after showing, not before: showing hands the popout coordinator
    // over, which closes whichever panel was open, and that close clears the
    // shared flag. Deferring means the panel taking over always wins, while
    // a handoff to a panel that does not manage the flag still leaves it
    // cleared rather than stuck on.
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Summoning by hotkey moves no pointer, so a hover the bar was still
  // holding must not keep the center indicators revealed behind the panel.
  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function refresh() {
    if (hostWidget) hostWidget.refresh()
  }

  function openDashboard() {
    if (hostWidget) hostWidget.openDashboard()
    root.close()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    // Left false, unlike the clock and weather panels this is modelled on:
    // those two sit in the bar's center section, where centering the popup on
    // the bar and centering it under the widget are the same thing. This widget
    // lives on the right, so centerOnBar would drop the cockpit in the middle
    // of the screen, disconnected from the dot that opened it.
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onActivateRequested: root.refresh()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refresh()
        else if (t === "o" || t === "O") root.openDashboard()
      }

      Column {
        id: content
        width: parent.width
        spacing: Style.spacing.lg

        // ---- Verdict. One word, in the status colour, over the app it is
        //      about. Clicking it refreshes -- the thing you reach for when a
        //      number looks wrong is "is that still true?".
        Item {
          width: parent.width
          height: heroRow.implicitHeight

          Row {
            id: heroRow
            width: parent.width
            spacing: Style.spacing.controlGap

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "●"
              color: root.statusColor(root.status)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.heading
            }

            Column {
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.xxs

              Text {
                text: Model.statusWord(root.status)
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.statusColor(root.status), Color.accent)
                  : root.statusColor(root.status)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
              }

              Text {
                text: "TradersPost production"
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          // Freshness lives opposite the verdict, because the two are read
          // together: a green dot means nothing without knowing how old it is.
          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.polling ? "updating…" : root.ageText
            color: root.stale && !root.polling
              ? root.statusColor("warning")
              : Qt.darker(root.contentForeground, 1.5)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            id: heroMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.refresh()
          }
        }

        // ---- Why the data is grey, when it is. Shown under the verdict
        //      rather than in place of the numbers: last-good values stay
        //      visible and this says not to trust them.
        Text {
          visible: root.lastError !== ""
          width: parent.width
          text: root.lastError
          color: root.statusColor("critical")
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        // ---- Anything actually paging. Absent on a healthy system, which is
        //      why it is a section rather than a permanent row: a cockpit
        //      should be quiet until it isn't.
        PanelSeparator {
          visible: root.health.issues.length > 0
          width: parent.width
          foreground: root.contentForeground
        }

        PanelSectionHeader {
          visible: root.health.issues.length > 0
          text: root.health.issues.length === 1 ? "OPEN ISSUE" : "OPEN ISSUES"
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
        }

        Column {
          visible: root.health.issues.length > 0
          width: parent.width
          spacing: Style.spacing.sm

          Repeater {
            model: root.health.issues

            Row {
              required property var modelData
              width: content.width
              spacing: Style.spacing.controlGap

              Text {
                text: "▲"
                color: root.statusColor("critical")
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                width: content.width - Style.space(24)
                text: modelData.title
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }
            }
          }
        }

        PanelSeparator {
          width: parent.width
          foreground: root.contentForeground
        }

        PanelSectionHeader {
          text: "ALERTS ON THESE"
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
        }

        Column {
          width: parent.width
          spacing: Style.spacing.xs

          Repeater {
            model: root.pagedRows
            delegate: metricRow
          }
        }

        PanelSeparator {
          width: parent.width
          foreground: root.contentForeground
        }

        PanelSectionHeader {
          text: "TRAFFIC · LAST 5 MIN"
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
        }

        Column {
          width: parent.width
          spacing: Style.spacing.xs

          Repeater {
            model: root.contextRows
            delegate: metricRow
          }
        }

        PanelSeparator {
          width: parent.width
          foreground: root.contentForeground
        }

        // ---- Footer. The keys are printed because this panel is reachable by
        //      hotkey, where there is no button to hunt for.
        Item {
          width: parent.width
          height: Math.max(footerHint.implicitHeight, footerActions.implicitHeight)

          Text {
            id: footerHint
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "r refresh · o New Relic"
            color: Qt.darker(root.contentForeground, 1.6)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }

          Row {
            id: footerActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.sm

            PanelActionButton {
              iconText: "󰑐"
              tooltipText: "Refresh now"
              foreground: root.contentForeground
              hoverColor: Color.accent
              fontFamily: root.contentFontFamily
              onClicked: root.refresh()
            }

            PanelActionButton {
              iconText: "󰏋"
              tooltipText: "Open New Relic"
              foreground: root.contentForeground
              hoverColor: Color.accent
              fontFamily: root.contentFontFamily
              onClicked: root.openDashboard()
            }
          }
        }
      }
    }
  }

  // One metric: name on the left, value on the right, and a dot only when the
  // value has a verdict attached. Plain volume figures get no dot -- a
  // throughput is not good or bad on its own, and colouring it would dilute the
  // dots that do mean something.
  Component {
    id: metricRow

    Item {
      required property var modelData
      width: content.width
      height: Math.max(rowLabel.implicitHeight, rowValue.implicitHeight)

      Text {
        id: rowLabel
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: modelData.label
        color: Qt.darker(root.contentForeground, 1.25)
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
        width: Math.min(implicitWidth, parent.width * 0.5)
      }

      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.sm

        // The host behind "Slowest API", and the threshold behind a queue wait
        // that has crossed it -- context that only earns its space when it
        // changes what the number means.
        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: text !== ""
          text: {
            if (modelData.detail !== "") return modelData.detail
            if (modelData.grade === "warning" || modelData.grade === "critical")
              return "limit " + root.queueWaitCritical + "ms"
            return ""
          }
          color: Qt.darker(root.contentForeground, 1.8)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideLeft
          width: Math.min(implicitWidth, content.width * 0.42)
        }

        Text {
          id: rowValue
          anchors.verticalCenter: parent.verticalCenter
          text: modelData.text
          color: root.stale
            ? Color.muted
            : (modelData.grade === "info" ? root.contentForeground : root.statusColor(modelData.grade))
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: modelData.grade === "warning" || modelData.grade === "critical"
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: modelData.grade !== "info"
          text: "●"
          color: root.stale ? Color.muted : root.statusColor(modelData.grade)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
