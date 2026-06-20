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
| `ticker` | Ticker, shown once per card (not repeated inside the headline — see `summary.title` below) |
| `signalScore` | Score, and to compute the Signal label if one isn't provided |
| `eventType` | Falls back to a humanized headline if `summary` is absent on a row |
| `eventDate` | This alert's own date, shown in the card's detail line |
| `details.side`, `details.transactionValue` | This alert's own side (BUY/SELL) and dollar value — distinct from the ticker-wide rollup fields below, see "A note on..." |
| `clusterCount` | Parsed, currently unused in the card layout (kept on the row struct for a future enhancement) |
| `lastBuyDate`, `lastBuyValue`, `lastSellDate` | Parsed and used for sort priority (`RowRank`), currently not displayed directly on the card |
| `summary.title`, `summary.subtitle`, `summary.badges`, `summary.scoreBucket` | The card headline (ticker suffix stripped) and badge pills — see `AlertSummaryDto` in the V1 API repo. Falls back to a humanized `eventType` if `summary` is absent (older API response, or an alert type `AlertSummaryBuilder` doesn't cover yet). |

`lastBuyDate`, `lastBuyValue`, `lastSellDate`, `clusterCount`,
`details`, and `summary` are all confirmed live on the current API.
The scanner is still written defensively: any field that's missing or
`null` on a given row renders as `-` (or an empty badge list) rather
than breaking the EA. If you're consuming this same endpoint and want
the authoritative, current field list, always check the live API docs
rather than this repo — the docs are the source of truth, this repo
just consumes them.

### Filtering by ticker: the `scope` query parameter

There's no dedicated "list of tickers" request parameter on
`GET /api/v1/alerts/latest`. Ticker filtering works through the
existing `scope` parameter instead: `scope=watchlist` restricts
results to the account's **default watchlist**, which is configured
on the EDGAR Alert website (Dashboard → Watchlist → set as default),
not via this EA. The scanner's `Scope` input
(`SCOPE_UNIVERSE` / `SCOPE_WATCHLIST`) is a thin wrapper around that
same query parameter — see `BuildUrl()` in
`EdgarAlertStockScanner.mq5`.

One real footgun this surfaces: per the API's own
`WatchlistPredicate` logic (`AlertRepository.cs` in the V1 API repo),
`scope=watchlist` with no default watchlist configured matches
**nothing**, not everything. The scanner distinguishes this case in
its status message (`"check your default watchlist is set..."`)
rather than letting a misconfigured watchlist look identical to "no
recent signals".

### A note on "Last Buy" vs. "Last Sell" vs. this alert's own side

The `/alerts/latest` feed returns one row per detected event, each
tagged with its own `details.side` (BUY or SELL) and
`details.transactionValue` — what *this specific alert* is. Separately,
the API also returns `lastBuyDate`/`lastBuyValue`/`lastSellDate`
directly on every row: true **per-ticker rollups** computed
server-side, answering a different question ("what's this ticker's
broader recent history", which may be a different event than the one
this row represents).

The card's detail line ("Buy $1.2M · 2026-03-06") always uses the
per-alert `details.side`/`details.transactionValue`/`eventDate` —
never the rollup fields — since the card is describing what this one
alert is, not the ticker's broader pattern. The rollup fields are
still parsed and used for sort priority (bullish-first ordering
favors tickers with recent buy activity), just not displayed directly
on the card today.

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
   `MaxRows`, `Scope`.
4. Same card layout and bullish-first sort order: ticker/score/signal
   on line one with the alert's headline (from `summary.title`), this
   alert's own side/value/date with badge tags on line two. See "Reading
   a card" in `mt5/EdgarAlertStockScanner/README.md` for the exact
   shape. (This replaced an earlier 8-column grid layout — keep the
   NinjaTrader version aligned with whatever the MT5 version's current
   layout is at the time of the port, not necessarily this exact
   wording.)
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
