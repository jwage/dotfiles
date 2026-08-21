// Parsing, grading and formatting for the TradersPost health widget.
//
// Deliberately Qt-free so it can be unit tested under node
// (test-model.js next to this file); the QML owns colour and layout, this owns
// what the numbers mean and how they read.
//
// The grades themselves come from traderspost-health, which mirrors the
// thresholds in New Relic's own alert policy. Nothing here invents a threshold;
// the one judgement made in this file is how a set of per-metric grades rolls
// up into the single word the bar shows.

// Worst-first, so a roll-up is "the first status present in this list".
var STATUS_ORDER = ["critical", "warning", "unknown", "ok"]

// The metric rows in the "application traffic" section, in order. The trading
// pipeline is not here: it is an ordered list of its own (see normalizeStages),
// because its order is the order a trade travels rather than a display choice.
var METRIC_ORDER = [
  "errorRate",
  "synthetic"
]

var STATUS_WORDS = {
  ok: "Healthy",
  warning: "Degraded",
  critical: "Unhealthy",
  unknown: "No data"
}

function statusWord(status) {
  return STATUS_WORDS[String(status)] || STATUS_WORDS.unknown
}

// Worst of a list of statuses. Used for the roll-up when a caller wants to
// grade a subset (the panel's queue section, say) rather than the whole payload.
function worstStatus(statuses) {
  for (var i = 0; i < STATUS_ORDER.length; i++) {
    var candidate = STATUS_ORDER[i]
    for (var j = 0; j < (statuses || []).length; j++)
      if (String(statuses[j]) === candidate) return candidate
  }
  return "unknown"
}

// The helper's stdout, turned into something the QML can bind to without
// worrying about shape. Anything unparseable is a no-data state carrying the
// reason, never a throw — the widget has to stay on the bar through a failed
// poll, and a grey dot with a message is more use than a blank slot.
function parseHealth(raw) {
  var text = String(raw === undefined || raw === null ? "" : raw).replace(/^\s+|\s+$/g, "")
  if (text === "") return failure("no output from traderspost-health")

  var payload
  try {
    payload = JSON.parse(text)
  } catch (e) {
    return failure("unreadable output from traderspost-health")
  }
  if (!payload || typeof payload !== "object") return failure("unexpected output shape")
  if (payload.ok !== true) return failure(String(payload.error || "New Relic unavailable"))

  var metrics = payload.metrics && typeof payload.metrics === "object" ? payload.metrics : {}
  var rows = []
  for (var i = 0; i < METRIC_ORDER.length; i++) {
    var key = METRIC_ORDER[i]
    var metric = metrics[key]
    if (!metric) continue
    rows.push({
      key: key,
      label: String(metric.label || key),
      grade: String(metric.grade || "info"),
      detail: String(metric.detail || ""),
      text: formatMetric(metric)
    })
  }

  var stages = normalizeStages(payload.stages)
  // Same shape as a pipeline stage, because it is the same kind of measurement
  // -- rate, run, wait -- and reads better in the same row than as three
  // separate metric rows.
  var traffic = normalizeStages(payload.traffic)
  var externals = normalizeExternals(payload.externals)

  // One alignment pass over both stage-shaped groups, so the web traffic row's
  // columns land under the pipeline's rather than beside them.
  alignColumns([stages, traffic], ["rateText", "runText", "waitText"])
  alignColumns([externals], ["rateText", "text"])

  return {
    ok: true,
    status: String(payload.status || "unknown"),
    app: String(payload.app || ""),
    rows: rows,
    stages: stages,
    traffic: traffic,
    externals: externals,
    issues: normalizeIssues(payload.issues),
    error: ""
  }
}

// The trading pipeline, in the order the helper sent it -- which is the order a
// trade travels: receive the webhook, relay it through the outbox, handle it,
// then place it live or on paper. Never re-sorted: the sequence is the
// information, so a stage backing up is read by where it sits in the chain.
//
// Every stage carries the same three figures -- rate, run, wait -- which is what
// lets them be padded into columns further down.
function normalizeStages(stages) {
  var out = []
  for (var i = 0; i < (stages || []).length; i++) {
    var stage = stages[i] || {}
    var wait = Number(stage.wait)
    var run = Number(stage.run)
    var hasWait = stage.wait !== null && stage.wait !== undefined && isFinite(wait)

    out.push({
      key: String(stage.key || ""),
      label: String(stage.label || stage.key || "unknown"),
      grade: String(stage.grade || "info"),
      rateText: formatRate(stage.rate),
      runText: isFinite(run) ? formatMs(run) + " run" : "",
      waitText: hasWait ? formatMs(wait) + " wait" : "",
      // Both kinds of stage report a wait, but they are graded on different
      // scales -- the message queues against the alert policy's 1000ms, the web
      // stages against WEB_QUEUE_* -- which the helper has already applied. This
      // only records whether there is a verdict to paint.
      graded: hasWait && stage.waitGraded === true
    })
  }
  return out
}

// ---- Column alignment. Every figure in these sections is scanned down a
//      column rather than read across a row, so each column is padded to a
//      common width and the digits line up.
//
//      Done here rather than with fixed widths in the QML because this is where
//      the strings are made, it is testable, and it adapts to whatever the
//      numbers happen to be: "1,069/min" and "<1/min" get the same column
//      without anyone picking a pixel width. It does assume the panel's font is
//      monospace, which is what Omarchy ships (JetBrainsMono Nerd Font) and what
//      the shell's own section headers already assume.

function padLeft(text, width) {
  var out = String(text === undefined || text === null ? "" : text)
  // No String.padStart: Qt's JS engine is older than the QML this has to run in.
  while (out.length < width) out = " " + out
  return out
}

// Pads the named fields to a common width across every row in every group, so
// separate sections (the pipeline and the web traffic row below it) still line
// up with each other.
function alignColumns(groups, keys) {
  var widths = {}
  var g, r, k, key

  for (k = 0; k < keys.length; k++) widths[keys[k]] = 0
  for (g = 0; g < groups.length; g++) {
    for (r = 0; r < (groups[g] || []).length; r++) {
      for (k = 0; k < keys.length; k++) {
        key = keys[k]
        var length = String(groups[g][r][key] || "").length
        if (length > widths[key]) widths[key] = length
      }
    }
  }
  for (g = 0; g < groups.length; g++) {
    for (r = 0; r < (groups[g] || []).length; r++) {
      for (k = 0; k < keys.length; k++) {
        key = keys[k]
        groups[g][r][key] = padLeft(groups[g][r][key], widths[key])
      }
    }
  }
  return groups
}

// External-call latencies, in the order the helper sent them (slowest first).
// Kept as its own list rather than folded into `rows` because these carry no
// grade: nothing in New Relic says what "slow" means for an external call, so
// there is no colour to assign and the ordering is the signal.
function normalizeExternals(externals) {
  var out = []
  for (var i = 0; i < (externals || []).length; i++) {
    var host = externals[i] || {}
    var ms = Number(host.ms)
    out.push({
      host: String(host.host || ""),
      label: String(host.label || host.host || "unknown"),
      text: isFinite(ms) ? formatMs(ms) : "—",
      rateText: formatRate(host.rpm)
    })
  }
  return out
}

function failure(message) {
  return {
    ok: false,
    status: "unknown",
    app: "",
    rows: [],
    stages: [],
    traffic: [],
    externals: [],
    issues: [],
    error: String(message || "unavailable")
  }
}

function normalizeIssues(issues) {
  var out = []
  for (var i = 0; i < (issues || []).length; i++) {
    var issue = issues[i] || {}
    out.push({
      title: String(issue.title || "Untitled issue"),
      priority: String(issue.priority || ""),
      entities: (issue.entities || []).map(String)
    })
  }
  return out
}

// ---- Number formatting. Every value the cockpit shows is glanced at, not
//      read, so precision is spent only where a difference changes a decision:
//      sub-millisecond queue waits and a fractional error rate both matter,
//      a throughput of 1164.2/min does not.

function formatMetric(metric) {
  var value = metric ? metric.value : null
  if (value === null || value === undefined || !isFinite(Number(value))) return "—"
  var number = Number(value)
  var unit = String(metric.unit || "")

  if (unit === "%") return formatPercent(number)
  if (unit === "ms") return formatMs(number)
  if (unit === "/min") return formatCount(number) + "/min"
  return formatCount(number)
}

// Two decimals below 1% so 0.04% is distinguishable from zero — at that scale
// the difference is "a handful of failures" versus "none", which is exactly the
// distinction worth having. Above 1% the decimals stop earning their space.
function formatPercent(value) {
  if (value === 0) return "0.00%"
  if (value < 1) return value.toFixed(2) + "%"
  return value.toFixed(1) + "%"
}

// Milliseconds up to a second, then seconds — a queue wait of 4200ms reads
// faster as 4.2s, and by then the exact millisecond has stopped mattering.
function formatMs(value) {
  if (value < 1) return value < 0.1 ? "<0.1ms" : value.toFixed(1) + "ms"
  if (value < 1000) return Math.round(value) + "ms"
  return (value / 1000).toFixed(value < 10000 ? 1 : 0) + "s"
}

function formatRate(value) {
  var number = Number(value)
  if (!isFinite(number) || number <= 0) return "idle"
  if (number < 1) return "<1/min"
  return formatCount(number) + "/min"
}

function formatCount(value) {
  if (value >= 100000) return Math.round(value / 1000) + "k"
  if (value >= 10000) return (value / 1000).toFixed(1) + "k"
  return String(Math.round(value)).replace(/\B(?=(\d{3})+(?!\d))/g, ",")
}

// ---- Bar label. Just the dot: colour is the whole message at bar scale, and a
//      response time beside it was noise -- a number nobody acts on, changing
//      every poll. The detail lives one hover (tooltip) or one click (panel)
//      away, and freshness is carried by the dot going grey rather than by a
//      figure ticking over.

function barLabel(health) {
  return "●"
}

function findRow(health, key) {
  var rows = (health && health.rows) || []
  for (var i = 0; i < rows.length; i++) if (rows[i].key === String(key)) return rows[i]
  return null
}

// One-line summary for the bar tooltip and for `omarchy-notification-send`.
function summaryLine(health) {
  if (!health || !health.ok) return "TradersPost: " + ((health && health.error) || "unavailable")

  var parts = ["TradersPost: " + statusWord(health.status)]
  if (health.issues.length > 0)
    parts.push(health.issues.length + (health.issues.length === 1 ? " open issue" : " open issues"))

  var interesting = ["errorRate", "webThroughput"]
  for (var i = 0; i < interesting.length; i++) {
    var row = findRow(health, interesting[i])
    if (row && row.text !== "—") parts.push(row.label + " " + row.text)
  }
  // The pipeline's own summary is the slowest stage still moving trades, which
  // is the thing worth putting in a notification.
  var worst = null
  for (var j = 0; j < (health.stages || []).length; j++) {
    var stage = health.stages[j]
    if (!stage.graded) continue
    if (worst === null || rank(stage.grade) < rank(worst.grade)) worst = stage
  }
  if (worst) parts.push(worst.label + " " + worst.waitText)
  return parts.join(" · ")
}

function rank(grade) {
  var index = STATUS_ORDER.indexOf(String(grade))
  return index === -1 ? STATUS_ORDER.length : index
}

// ---- Freshness. A cockpit that silently shows five-minute-old numbers is
//      worse than one that admits it, so the panel prints the age of the last
//      successful poll and the dot goes grey once it is stale.

function ageText(ageMs) {
  var seconds = Math.max(0, Math.round(Number(ageMs) / 1000))
  if (!isFinite(seconds)) return "never"
  if (seconds < 5) return "just now"
  if (seconds < 60) return seconds + "s ago"
  var minutes = Math.round(seconds / 60)
  if (minutes < 60) return minutes + "m ago"
  return Math.round(minutes / 60) + "h ago"
}

// Three missed polls. One slow or dropped request is normal on a laptop that
// suspends and resumes; three in a row means the number on screen is no longer
// something to make a decision from.
function isStale(ageMs, pollIntervalMs) {
  var interval = Number(pollIntervalMs)
  if (!isFinite(interval) || interval <= 0) return false
  return Number(ageMs) > interval * 3
}

// Poll interval, in ms, from the widget's shell.json settings. Clamped: below
// 15s this is just burning NerdGraph quota on a 5-minute query window, and
// above an hour the widget is decoration rather than a cockpit.
function pollIntervalMs(configuredSeconds) {
  var seconds = Number(configuredSeconds)
  if (!isFinite(seconds) || seconds <= 0) seconds = 60
  return Math.max(15, Math.min(3600, Math.round(seconds))) * 1000
}

if (typeof module !== "undefined") {
  module.exports = {
    METRIC_ORDER: METRIC_ORDER,
    statusWord: statusWord,
    worstStatus: worstStatus,
    parseHealth: parseHealth,
    formatMetric: formatMetric,
    formatPercent: formatPercent,
    formatMs: formatMs,
    formatRate: formatRate,
    formatCount: formatCount,
    normalizeExternals: normalizeExternals,
    normalizeStages: normalizeStages,
    alignColumns: alignColumns,
    padLeft: padLeft,
    barLabel: barLabel,
    findRow: findRow,
    summaryLine: summaryLine,
    ageText: ageText,
    isStale: isStale,
    pollIntervalMs: pollIntervalMs
  }
}
