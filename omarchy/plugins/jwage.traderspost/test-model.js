#!/usr/bin/env node
// Unit tests for Model.js. Run: node test-model.js
//
// Model.js is the only part of this widget with logic worth being wrong about,
// and it is the part that is awkward to exercise inside a running shell -- so it
// is kept Qt-free and tested here instead.

const assert = require("assert")
const Model = require("./Model.js")

let checks = 0
function check(name, fn) {
  fn()
  checks++
}

// ---- Formatting

check("percent keeps two decimals below 1% so a trickle is not shown as zero", () => {
  assert.strictEqual(Model.formatPercent(0), "0.00%")
  assert.strictEqual(Model.formatPercent(0.04), "0.04%")
  assert.strictEqual(Model.formatPercent(0.996), "1.00%")
  assert.strictEqual(Model.formatPercent(12.34), "12.3%")
})

check("ms switches to seconds past a second", () => {
  assert.strictEqual(Model.formatMs(0.05), "<0.1ms")
  assert.strictEqual(Model.formatMs(0.4), "0.4ms")
  assert.strictEqual(Model.formatMs(3.9), "4ms")
  assert.strictEqual(Model.formatMs(999), "999ms")
  assert.strictEqual(Model.formatMs(1000), "1.0s")
  assert.strictEqual(Model.formatMs(4200), "4.2s")
  assert.strictEqual(Model.formatMs(65000), "65s")
})

check("counts get thousands separators, then abbreviate", () => {
  assert.strictEqual(Model.formatCount(0), "0")
  assert.strictEqual(Model.formatCount(1980), "1,980")
  assert.strictEqual(Model.formatCount(9999), "9,999")
  assert.strictEqual(Model.formatCount(12345), "12.3k")
  assert.strictEqual(Model.formatCount(250000), "250k")
})

check("a missing value formats as a dash rather than NaN", () => {
  assert.strictEqual(Model.formatMetric({ value: null, unit: "ms" }), "—")
  assert.strictEqual(Model.formatMetric({ value: undefined, unit: "%" }), "—")
  assert.strictEqual(Model.formatMetric(null), "—")
  assert.strictEqual(Model.formatMetric({ value: "nonsense", unit: "ms" }), "—")
})

// ---- Roll-up

check("worst status wins, and absent grades are not treated as healthy", () => {
  assert.strictEqual(Model.worstStatus(["ok", "warning", "critical"]), "critical")
  assert.strictEqual(Model.worstStatus(["ok", "warning"]), "warning")
  assert.strictEqual(Model.worstStatus(["ok", "unknown"]), "unknown")
  assert.strictEqual(Model.worstStatus(["ok", "ok"]), "ok")
  assert.strictEqual(Model.worstStatus([]), "unknown")
})

// ---- Parsing

const healthy = JSON.stringify({
  ok: true,
  status: "ok",
  app: "TradersPost Heroku Production",
  stages: [
    { key: "receive", label: "Receive Webhook", rate: 184.2, wait: null, run: 11.4, extra: 13.8, extraLabel: "p95", grade: "info" },
    { key: "outbox", label: "Outbox", rate: 183.1, wait: 4.1, run: 7.6, grade: "ok" },
    { key: "handle", label: "Handle Webhook", rate: 185.0, wait: 6.2, run: 21.8, grade: "ok" },
    { key: "live", label: "Live Trades", rate: 47.3, wait: 1420.5, run: 336.1, grade: "critical" },
    { key: "paper", label: "Paper Trades", rate: 141.2, wait: 6.0, run: 160.4, grade: "ok" }
  ],
  metrics: {
    errorRate: { value: 0, unit: "%", grade: "ok", label: "Error rate" },
    webDuration: { value: 107.8, unit: "ms", grade: "info", label: "Web response" },
    webThroughput: { value: 1164.2, unit: "/min", grade: "info", label: "Web throughput" }
  },
  externals: [
    { host: "sandbox.tradier.com", label: "Tradier paper", ms: 787.4, rpm: 47.2 },
    { host: "api.stripe.com", label: "Stripe", ms: 262.0, rpm: 4.1 },
    { host: "api.ibkr.com", label: "IBKR", ms: 134.1, rpm: 1069.3 },
    { host: "api.newbroker.example", label: "api.newbroker.example", ms: 0.4, rpm: 0.2 }
  ],
  issues: []
})

check("a healthy payload parses into ordered rows", () => {
  const health = Model.parseHealth(healthy)
  assert.strictEqual(health.ok, true)
  assert.strictEqual(health.status, "ok")
  assert.deepStrictEqual(health.rows.map(r => r.key),
    ["errorRate", "webThroughput", "webDuration"])
  assert.strictEqual(Model.findRow(health, "errorRate").text, "0.00%")
})

check("stages keep pipeline order, never sorted by value", () => {
  const health = Model.parseHealth(healthy)
  assert.deepStrictEqual(health.stages.map(s => s.label),
    ["Receive Webhook", "Outbox", "Handle Webhook", "Live Trades", "Paper Trades"])
  // Live Trades is the worst stage by far; it must still sit fourth, because
  // the sequence is the information.
  assert.strictEqual(health.stages[3].grade, "critical")
})

check("each stage formats its three figures, and only a wait is graded", () => {
  const stages = Model.parseHealth(healthy).stages
  const receive = stages[0], live = stages[3]
  assert.strictEqual(receive.rateText, "184/min")
  assert.strictEqual(receive.runText, "11ms run")
  // The front door has no queue, so its trailing figure is the p95 and it
  // carries no verdict.
  assert.strictEqual(receive.tailText, "14ms p95")
  assert.strictEqual(receive.graded, false)
  assert.strictEqual(live.tailText, "1.4s wait")
  assert.strictEqual(live.graded, true)
})

check("a stage missing its numbers degrades instead of printing NaN", () => {
  assert.deepStrictEqual(Model.normalizeStages([{ key: "x", label: "X" }]),
    [{ key: "x", label: "X", grade: "info", rateText: "idle", runText: "", tailText: "", graded: false }])
  assert.deepStrictEqual(Model.normalizeStages(undefined), [])
})

check("externals keep the helper's slowest-first order and are not metric rows", () => {
  const health = Model.parseHealth(healthy)
  assert.deepStrictEqual(health.externals.map(b => b.label),
    ["Tradier paper", "Stripe", "IBKR", "api.newbroker.example"])
  assert.deepStrictEqual(health.externals.map(b => b.text), ["787ms", "262ms", "134ms", "0.4ms"])
  // Rate is context for the latency beside it, rounded hard.
  assert.deepStrictEqual(health.externals.map(b => b.rateText),
    ["47/min", "4/min", "1,069/min", "<1/min"])
  // Non-brokers are listed too: the panel shows all external traffic, so Stripe
  // must not be filtered out the way an earlier broker-only version did.
  assert.ok(health.externals.some(b => b.host === "api.stripe.com"))
  // None of them leak into the graded metric rows.
  assert.strictEqual(health.rows.some(r => r.key === "externals"), false)
})

check("an unrecognised host still lists, under its hostname", () => {
  // traderspost-health filters nothing, so a newly called dependency appears on
  // its own; the model must not drop it for lacking a pretty label.
  const health = Model.parseHealth(healthy)
  const fresh = health.externals[health.externals.length - 1]
  assert.strictEqual(fresh.label, "api.newbroker.example")
  assert.strictEqual(fresh.host, "api.newbroker.example")
})

check("call rates degrade sanely", () => {
  assert.strictEqual(Model.formatRate(0), "idle")
  assert.strictEqual(Model.formatRate(null), "idle")
  assert.strictEqual(Model.formatRate(-3), "idle")
  assert.strictEqual(Model.formatRate(0.4), "<1/min")
  assert.strictEqual(Model.formatRate(1069.3), "1,069/min")
  assert.strictEqual(Model.formatRate(25000), "25.0k/min")
})

check("a payload with no externals at all is an empty list, not a crash", () => {
  const health = Model.parseHealth(JSON.stringify({ ok: true, status: "ok", metrics: {}, issues: [] }))
  assert.deepStrictEqual(health.externals, [])
  assert.deepStrictEqual(Model.normalizeExternals(undefined), [])
  // A malformed entry becomes a dash rather than dropping the row.
  assert.deepStrictEqual(Model.normalizeExternals([{}]),
    [{ host: "", label: "unknown", text: "—", rateText: "idle" }])
})

check("rows follow METRIC_ORDER, not the order the JSON happened to use", () => {
  const scrambled = JSON.stringify({
    ok: true, status: "ok", metrics: {
      webDuration: { value: 1, unit: "ms", grade: "info", label: "Web response" },
      errorRate: { value: 0, unit: "%", grade: "ok", label: "Error rate" }
    }, issues: []
  })
  assert.deepStrictEqual(Model.parseHealth(scrambled).rows.map(r => r.key),
    ["errorRate", "webDuration"])
})

check("failures degrade to a no-data state with a reason, never a throw", () => {
  for (const [input, expectation] of [
    ["", /no output/],
    ["not json at all", /unreadable/],
    ["null", /unexpected output shape/],
    ['{"ok":false,"error":"401 Unauthorized"}', /401 Unauthorized/],
    ['{"ok":false}', /unavailable/]
  ]) {
    const health = Model.parseHealth(input)
    assert.strictEqual(health.ok, false, `expected failure for ${JSON.stringify(input)}`)
    assert.strictEqual(health.status, "unknown")
    assert.deepStrictEqual(health.rows, [])
    assert.deepStrictEqual(health.externals, [])
    assert.deepStrictEqual(health.stages, [])
    assert.match(health.error, expectation)
  }
})

check("open issues are normalised even when fields are missing", () => {
  const health = Model.parseHealth(JSON.stringify({
    ok: true, status: "critical", metrics: {},
    issues: [{ title: "Elevated Live Queue Wait Time", priority: "CRITICAL", entities: ["TradersPost Heroku Production"] }, {}]
  }))
  assert.strictEqual(health.issues.length, 2)
  assert.strictEqual(health.issues[0].priority, "CRITICAL")
  assert.strictEqual(health.issues[1].title, "Untitled issue")
  assert.deepStrictEqual(health.issues[1].entities, [])
})

// ---- Labels

check("the bar label is the dot and nothing else, in every state", () => {
  // No response time beside it: colour is the whole message at bar scale. And a
  // failed poll still keeps the dot -- the widget must not vanish off the bar.
  assert.strictEqual(Model.barLabel(Model.parseHealth(healthy)), "●")
  assert.strictEqual(Model.barLabel(Model.parseHealth("broken")), "●")
  assert.strictEqual(Model.barLabel(null), "●")
})

check("the summary line leads with the verdict and names the worst stage", () => {
  const line = Model.summaryLine(Model.parseHealth(healthy))
  assert.match(line, /^TradersPost: Healthy/)
  // Of the graded stages, Live Trades is the worst -- that is the one worth
  // putting in a notification.
  assert.match(line, /Live Trades 1\.4s wait$/)
  assert.match(Model.summaryLine(Model.parseHealth("broken")), /unreadable/)
  const critical = Model.parseHealth(JSON.stringify({
    ok: true, status: "critical", metrics: {}, issues: [{ title: "x", priority: "CRITICAL" }]
  }))
  assert.match(Model.summaryLine(critical), /Unhealthy · 1 open issue$/)
})

// ---- Freshness

check("age reads in the largest useful unit", () => {
  assert.strictEqual(Model.ageText(0), "just now")
  assert.strictEqual(Model.ageText(4000), "just now")
  assert.strictEqual(Model.ageText(30000), "30s ago")
  assert.strictEqual(Model.ageText(90000), "2m ago")
  assert.strictEqual(Model.ageText(3600000), "1h ago")
})

check("staleness is three missed polls, not one", () => {
  const interval = 60000
  assert.strictEqual(Model.isStale(60000, interval), false)
  assert.strictEqual(Model.isStale(179000, interval), false)
  assert.strictEqual(Model.isStale(181000, interval), true)
  // Without a known interval nothing can be called stale.
  assert.strictEqual(Model.isStale(999999, 0), false)
})

check("the poll interval is clamped to something defensible", () => {
  assert.strictEqual(Model.pollIntervalMs(undefined), 60000)
  assert.strictEqual(Model.pollIntervalMs(0), 60000)
  assert.strictEqual(Model.pollIntervalMs("nonsense"), 60000)
  assert.strictEqual(Model.pollIntervalMs(1), 15000)
  assert.strictEqual(Model.pollIntervalMs(120), 120000)
  assert.strictEqual(Model.pollIntervalMs(99999), 3600000)
})

console.log(`ok - ${checks} checks passed`)
