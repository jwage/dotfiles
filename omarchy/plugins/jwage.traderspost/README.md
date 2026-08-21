# jwage.traderspost

TradersPost production health as one dot on the Omarchy bar, with an ops
cockpit behind it.

```
bar:   ● 101ms                    <- green / amber / red / grey, + web response time

click:
┌────────────────────────────────────────────┐
│ ● Healthy                        just now  │
│   TradersPost production                   │
│                                            │
│ ALERTS ON THESE                            │
│ Live queue wait                    5ms  ●  │
│ Paper queue wait                   6ms  ●  │
│ Webhook queue wait                 4ms  ●  │
│ Error rate                       0.00%  ●  │
│ Homepage check                       0  ●  │
│                                            │
│ TRAFFIC · LAST 5 MIN                       │
│ Web throughput                 1,114/min   │
│ Web response                       101ms   │
│ Webhooks (5m)                      1,970   │
│ Trades (5m)                        1,591   │
│ Slowest API      api.binance.com   589ms   │
│                                            │
│ r refresh · o New Relic            ⟳  ⧉   │
└────────────────────────────────────────────┘
```

| File | What it is |
|---|---|
| `traderspost-health` | Fetches everything from New Relic NerdGraph in one request; prints JSON (`--json`) or a readable table. Runs standalone. |
| `Model.js` | Parsing, grading roll-up and number formatting. Qt-free so it can be tested under node. |
| `test-model.js` | `node test-model.js` — 14 checks over Model.js. |
| `BarWidget.qml` | The bar dot. Owns the poll timer, holds the last good payload. |
| `Panel.qml` | The cockpit popup. Renders what BarWidget already fetched. |

## Gestures

| Input | Does |
|---|---|
| Left click | Open/close the cockpit |
| Middle click | Force a refresh |
| Right click | Send the one-line summary as a notification |
| `r` (panel open) | Refresh |
| `o` (panel open) | Open New Relic in the browser |
| `Esc` | Close |

Also driveable over IPC, which is what makes it scriptable and testable:

```sh
omarchy-shell jwage.traderspost status     # one-line summary, no UI needed
omarchy-shell jwage.traderspost open|close|toggle|refresh
```

## Where the thresholds come from

Nothing here invents a threshold. Account 6271700 has one alert policy,
**TradersPost Policy**, and its four conditions *are* the definition of
unhealthy used by the widget:

| Condition | Threshold | Shown as |
|---|---|---|
| Elevated Live Queue Wait Time | > 1000ms for 300s | Live queue wait |
| Elevated Paper Queue Wait Time | > 1000ms for 300s | Paper queue wait |
| Elevated Webhook Queue Wait Time | > 1000ms for 300s | Webhook queue wait |
| TradersPost Synthetic Check Failure | > 3 failures | Homepage check |

Every query window is 5 minutes, matching the 300s those conditions use for
their critical terms, so a number going red here means what New Relic's own
evaluation would mean by it. **Change a threshold in New Relic and change
`QUEUE_WAIT_CRITICAL_MS` in `traderspost-health` to match** — they are two
copies of one decision, and the whole point of the widget is that its colours
agree with the pager.

Two gradings are the widget's own, because New Relic has no equivalent:

- **The amber tier.** Both alert terms fire at the same 1000ms and differ only
  in duration, so there is no "getting worse" signal to mirror. Amber is half
  the critical threshold, to give the dot something to say before the pager
  goes off.
- **Error rate.** No condition covers it, so: amber at 1%, red at 5%.

An open New Relic issue outranks every raw number: if something is actually
paging, the dot is red regardless of how the last 5 minutes look.

## Colour

Critical uses the theme's own `Color.urgent`, so the loudest state always
matches the desktop. Amber and green are fixed, desaturated values — the
Omarchy palette has no green or amber to borrow, and traffic-light semantics
are the entire point of an ops widget. Grey is `Color.muted` and means *the
number on screen is not current*, which is a different statement from healthy.

## Staleness

Last good data stays on screen through a failed poll — a stale number labelled
stale beats an empty panel. After three missed polls the dot goes grey, the age
in the panel header turns amber, and the reason for the failure prints under the
verdict. The bar keeps a dot in every failure mode; the widget never silently
disappears from the bar.

## The API key

`traderspost-health` reads `NEW_RELIC_MCP_API_KEY` and `NEW_RELIC_ACCOUNT_ID`
from the environment when the session has them (UWSM sources
`~/.config/mcp-secrets.env`), and parses that file directly otherwise, which is
what makes it work from a plain terminal. The key is never passed as an
argument — it would be visible in `ps` to every user on the box — and
`~/.config/mcp-secrets.env` is deliberately not tracked in this repo. A new
machine needs that file before the widget shows anything but grey.

## Settings

In `shell.json`, on the widget's own layout entry:

```json
{ "id": "jwage.traderspost", "pollSeconds": 60, "showLatency": true }
```

`pollSeconds` is clamped to 15–3600: below 15 it is burning NerdGraph quota
against a 5-minute query window, above an hour the widget is decoration.
`showLatency` drops the response time and leaves a bare dot. Vertical bars
always get the bare dot — there is no room for a number.

## Editing it

QML in a running shell is cached per URL, and these files reach the shell as
symlinks into this repo. Rewriting a file gives it a new inode, which the
shell's watcher does not notice, and **neither a save nor
`omarchy-shell shell rescanPlugins` picks the change up** — both were tried.
Use:

```sh
omarchy restart shell
```

`traderspost-health` has no such problem: the widget shells out to it per poll,
so an edit lands on the next tick. Run it directly while iterating.
