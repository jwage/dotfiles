import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
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
  // two agent windows can be running different CLIs at once — the
  // configured default agent says nothing about any particular window, so
  // it is deliberately not consulted at all.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
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

  function slackTrayIconSource() {
    var items = SystemTray.items.values
    for (var i = 0; i < items.length; i++) {
      var item = items[i]
      if (String(item.id || "").indexOf("Slack_status_icon") !== -1)
        return String(item.icon || "")
    }
    return ""
  }
  property string focusHelperAddress: ""

  Process {
    id: focusHelper
    command: ["bash", Qt.resolvedUrl("focus-window").toString().replace("file://", ""), root.focusHelperAddress]
    onExited: function(exitCode) {
      focusHelper.running = false
    }
  }

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
      if (root.settledWindowAddresses[address]) {
        var settled = Object.assign({}, root.settledWindowAddresses)
        delete settled[address]
        root.settledWindowAddresses = settled
      }
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

  function runFocusHelper(address) {
    if (!address) return
    root.focusHelperAddress = String(address)
    focusHelper.running = true
  }

  // Focus a window without dragging the pointer along with it. Hyprland warps
  // the cursor into whatever focuswindow focuses (cursor:no_warps defaults
  // off), which is wrong for a click that came from the bar: the pointer is up
  // here on the icon and should stay there, not get flung into the middle of
  // the window that just came forward. Activating the Wayland toplevel asks
  // for focus directly and does no warping -- and skips a subprocess besides.
  // The dispatcher stays as the fallback for anything with no live handle.
  function focusToplevel(toplevel, address) {
    var active = Hyprland.activeToplevel
    var activeAddress = active ? root.normalizedAddress(active.address) : ""
    var targetAddress = root.normalizedAddress(address)

    // Workspace switching deliberately ignores focus requests underneath a
    // fullscreen window. An explicit click on an app icon is different: the
    // user is asking for that app. The helper queries Hyprland live, transfers
    // any fullscreen mode to the clicked target, and then focuses it. Keeping
    // that IPC snapshot outside Quickshell avoids stale toplevel geometry/state
    // during the transition.
    if (activeAddress !== targetAddress) {
      if (!root.bar || !address) return
      root.runFocusHelper(address)
      return
    }

    if (toplevel && toplevel.wayland && typeof toplevel.wayland.activate === "function") {
      toplevel.wayland.activate()
      return
    }

    root.focusWindow(address)
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

  function isTransientWindow(toplevel, appId) {
    var ipc = toplevel ? toplevel.lastIpcObject : null
    var title = root.windowTitle(toplevel)
    // X11 menus from Spotify (and similar toolkits) can arrive before their
    // class metadata: they have no app id or title and are not real apps.
    if (!String(appId || "") && !title) return true
    // Native app menus are separate floating clients; they should not become
    // extra app icons in the workspace strip. Normal workspace app windows
    // remain tiled, so this excludes the transient surface without relying
    // on the menu's inconsistent app-id/class metadata.
    if (!ipc) return false
    if (ipc.floating === true) return true
    var size = ipc.size
    return Array.isArray(size) && size.length === 2 && size[0] < 600 && size[1] < 500
  }

  // Gmail keeps its unread inbox count in its own document title, which the
  // compositor hands us verbatim and re-emits on every change — so the count
  // is event-driven off the same toplevel the icon already comes from: no
  // polling, no Gmail API, no second widget in the bar.
  //
  // This only works because each account runs as its own Chrome app window
  // (see hypr/autostart.lua). A plain browser window reports only its
  // *active tab's* title, so two accounts living as two tabs can never both
  // be read — which is exactly why they were split out.
  readonly property string gmailAppIdPrefix: "chrome-mail.google.com__"
  readonly property int maxUnreadShown: 99
  readonly property string slackStatePath: Quickshell.env("HOME") + "/.config/Slack/storage/root-state.json"
  property var slackState: null
  property var gmailUnreadByAddress: ({})
  property int gmailRevision: 0
  property var settledWindowAddresses: ({})
  readonly property int windowSettleMs: 180

  function settleWindowLater(address) {
    if (!address || root.settledWindowAddresses[address]) return
    var timer = Qt.createQmlObject(
      'import QtQuick; Timer { interval: ' + root.windowSettleMs + '; running: true; repeat: false }',
      root, "workspaceWindowSettle")
    timer.triggered.connect(function() {
      var updated = Object.assign({}, root.settledWindowAddresses)
      updated[address] = true
      root.settledWindowAddresses = updated
      timer.destroy()
    })
  }

  // Slack keeps its app-level unread/mention state in the same JSON file it
  // uses for the tray badge. Watching that file gives the workspace icon the
  // same signal without scraping window titles or trying to count channels.
  FileView {
    id: slackStateFile
    path: root.slackStatePath
    watchChanges: true
    printErrors: false
    onLoaded: root.parseSlackState(text())
    onFileChanged: reload()
    onLoadFailed: root.slackState = null
  }

  function isGmailWindow(appId) {
    return String(appId || "").indexOf(root.gmailAppIdPrefix) === 0
  }

  function parseSlackState(content) {
    try {
      var parsed = JSON.parse(String(content || ""))
      root.slackState = parsed && typeof parsed === "object" ? parsed : null
    } catch (e) {
      root.slackState = null
    }
  }

  function slackHasUnread() {
    return root.slackUnreadCount() > 0
  }

  function slackTitleUnreadCount(toplevel) {
    var title = root.windowTitle(toplevel)
    var match = title.match(/(\d+)\s+new\s+items?/i)
    if (match) return Number(match[1]) || 0
    return /new\s+items?|new\s+messages?|unread/i.test(title) ? 1 : -1
  }

  function signalUnreadCount(toplevel) {
    var title = root.windowTitle(toplevel)
    var match = /\((\d{1,6})\)\s*$/.exec(title)
    return match ? (Number(match[1]) || 0) : 0
  }

  function unreadCountForWindow(appId, toplevel) {
    if (appId === "signal") return root.signalUnreadCount(toplevel)
    if (appId !== "slack") return 0

    var titleCount = root.slackTitleUnreadCount(toplevel)
    return titleCount >= 0 ? titleCount : root.slackUnreadCount()
  }

  function slackUnreadCount() {
    var teams = root.slackState && root.slackState.webapp ? root.slackState.webapp.teams : null
    if (!teams) return 0

    var total = 0

    var ids = Object.keys(teams)
    for (var i = 0; i < ids.length; i++) {
      var unreads = teams[ids[i]] ? teams[ids[i]].unreads : null
      if (!unreads) continue
      // `unreads` is Slack's app badge total; highlights is a useful fallback
      // for workspaces where Slack reports mentions separately.
      total += Math.max(Number(unreads.unreads) || 0, Number(unreads.unreadHighlights) || 0)
    }

    return total
  }

  function windowTitle(toplevel) {
    if (!toplevel) return ""
    if (toplevel.wayland && toplevel.wayland.title) return String(toplevel.wayland.title)
    return String(toplevel.title || "")
  }

  // Accepts both title shapes Gmail ships — "(2) Inbox - you@x - …" and
  // "Inbox (2) - you@x - …" — by reading only the two edges of the first
  // " - " segment, so an open message whose *subject* contains parentheses
  // ("Re: renewal (2 seats) - …") is never misread as a count. Which window
  // is Gmail is decided by app id, not by the title, because a Workspace
  // account ends its title "<domain> Mail" where a personal one says
  // "Gmail" — matching on the word would silently miss the work inbox.
  function gmailUnreadCount(title) {
    var head = String(title || "").split(" - ")[0]
    var match = /^\((\d{1,6})\+?\)/.exec(head) || /\((\d{1,6})\+?\)\s*$/.exec(head)
    if (!match) return 0

    var count = parseInt(match[1], 10)
    return isFinite(count) && count > 0 ? count : 0
  }

  function gmailUnreadForWindow(toplevel, title) {
    var address = String(toplevel && toplevel.address || "")
    var head = String(title || "").split(" - ")[0]
    var inInbox = /\binbox\b/i.test(head)
    var hasExplicitCount = /^\(\d{1,6}\+?\)/.test(head) || /\(\d{1,6}\+?\)\s*$/.test(head)

    // Gmail omits the count while an individual message is open. Preserve
    // the last inbox-reported value until Gmail shows the inbox again.
    if ((inInbox || hasExplicitCount) && address) {
      var count = root.gmailUnreadCount(title)
      if (root.gmailUnreadByAddress[address] !== count) Qt.callLater(function() {
        var updated = Object.assign({}, root.gmailUnreadByAddress)
        updated[address] = count
        root.gmailUnreadByAddress = updated
      })
      return count
    }

    if (address && root.gmailUnreadByAddress[address] !== undefined)
      return Number(root.gmailUnreadByAddress[address]) || 0
    return root.gmailUnreadCount(title)
  }

  // "(2) Inbox - jwage@traderspost.io - traderspost.io Mail". The address is
  // the only part that names the account the same way for both a Workspace
  // and a personal inbox, so the tooltip is keyed off it.
  function gmailAccountLabel(title) {
    var parts = String(title || "").split(" - ")
    for (var i = 0; i < parts.length; i++) {
      var part = parts[i].trim()
      if (/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(part)) return part
    }
    return String(title || "").trim() || "Gmail"
  }

  // Retain the compositor's toplevel order for the icon strip. Sorting by
  // hyprctl's "at" made the strip jump whenever focusing a tiled window
  // changed the layout: the focused window could move to the top-left and
  // suddenly become the first icon. The toplevel collection order is stable
  // for the lifetime of the windows, and changes only when windows are added,
  // removed, or moved between workspaces.
  function windowPosition(toplevel) {
    var ipc = toplevel ? toplevel.lastIpcObject : null
    var at = ipc ? ipc["at"] : null
    var x = (at && at.length > 1) ? Number(at[0]) : 0
    var y = (at && at.length > 1) ? Number(at[1]) : 0
    return { x: isFinite(x) ? x : 0, y: isFinite(y) ? y : 0 }
  }

  // Quickshell refreshes its toplevel list the instant Hyprland reports a
  // window opening or closing -- which is *before* Hyprland has finished
  // re-tiling whatever is left. The geometry the sort reads is therefore the
  // layout mid-rearrange, and the icon order silently drifts out of step with
  // the screen until something else happens to force a refresh. Asking again
  // once the dust has settled is what keeps the two in sync; the timer
  // restarts per event, so a burst collapses into one extra round trip.
  //
  // Swapping two windows within a workspace emits no Hyprland event at all,
  // so that one case cannot be caught directly -- listening to activewindow
  // is what makes it self-correct on the next focus change instead of
  // staying wrong.
  readonly property var geometryEvents: [
    "openwindow", "closewindow", "movewindow", "movewindowv2",
    "changefloatingmode", "fullscreen", "activewindow"
  ]

  Timer {
    id: geometrySettleTimer
    interval: 150
    repeat: false
    onTriggered: Hyprland.refreshToplevels()
  }

  Connections {
    target: Hyprland

    function onRawEvent(event) {
      if (root.geometryEvents.indexOf(event.name) !== -1) geometrySettleTimer.restart()
      if (event.name === "windowtitle" || event.name === "windowtitlev2") root.gmailRevision++
    }
  }

  // Hyprland hands addresses back with and without the 0x prefix depending
  // on which side of the IPC they came from.
  function normalizedAddress(value) {
    return String(value || "").replace(/^0x/i, "").toLowerCase()
  }

  // One entry per window, except Gmail: every Gmail window folds into a
  // single entry carrying the summed unread count, because one mail icon
  // that means "your mail" beats one icon per account. Entries retain the
  // order in which the toplevel collection supplies them, so focusing a
  // window never changes the icon order.
  function buildEntries(toplevels) {
    var gmailRefresh = root.gmailRevision
    var entries = []
    var gmailWindows = []
    var gmailOrder = -1

    for (var i = 0; i < toplevels.length; i++) {
      var toplevel = toplevels[i]
      if (!toplevel) continue
      var address = String(toplevel["address"] || "")
      if (address && !root.settledWindowAddresses[address]) {
        root.settleWindowLater(address)
        continue
      }

      var appId = root.windowAppId(toplevel)
      if (root.isTransientWindow(toplevel, appId)) continue
      if (root.isGmailWindow(appId)) {
        gmailWindows.push(toplevel)
        if (gmailOrder === -1) gmailOrder = i
        continue
      }

      entries.push({
        gmail: false,
        appId: appId,
        toplevel: toplevel,
        address: String(toplevel["address"] || ""),
        position: root.windowPosition(toplevel),
        order: i,
        unread: root.unreadCountForWindow(appId, toplevel),
        accounts: []
      })
    }

    if (gmailWindows.length > 0) {
      var gmailEntry = root.buildGmailEntry(gmailWindows)
      gmailEntry.order = gmailOrder
      entries.push(gmailEntry)
    }

    entries.sort(root.compareEntries)
    return entries
  }

  function buildGmailEntry(windows) {
    var accounts = []
    var total = 0
    var position = null

    for (var i = 0; i < windows.length; i++) {
      var toplevel = windows[i]
      var title = root.windowTitle(toplevel)
      var unread = root.gmailUnreadForWindow(toplevel, title)
      total += unread

      accounts.push({
        label: root.gmailAccountLabel(title),
        unread: unread,
        toplevel: toplevel,
        address: String(toplevel["address"] || "")
      })

      // The group keeps the position of the first Gmail window in the
      // compositor's stable toplevel order.
      var at = root.windowPosition(toplevel)
      if (position === null || at.y < position.y || (at.y === position.y && at.x < position.x)) position = at
    }

    // Sorted by address, never by count: the click cycle and the tooltip
    // must not reshuffle themselves just because a message arrived.
    accounts.sort(function(left, right) { return String(left.label).localeCompare(String(right.label)) })

    return {
      gmail: true,
      appId: root.windowAppId(windows[0]),
      toplevel: windows.length > 0 ? windows[0] : null,
      address: accounts.length > 0 ? accounts[0].address : "",
      position: position || ({ x: 0, y: 0 }),
      unread: total,
      accounts: accounts
    }
  }

  // The explicit order comes from the toplevel collection, not live window
  // geometry. The address tie-break only handles a defensive missing order.
  function compareEntries(left, right) {
    if (left.order !== right.order) return left.order - right.order
    return String(left.address).localeCompare(String(right.address))
  }

  function entryIsFocused(entry) {
    var active = Hyprland.activeToplevel
    if (!entry || !active) return false
    var activeAddress = root.normalizedAddress(active.address)
    if (entry.gmail && entry.accounts) {
      for (var i = 0; i < entry.accounts.length; i++)
        if (root.normalizedAddress(entry.accounts[i].address) === activeAddress) return true
      return false
    }
    return root.normalizedAddress(entry.address) === activeAddress
  }

  function gmailTooltip(entry) {
    if (!entry || !entry.accounts) return ""

    var lines = []
    for (var i = 0; i < entry.accounts.length; i++) {
      var account = entry.accounts[i]
      lines.push(account.label + "   " + (account.unread > 0 ? account.unread + " unread" : "no unread"))
    }
    return lines.join("\n")
  }

  // Unread inboxes first, then the rest, always in the same order — and
  // always advancing past whatever is focused, so clicking a second time
  // reliably lands on the other account instead of re-focusing this one.
  function focusGmail(entry) {
    if (!entry || !entry.accounts || entry.accounts.length === 0) return

    var ordered = []
    for (var i = 0; i < entry.accounts.length; i++) if (entry.accounts[i].unread > 0) ordered.push(entry.accounts[i])
    for (var j = 0; j < entry.accounts.length; j++) if (entry.accounts[j].unread <= 0) ordered.push(entry.accounts[j])

    var focused = Hyprland.activeToplevel ? root.normalizedAddress(Hyprland.activeToplevel.address) : ""
    var index = -1
    for (var k = 0; k < ordered.length; k++) {
      if (root.normalizedAddress(ordered[k].address) === focused) {
        index = k
        break
      }
    }

    var next = ordered[(index + 1) % ordered.length]
    root.focusToplevel(next.toplevel, next.address)
  }

  // App icons come from the window's app id. A window's app id and its
  // .desktop file's Icon= often differ (e.g. appId "cursor" but
  // Icon=co.anysphere.cursor, appId "signal" but Icon=signal-desktop), so
  // resolve the desktop entry first via Quickshell's own heuristic matcher
  // before trying the app id directly, then fall back to a generic icon.
  function windowIconSource(appId, address) {
    var name = String(appId || "").trim()
    if (!name) return Quickshell.iconPath("application-x-executable", true)

    // Reuse Slack's status-notifier icon. Slack updates this icon immediately
    // when its unread state changes, including the app-provided badge.
    if (name === "slack") {
      var slackIcon = root.slackTrayIconSource()
      if (slackIcon.length > 0) return slackIcon
    }

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

      // Draw nothing at all until the probe answers, rather than guessing
      // from the configured default agent. The guess is wrong for every
      // window not running that agent — it is what made a Codex window show
      // Claude's mark — and when the default has not loaded yet it degrades
      // to the generic executable glyph, so a brand-new window flashed a
      // meaningless icon either way. Probes finish in well under a second,
      // so the slot just stays blank until the real mark is known.
      if (resolved === undefined) return ""

      if (root.agentIconIds.indexOf(resolved) !== -1)
        return Util.fileUrl(root.omarchyPath + "/shell/plugins/agents/assets/" + resolved + ".svg")

      var themeIconName = root.agentThemeIconNames[resolved]
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
    columnSpacing: root.vertical ? 0 : Style.space(5)
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
        // Windows folded into what the strip actually draws: Gmail collapsed
        // to one entry, everything kept in stable compositor order.
        readonly property var entries: root.buildEntries(toplevels)
        readonly property bool isFirstWorkspace: modelData === root.workspaceIds()[0]

        bar: root.bar
        text: numberText
        labelVisible: false
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : content.implicitWidth + Style.space(12)
        fixedHeight: root.barSize
        onPressed: function() { root.focusWorkspace(modelData) }

        // Separates one workspace from the next now that the focused app's
        // own underline (below) is what marks the active workspace -- the
        // divider is just structure, not a focus indicator, so it doesn't
        // change color or hide itself when focused, and it sits outside
        // dimmableContent below so an empty, unfocused neighbor doesn't
        // fade it too.
        Rectangle {
          anchors.left: parent.left
          anchors.leftMargin: -Style.space(2)
          anchors.verticalCenter: parent.verticalCenter
          width: 1
          height: Style.space(16)
          color: root.bar ? root.bar.barForeground : Color.foreground
          opacity: 0.3
          visible: !root.vertical && !workspaceButton.isFirstWorkspace
        }

        Item {
          id: dimmableContent
          anchors.fill: parent
          opacity: workspaceButton.occupied || workspaceButton.focused ? 1 : 0.5

          Row {
            id: content
            anchors.centerIn: parent
            spacing: Style.space(3)

            // Empty workspaces have no app icon to show focus on, so they keep
            // the number -- with the same accent pill as before when focused.
            // An occupied workspace drops both: the focused app's own
            // underline (below) already marks which one is active.
            Rectangle {
              id: numberBadge
              anchors.verticalCenter: parent.verticalCenter
              width: Math.max(height, numberLabel.implicitWidth + Style.space(6))
              height: Style.space(16)
              radius: height / 2
              color: workspaceButton.focused ? Color.accent : "transparent"
              visible: !workspaceButton.showIcons

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
            model: workspaceButton.showIcons ? workspaceButton.entries.length : 0

            // A plain Item rather than a Row: the click target has to cover
            // the icon *and* its count, and a MouseArea inside a positioner
            // would be laid out as another cell of it instead of overlaying
            // one. Collapses to exactly the icon's width whenever there is no
            // count to show, so every window that isn't Gmail is untouched.
            Item {
              id: windowEntry
              required property int index
              readonly property var entry: workspaceButton.entries[index] || null
              readonly property bool isGmail: entry !== null && entry.gmail === true
              readonly property bool isSlack: entry !== null && entry.appId === "slack"
              readonly property int unreadCount: entry !== null ? entry.unread : 0
              readonly property bool appFocused: root.entryIsFocused(entry)
              // Slack's status-notifier icon already carries its live unread
              // indicator; use that same icon rather than a second stale badge.
              readonly property bool hasUnreadIndicator: unreadCount > 0 && !isSlack
              // Bar.showTooltip only accepts a target that reports itself
              // hovered, so the flag has to live on the item being pointed at.
              property bool tooltipHovered: false
              property var registeredBar: null

              // Every ModuleSlot is covered by the bar's own drag-to-reorder
              // MouseArea, which sits above module content and swallows the
              // press, then re-dispatches it to whichever *registered* click
              // target contains the point (Bar.pressModuleClickTarget). A
              // MouseArea declared in here therefore never sees a click at
              // all -- which is why clicking an icon used to do nothing but
              // switch workspace: the only registered target under the
              // pointer was the workspace button wrapping it. Registering
              // each icon puts it in that same lookup.
              //
              // Hover is unaffected and still arrives here directly, which is
              // what the tooltip below rides on.
              function triggerPress(button) {
                if (root.bar) root.bar.hideTooltip(windowEntry)
                if (button !== Qt.LeftButton || !windowEntry.entry) return

                if (windowEntry.isGmail) root.focusGmail(windowEntry.entry)
                else root.focusToplevel(windowEntry.entry.toplevel, windowEntry.entry.address)
              }

              // The lookup scans registrations newest-first, so the last one
              // in wins the point -- and the workspace button re-registers
              // itself whenever the bar is injected into it, which happens
              // after these delegates have been built. Re-registering on that
              // same signal (deferred, so it lands after the button's own
              // handler) and again on hover keeps the icon ahead of the
              // button it sits inside.
              function syncClickRegistration() {
                if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(windowEntry)
                registeredBar = root.bar
                if (registeredBar && registeredBar.registerClickTarget) registeredBar.registerClickTarget(windowEntry)
              }

              Component.onCompleted: syncClickRegistration()
              Component.onDestruction: if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(windowEntry)

              Connections {
                target: root
                function onBarChanged() { Qt.callLater(windowEntry.syncClickRegistration) }
              }

              anchors.verticalCenter: parent.verticalCenter
              opacity: windowEntry.appFocused ? 1.0 : 0.55
              // The unread count is an overlay, so it must not widen the icon
              // slot or push the following app away from its normal spacing.
              implicitWidth: windowIcon.width
              implicitHeight: root.iconSize

              Image {
                id: windowIcon
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: root.iconSize
                height: root.iconSize
                fillMode: Image.PreserveAspectFit
                sourceSize.width: width * Screen.devicePixelRatio
                sourceSize.height: height * Screen.devicePixelRatio
                source: root.windowIconSource(windowEntry.entry ? windowEntry.entry.appId : "",
                                              windowEntry.entry ? windowEntry.entry.address : "")
              }

              Rectangle {
                anchors.horizontalCenter: windowIcon.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: -5
                width: Math.round(windowIcon.width * 1.0)
                height: 2
                radius: 1
                color: Color.accent
                visible: windowEntry.appFocused
                z: 3
              }

              // Familiar notification-badge treatment: the count sits over
              // the icon's top-right corner, staying circular for one digit
              // and becoming a compact pill for larger counts. Zero unread
              // hides it entirely; 100+ is deliberately capped to keep the
              // badge from becoming a second label.
              BorderSurface {
                id: unreadLabel
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: -width * 0.22
                anchors.topMargin: -height * 0.16
                visible: windowEntry.hasUnreadIndicator
                z: 2
                height: Math.max(12, Math.round(root.iconSize * 0.62))
                width: Math.max(height, unreadText.implicitWidth + Style.space(4))
                radius: height / 2
                color: root.bar ? root.bar.barForeground : Color.foreground
                borderSpec: Border.flat(Color.accent, 1)

                Text {
                  id: unreadText
                  anchors.centerIn: parent
                  text: windowEntry.unreadCount > root.maxUnreadShown ? (root.maxUnreadShown + "+") : String(windowEntry.unreadCount)
                  color: Color.accent
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Math.max(8, Math.round(parent.height * 0.74))
                  font.bold: true
                }
              }

              // Hover only. The click itself arrives through triggerPress
              // above, since the bar intercepts presses before they reach
              // here; this exists to drive the tooltip and to keep the icon's
              // registration ahead of the workspace button's.
              MouseArea {
                id: entryMouse
                anchors.fill: parent
                hoverEnabled: true

                onEntered: {
                  windowEntry.syncClickRegistration()
                  windowEntry.tooltipHovered = true
                  if (windowEntry.isGmail && root.bar) root.bar.showTooltip(windowEntry, root.gmailTooltip(windowEntry.entry))
                }

                onExited: {
                  windowEntry.tooltipHovered = false
                  if (root.bar) root.bar.hideTooltip(windowEntry)
                }
              }
            }
          }
        }
        }
      }
    }
  }
}
