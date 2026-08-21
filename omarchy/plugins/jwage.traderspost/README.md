# jwage.traderspost

TradersPost production health as one dot on the Omarchy bar, with an ops
cockpit behind it.

```
bar:   ●                        <- green / amber / red / grey, and nothing else

click:
┌────────────────────────────────────────────────────────┐
│ ● Healthy                                    just now  │
│   TradersPost production                               │
│                                                        │
│ TRADING EXECUTION · LAST 5 MIN                         │
│ Receive Webhook   164/min   11ms run   2ms wait ●      │
│ Outbox            164/min    7ms run   4ms wait ●      │
│ Handle Webhook    164/min   19ms run   4ms wait ●      │
│ Live Trades        29/min  317ms run   4ms wait ●      │
│ Paper Trades      114/min  157ms run   5ms wait ●      │
│                                                        │
│ APPLICATION TRAFFIC · LAST 5 MIN                       │
│ Web traffic       772/min  168ms run   2ms wait ●      │
│ Error rate                                   0.00%   ● │
│ Homepage check                                   0   ● │
│                                                        │
│ EXTERNAL SERVICES · 19 ACTIVE            (scrolls)     │
│ E*TRADE                          69/min      276ms     │
│ TradeStation auth                 2/min      180ms     │
│ IBKR                          1,028/min      155ms     │
│ …                                                      │
│                                                        │
│ r refresh · o New Relic                       ⟳  ⧉    │
└────────────────────────────────────────────────────────┘
```

The bar is a bare dot on purpose: at bar scale the colour is the whole message,
and a response time beside it was a number nobody acts on, changing every poll.
Hover for a one-line summary, click for the detail.

## The three sections

**1. Trading execution** is the path a trade actually travels, in travel order:

```
Receive Webhook  ->  Outbox  ->  Handle Webhook  ->  Live Trades
(HTTP front door)   (relay)     (queue worker)      Paper Trades
```

Reading down the section follows one webhook from the front door to a placed
order, so a stage backing up is located by *where it sits in the chain* rather
than by hunting for a number. **This list is never re-sorted** — not by latency,
not by severity. The sequence is the information.

Every stage reports the same three figures, in the same order: how fast it is
flowing, how long the work took (`run`), and how long it waited in the queue
(`wait`). Those last two fail differently and that is why both are here — a
healthy wait with a climbing run time is a slow broker; the reverse is a
backed-up queue. Only the wait is graded, because that is what New Relic pages
on. Watching the rates agree down the chain (172 / 172 / 172 above) is a free
sanity check that nothing is being dropped between stages.

Receive Webhook's wait is a **different kind of wait**: there is no message
queue in front of an HTTP request, so that figure is New Relic's
`queueDuration` — time between the request reaching Heroku's router and the app
picking it up, which is dyno saturation showing itself.

It is graded and dotted like every other row, but **on its own scale** — see
`WEB_QUEUE_*` below. Judging request queue time against the 1000ms the alert
policy uses for a *message* queue would call a genuine emergency healthy, so the
two kinds of wait never share a threshold. Each stage declares which scale it is
on (`waitScale`), and a test pins it: 5s of request queue time must not come out
critical.

**2. Application traffic** is what is true *around* the pipeline. Web traffic
gets the same row shape as a pipeline stage — rate, run, wait — because it is
the same kind of measurement, and the three figures only mean anything together;
as three separate rows they read like three unrelated facts. It covers
everything on HTTP **except** the webhook front door, which belongs to the
pipeline above. Excluding it matters: it is the highest-volume web transaction
by an order of magnitude and much faster than a page render, so averaged in
together each hid the other. Error rate and the synthetic homepage check sit
below it as plain rows, having nothing to say about rate or duration.

**3. External services** is every external host called in the window, slowest
first, under a friendly name — every host this app has called in the last 30 days
has one, and anything new shows its raw hostname until a label is added.
`api.thefuturesdesk.projectx.com` reads as "Futures Desk"; the 90-character AWS
PrivateLink endpoint reads as "AWS PrivateLink" rather than pushing every other
column off the panel. To refresh the list after adding an integration:

```sh
# every host called in the last 30 days, with whether it has a label
python3 - <<'EOF'
import importlib.util, json
from importlib.machinery import SourceFileLoader
l = SourceFileLoader("h", "traderspost-health")
h = importlib.util.module_from_spec(importlib.util.spec_from_loader("h", l)); l.exec_module(h)
key, acct = h.credentials()
q = ("SELECT count(apm.service.external.host.duration) FROM Metric WHERE appName = "
     f"'{h.APP_NAME}' FACET `external.host` SINCE 30 days ago LIMIT 200")
r = h.fetch(key, f'{{ actor {{ account(id: {acct}) {{ nrql(query: {json.dumps(q)}) {{ results }} }} }} }}')
for row in r["data"]["actor"]["account"]["nrql"]["results"]:
    host = str(row["external.host"])
    print(("ok  " if host in h.HOST_LABELS else "TODO"), host)
EOF
```

The list is not filtered to brokers: Stripe, SendGrid or Google auth going slow is an
ops signal too. Ungraded, because nothing in New Relic defines what "slow" means
for an external call and this widget does not invent thresholds — the ordering
does that work. The call rate sits beside each latency because it changes what
the latency means: 866ms on an endpoint taking 67 calls a minute is a different
problem from 866ms on an idle one.

Every figure is padded into a column and right-aligned, because these are
scanned *down* rather than read across: a ragged column makes you re-find the
decimal point on every row. The pipeline and the Web traffic row share one set
of columns even though they are separate sections, so the eye does not have to
re-anchor between them. The padding is done in `Model.js` (where the strings are
made, and where it can be tested) rather than with pixel widths in the QML, so
it adapts to whatever the numbers happen to be — `1,069/min` and `<1/min` land
in the same column without anyone picking a width. It assumes the panel font is
monospace, which is what Omarchy ships.

Only that last section grows with the data, so it is the only one that scrolls —
the panel stays a popup rather than a column reaching down the screen. The count
in its header ("19 ACTIVE") is what says there is more below the fold.

| File | What it is |
|---|---|
| `traderspost-health` | Fetches everything from New Relic NerdGraph in one request; prints JSON (`--json`) or a readable table. Runs standalone. |
| `HOST_LABELS` (in the helper) | Friendly names for external hosts — every one of the 37 seen in the last 30 days. Unlisted hosts fall back to their hostname, so a new dependency still appears the first time it is called; nothing is ever filtered out. |
| `Model.js` | Parsing, grading roll-up and number formatting. Qt-free so it can be tested under node. |
| `test-model.js` | `node test-model.js` — 26 checks over Model.js. |
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
| Elevated Live Queue Wait Time | > 1000ms for 300s | Live Trades (the wait) |
| Elevated Paper Queue Wait Time | > 1000ms for 300s | Paper Trades (the wait) |
| Elevated Webhook Queue Wait Time | > 1000ms for 300s | Handle Webhook (the wait) |
| TradersPost Synthetic Check Failure | > 3 failures | Homepage check |

"Homepage check" is New Relic's **TradersPost Homepage Monitor** — a Synthetics
ping of `https://traderspost.io` every minute from San Francisco, with TLS
validation on and a redirect counted as a failure. The row is the number of
FAILED checks in the window, so on a 1-minute period a healthy 5 minutes reads
`0` out of about 5 checks, and the alert's "> 3" is most of the window failing.
It is the one signal here that comes from outside the app looking in: APM can
look perfectly healthy while the site is unreachable.

Every query window is 5 minutes, matching the 300s those conditions use for
their critical terms, so a number going red here means what New Relic's own
evaluation would mean by it. **Change a threshold in New Relic and change
`QUEUE_WAIT_CRITICAL_MS` in `traderspost-health` to match** — they are two
copies of one decision, and the whole point of the widget is that its colours
agree with the pager.

Three gradings are the widget's own, because New Relic has no equivalent:

- **The amber tier.** Both alert terms fire at the same 1000ms and differ only
  in duration, so there is no "getting worse" signal to mirror. Amber is half
  the critical threshold, to give the dot something to say before the pager
  goes off.
- **Error rate.** No condition covers it, so: amber at 1%, red at 5%.
- **Request queue time** (`WEB_QUEUE_WARNING_MS` / `WEB_QUEUE_CRITICAL_MS`, 25ms
  and 100ms). Used by Receive Webhook and Web traffic. Nothing in New Relic
  covers it, so these are set against what this app actually does — about 2ms
  average and 2.4ms 95th percentile — making amber roughly a 10x rise and red a
  50x one.
  Like the outbox, this means the dot can go amber or red with nothing paging;
  adding a matching condition in New Relic is the way to close that gap.
- **The Outbox stage.** No condition covers the outbox either, and it is graded
  against the same 1000ms as the other queues. It is in because an outbox stall
  means accepted webhooks are not reaching the handlers at all — an incident
  whether or not New Relic pages for it. The cost is that the dot can go red
  with nothing paging. If the dot should mirror the pager and nothing else, set
  that stage's grade to `"info"` in `traderspost-health` (there is a comment on
  the loop that does it).

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
{ "id": "jwage.traderspost", "pollSeconds": 60 }
```

`pollSeconds` is clamped to 15–3600: below 15 it is burning NerdGraph quota
against a 5-minute query window, above an hour the widget is decoration.

## Scrolling the external list

Qt's built-in wheel step on a `Flickable` is a few pixels — about a third of a
row here — which made a 20-row list feel stuck. The section takes the wheel
event itself instead: `pixelDelta` where the device sends it (touchpads, and the
Magic Mouse through `magicmouse-scroll`'s virtual touchpad, so a fling still
reads as one continuous motion), and three rows per notch for a plain wheel.
A scrollbar shows on demand.

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
