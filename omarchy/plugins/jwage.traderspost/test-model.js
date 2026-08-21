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
  metrics: {
    liveQueueWait: { value: 3.93, unit: "ms", grade: "ok", label: "Live queue wait" },
    errorRate: { value: 0, unit: "%", grade: "ok", label: "Error rate" },
    webDuration: { value: 107.8, unit: "ms", grade: "info", label: "Web response" },
    slowestBroker: { value: 410, unit: "ms", grade: "info", label: "Slowest API", detail: "api.stripe.com" }
  },
  issues: []
})

check("a healthy payload parses into ordered rows", () => {
  const health = Model.parseHealth(healthy)
  assert.strictEqual(health.ok, true)
  assert.strictEqual(health.status, "ok")
  assert.deepStrictEqual(health.rows.map(r => r.key),
    ["liveQueueWait", "errorRate", "webDuration", "slowestBroker"])
  assert.strictEqual(Model.findRow(health, "liveQueueWait").text, "4ms")
  assert.strictEqual(Model.findRow(health, "slowestBroker").detail, "api.stripe.com")
})

check("rows follow METRIC_ORDER, not the order the JSON happened to use", () => {
  const scrambled = JSON.stringify({
    ok: true, status: "ok", metrics: {
      slowestBroker: { value: 1, unit: "ms", grade: "info", label: "Slowest API" },
      liveQueueWait: { value: 1, unit: "ms", grade: "ok", label: "Live queue wait" }
    }, issues: []
  })
  assert.deepStrictEqual(Model.parseHealth(scrambled).rows.map(r => r.key),
    ["liveQueueWait", "slowestBroker"])
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

check("the bar label carries the dot, plus latency when there is room", () => {
  const health = Model.parseHealth(healthy)
  assert.strictEqual(Model.barLabel(health, false), "●")
  assert.strictEqual(Model.barLabel(health, true), "● 108ms")
  // A failed poll keeps the dot -- the widget must not vanish off the bar.
  assert.strictEqual(Model.barLabel(Model.parseHealth("broken"), true), "●")
})

check("the summary line leads with the verdict", () => {
  assert.match(Model.summaryLine(Model.parseHealth(healthy)), /^TradersPost: Healthy/)
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
