# EDGAR Alert Stock Scanner — MetaTrader 5

A **free** MT5 Expert Advisor that pulls the latest SEC insider-activity
signals from the [EDGAR Alert](https://www.edgaralert.com) API and shows
them in a simple on-chart table.

This is a **scanner / display tool only**.
It does **not** place trades, modify orders, or touch your account in
any way. It only reads data from the EDGAR Alert API and draws labels
on your chart. It's built and attached as an **Expert Advisor (EA)**,
not a custom indicator — that's a platform requirement, not a design
choice: MQL5's `WebRequest()` can only be called from an EA or a
script, never from an indicator (MT5 returns error 4014 if you try).

---

## What you need

1. A free EDGAR Alert account and API key — sign up at
   https://www.edgaralert.com
2. MetaTrader 5 (desktop)

---

## Installation

1. Open MetaTrader 5.
2. Go to **File → Open Data Folder**. This opens a Windows Explorer
   window.
3. Navigate to `MQL5 → Experts`.
4. Copy `EdgarAlertStockScanner.mq5` into that folder.
5. Back in MetaTrader 5, open the **Navigator** panel (Ctrl+N) if it's
   not already visible.
6. Right-click **Expert Advisors** in the Navigator and choose
   **Refresh** (or restart MT5).
7. You should now see `EdgarAlertStockScanner` listed under
   **Expert Advisors**.

---

## Required: allow WebRequest for the EDGAR Alert API

MT5 blocks all outbound web requests from Expert Advisors by default.
You must explicitly allow the EDGAR Alert API domain, or the scanner
will show:

> **Enable WebRequest for https://api.edgaralert.com in MT5 settings**

To allow it:

1. In MetaTrader 5, go to **Tools → Options**.
2. Click the **Expert Advisors** tab.
3. Check **Allow algorithmic trading** (required for any EA, including
   this one, even though it never trades).
4. Check **Allow WebRequest for listed URL:**.
5. Click **Add** (or click into the empty text box) and enter:

   ```
   https://api.edgaralert.com
   ```

6. Click **OK**.

If you changed the `ApiBaseUrl` input from the default, allow that
exact URL instead.

> **Note:** This setting lives in MT5 itself, not in the EA. If you
> reinstall MT5 or use a different terminal/profile, you'll need to
> repeat this step.

---

## Adding the scanner to a chart

1. Open any chart (the scanner is not tied to a specific symbol — it
   shows signals across tickers, not just the current chart's symbol).
2. In the Navigator, drag **EdgarAlertStockScanner** from
   **Expert Advisors** onto the chart.
3. In the settings dialog that appears, go to the **Inputs** tab and
   fill in:

   | Input            | Description                                   | Default                    |
   |-------------------|------------------------------------------------|-----------------------------|
   | `ApiKey`          | Your EDGAR Alert API key (**required**)        | *(empty)*                   |
   | `ApiBaseUrl`      | EDGAR Alert API base URL                       | `https://api.edgaralert.com`|
   | `RefreshSeconds`  | How often to re-fetch signals, in seconds      | `900` (15 minutes)          |
   | `MaxRows`         | Max number of signal rows to display (1–50)    | `10`                        |
   | `Scope`           | `All tickers (no filter)` or `Only my watchlist tickers` — see below | `All tickers (no filter)` |

4. Make sure the **Algo Trading** button in the MT5 toolbar is enabled
   (green) — MT5 requires this for any Expert Advisor to run, even one
   that, like this one, never places a trade.
5. Click **OK**. The scanner panel should appear in the top-left
   corner of the chart and refresh automatically.

---

## Filtering to specific tickers (Scope)

There's no separate "list of tickers" setting on this EA, because
that's not how the underlying API filters by ticker. Instead:

1. Log into [edgaralert.com](https://www.edgaralert.com) and build a
   watchlist under **Dashboard → Watchlist**, then set it as your
   account's **default** watchlist.
2. Set this EA's `Scope` input to **Only my watchlist tickers**.

Every alert this EA then shows is restricted to that list. If `Scope`
is set to watchlist mode but you haven't configured a default
watchlist on the website yet, the API returns **zero rows** — not
"everything" — so the scanner will show a status message telling you
to check your watchlist setup rather than silently looking like
nothing is happening.

---

## Sort order

Cards are sorted **bullish first**: signals with a recent insider buy
are shown above sell-only signals, and within each group, higher
scores sort first. EDGAR Alert's core edge is insider *buying* —
that's the cleaner, more actionable signal — so the list puts it in
front of you immediately.

## Reading a card

Each alert renders as a two-line card:

```
TPC   88 VERY STRONG          Large Buy vs History
Buy $1.2M · 2026-03-06        [Officer] [Cluster Buy]
```

| Part | Meaning |
|---|---|
| Ticker, Score, Signal | Same as before — stock ticker, EDGAR Alert signal score, and strength label (BUY / STRONG / VERY STRONG). |
| Headline | A short, readable description of the alert (e.g. "Large Buy vs History", "CFO Resigned"), built server-side from the event type — see the API's `summary.title` field. Falls back to a humanized version of the raw event type if the API response doesn't include a `summary` object. |
| Side, value, date | What *this specific alert* is — buy or sell, the dollar amount of *this* transaction (not a rollup), and the filing date. Management-change alerts (CEO/CFO/director appointments) have no dollar value, so this line just shows the action and date for those. |
| Badges | Small tags describing context — `Officer`/`Director`, `Discretionary`/`Scheduled (10b5-1)`, `RSU Vesting`/`ESPP`, `Cluster Buy`/`Cluster Sell`, or role/departure tags for management alerts. Comes from the API's `summary.badges` field; a card with no applicable tags simply shows no badges. |

This replaced an earlier 8-column grid layout (Ticker / Score / Signal
/ Last Buy / Buy Value / Last Sell / Cluster / Event all on one fixed-
width line). The card format exists because event descriptions are
real English phrases ("Large Sell vs History"), not short codes — they
need room to read as prose. It's also more compact for the common
case: most alerts have 0–2 badges, and a card's second line only takes
the space its own content needs, instead of reserving a wide fixed
column on every row whether or not that row needs it.

---

## Status messages

| Message                                                        | Meaning                                              |
|------------------------------------------------------------------|-------------------------------------------------------|
| `Enter EDGAR Alert API key`                                      | The `ApiKey` input is empty.                          |
| `Enable WebRequest for https://api.edgaralert.com in MT5 settings` | WebRequest is not allowed for this URL (see above).  |
| `No signals returned`                                            | The API call succeeded but returned zero signals (universe scope). |
| `No signals (check your default watchlist is set at edgaralert.com)` | Zero signals while `Scope` is set to watchlist — either a genuinely quiet watchlist, or no default watchlist configured yet. |
| `API error: ...`                                                 | The API call failed (bad key, rate limit, etc).      |

---

## Removing the scanner

Right-click the chart → **Expert list** → select
**EdgarAlertStockScanner** → **Remove**.

---

## Disclaimer

This tool displays informational signals derived from public SEC
filings. It is not investment advice, and EDGAR Alert is not a
brokerage, trading platform, or portfolio management system. Trading
decisions are entirely your own responsibility.

---

Powered by [EDGARAlert.com](https://www.edgaralert.com)
