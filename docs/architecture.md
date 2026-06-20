# Architecture

This document explains how the EDGAR Alert Trading Tools (MT5 first,
NinjaTrader second) fit into the EDGAR Alert public API, what this
repo assumes about that API's contract, why TradingView and
Thinkorswim are out of scope for now, and the platform sequencing
(MT5 → NinjaTrader).

This repo is **client-only**. It does not contain, and will never
contain, any EDGAR Alert backend, database, or signal-generation code
— only plugins that call the public API documented at
[edgaralert.com/docs](https://www.edgaralert.com).

---

## 1. How this fits into the EDGAR Alert API

EDGAR Alert is API-first: every client — the website, AI agents, and
now trading-platform plugins — talks to the same public V1 REST API.
A trading-platform plugin is just another client of that API, exactly
like a browser-based dashboard would be, with no special access or
private endpoints.

Concretely, the MT5 scanner is a **read-only API consumer**:

- Authenticates with an `X-API-Key` header (the same header used by
  every other documented V1 endpoint).
- Calls `GET /api/v1/alerts/latest?limit=`, a publicly documented
  endpoint available on every plan, including FREE.
- Never writes anything back to EDGAR Alert. This repo contains no
  trading, order-placement, or account-modifying code of any kind —
  scanner/display only.

### Why this ships as an Expert Advisor, not a custom indicator

This is a hard MQL5 platform requirement, not a design preference.
`WebRequest()` — the only way to call an external REST API from MQL5
— can only be called from an Expert Advisor or a script. Calling it
from a custom indicator's `OnCalculate()` thread always fails with
error 4014 ("Function is not allowed for call"), regardless of
whether the URL is correctly allowlisted in
Tools → Options → Expert Advisors. See
[mql5.com/en/docs/network/webrequest](https://www.mql5.com/en/docs/network/webrequest).

The original MVP release was compiled with `#property
indicator_chart_window`, making it a custom indicator that called
`WebRequest()` — it would never have worked for anyone who actually
attached it to a chart. Fixed by converting to a proper EA: no
`indicator_*` properties, no `OnCalculate`, all logic driven by
`OnInit`/`OnTimer` like any EA without per-tick trading logic (an EA
does not require an `OnTick` handler — see
[MQL5's own docs on the Tick event](https://www.mql5.com/en/docs/basis/function/events),
which states explicitly that EAs can run entirely on `OnTimer`,
`OnBookEvent`, and `OnChartEvent` instead).

Practical implication: install this into `MQL5 → Experts` (not
`MQL5 → Indicators`), attach it the same way you'd attach any other
EA, and make sure **Allow algorithmic trading** is checked and the
**Algo Trading** toolbar button is enabled — both are required for
any EA to run at all, even one like this that never places a trade.
See `docs/mt5-install.md` for the full setup checklist.

### Response fields this scanner depends on

The scanner reads the following fields from the JSON array returned
by `GET /api/v1/alerts/latest` (see the full reference at
[edgaralert.com/docs/api/alerts](https://www.edgaralert.com)):

| Field | Used for |
|---|---|
| `ticker` | Ticker column |
| `signalScore` | Score column, and to compute the Signal label if one isn't provided |
| `eventType` | Event column |
| `eventDate` | Date used to populate Last Buy / Last Sell (see below) |
| `details.side` | Whether this event was a BUY or a SELL. Nested under `details` (not a top-level field) — added alongside the typed `details` object that replaced raw `messageJson` parsing. |
| `clusterCount` | Cluster column |
| `lastBuyDate`, `lastBuyValue`, `lastSellDate` | Last Buy / Buy Value / Last Sell columns, see below |

`lastBuyDate`, `lastBuyValue`, `lastSellDate`, and `clusterCount` are
confirmed live on the current API — added specifically for
trading-platform scanners like this one (per-ticker rollups, so a
single row can report a ticker's most recent buy and sell even though
the row itself only represents one event). The scanner is still
written defensively: any field that's missing or `null` on a given
row (a ticker with no buy history, for example) renders as `-` in the
table rather than breaking the plugin. If you're consuming this same
endpoint and want the authoritative, current field list, always check
the live API docs rather than this repo — the docs are the source of
truth, this repo just consumes them.

### A note on "Last Buy" vs. "Last Sell"

The `/alerts/latest` feed returns one row per detected event, each
tagged with a `side` (BUY or SELL) — it is not pre-aggregated per
ticker on its own. The API now also returns `lastBuyDate`,
`lastBuyValue`, and `lastSellDate` directly on every row — true
per-ticker rollups computed server-side — and the scanner prefers
those whenever present. The per-row `side` + `eventDate` inference
described below only kicks in as a fallback when a rollup field is
genuinely absent (e.g. a ticker with no sell history at all has a
`null` `lastSellDate`, which is a different case from the rollup
being unavailable).

When the fallback does apply: the scanner reads that row's own
`details.side` and `eventDate` and populates whichever of Last Buy /
Last Sell matches that row, leaving the other blank for that row —
see the field fallback chain in `EdgarAlertStockScanner.mq5`'s JSON
parser.

### Sort order: bullish-first

Rows are sorted with BUY-side signals above SELL-only rows, and
within each group, higher scores first. EDGAR Alert's core edge is
insider *buying* — that's the cleaner, more actionable signal — so
the table surfaces it first by default.

### Why "Last Sell" is shown but not "Sell Value"

If a ticker has a strong score, the natural next question is "are
insiders also selling?" — Last Sell answers that at a glance. But
insider sells are a noisy signal on their own (tax planning, RSU
vesting, scheduled 10b5-1 plans, diversification all show up as
"sells" with no negative read-through), so this MVP doesn't dedicate
a column to sizing them the way it does for buys.

### Possible future API needs

If a future version of this scanner adds ticker-list/watchlist
management (so a plugin could add or remove tickers from a user's
EDGAR Alert watchlist directly), that would require an API-key-
authenticated watchlist endpoint. As of this writing, watchlist
management is only available through the logged-in website, not the
public API — if you need this, check the current API docs or contact
EDGAR Alert, since this may have changed since this doc was written.

---

## 2. Why TradingView / Thinkorswim are excluded for live API plugins

- **TradingView**: Pine Script has no general-purpose outbound HTTP
  capability for arbitrary REST APIs from indicators/strategies, the
  way MQL5's `WebRequest` (called from an Expert Advisor or script —
  it's blocked from indicators too, see Section 1) or NinjaScript's
  `HttpClient` do. Pulling data from an external authenticated API
  like EDGAR Alert isn't a supported pattern for a standard Pine
  Script indicator without a separate relay/webhook service —
  disproportionate effort for a free MVP tool.
- **Thinkorswim (thinkScript)**: similarly, thinkScript doesn't
  support arbitrary outbound HTTP calls to third-party REST APIs from
  custom studies, so there's no first-class way to call a
  `X-API-Key`-authenticated endpoint from inside a thinkScript study.

Both platforms are reasonable candidates for a **different**
integration shape later (e.g. a webhook-based workflow that pushes
*into* EDGAR Alert rather than pulling *from* it), but that's a
different architecture than "live API-key plugin with a refreshing
on-chart table," so it's out of scope for this repo.

---

## 3. Why MT5 is first for marketplace reach

- MT5 has a very large installed base among retail forex/CFD/
  multi-asset traders, and many brokers offer it with stock CFDs,
  making an insider-signal scanner directly relevant to traders
  already on the platform.
- MQL5 has native, well-documented `WebRequest()` support for calling
  external REST APIs with custom headers — a direct match for
  `X-API-Key` auth, with no relay service needed.
- MT5's chart-object model (`OBJ_LABEL` etc.) is simple enough to
  build a readable table MVP quickly, matching the "don't
  over-engineer the UI" goal for a first version.
- The MQL5 Market / community is a low-friction free-distribution
  channel for a free lead-gen tool whose job is to get more people
  trying EDGAR Alert.

## 4. Why NinjaTrader is second for a higher-quality stock/futures audience

- NinjaTrader's user base skews toward more serious U.S. equities and
  futures traders — a stronger fit for SEC insider-activity signals
  than MT5's heavier forex/CFD skew.
- NinjaScript (C#) is a strictly more capable environment than MQL5
  for this kind of plugin: full `HttpClient`, proper JSON
  deserialization, and richer native UI controls (WPF-based panels
  instead of hand-placed chart labels), so the quality ceiling for a
  polished scanner is much higher.
- Going second lets the NinjaTrader build reuse a contract
  (`/api/v1/alerts/latest`, `X-API-Key`, the same field names) that's
  already been validated against real users on MT5 first, rather than
  designing the integration twice in parallel.

## 5. Future plan to port the same API contract to NinjaTrader

The NinjaTrader version is intentionally scoped to be a **UI port,
not a new integration design**:

1. Same authentication: `X-API-Key` header.
2. Same endpoint: `GET /api/v1/alerts/latest?limit=` (plus whatever
   additional documented fields exist by the time this is built —
   always check the current API docs).
3. Same user inputs: `ApiKey`, `ApiBaseUrl`, `RefreshSeconds`,
   `MaxRows`.
4. Same columns, same bullish-first sort order: Ticker, Score, Signal,
   Last Buy, Buy Value, Last Sell, Cluster, Event.
5. Same constraint: scanner/display only, never order placement. This
   is a hard rule for this repo, not just an MVP shortcut — EDGAR
   Alert is a research/signal platform, not a trading or brokerage
   platform, and these plugins will never place trades.

The only things that change between platforms are platform-native
concerns: NinjaScript's `Indicator`/`AddOn` lifecycle instead of
MQL5's `OnInit`/`OnTimer`, `HttpClient` + JSON deserialization instead
of `WebRequest` + the hand-rolled MQL5 JSON parser, and a proper WPF
panel instead of `OBJ_LABEL` chart objects. Keeping the API contract
identical across both platforms means any future API change benefits
both plugins, instead of two separate integration efforts drifting
apart.
