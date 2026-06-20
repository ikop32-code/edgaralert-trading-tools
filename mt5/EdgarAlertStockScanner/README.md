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

4. Make sure the **Algo Trading** button in the MT5 toolbar is enabled
   (green) — MT5 requires this for any Expert Advisor to run, even one
   that, like this one, never places a trade.
5. Click **OK**. The scanner table should appear in the top-left
   corner of the chart and refresh automatically.

---

## Sort order

Rows are sorted **bullish first**: signals with a recent insider buy
are shown above sell-only rows, and within each group, higher scores
sort first. EDGAR Alert's core edge is insider *buying* — that's the
cleaner, more actionable signal — so the table is ordered to put it
in front of you immediately.

## Table columns

| Column      | Meaning                                                  |
|-------------|---------------------------------------------------------|
| Ticker      | Stock ticker symbol                                       |
| Score       | EDGAR Alert signal score                                   |
| Signal      | Signal strength label (e.g. BUY, STRONG, VERY STRONG)      |
| Last Buy    | Date of the most recent insider buy, if any                |
| Buy Value   | Dollar value of the most recent insider buy, if provided   |
| Last Sell   | Date of the most recent insider sell, if any                |
| Cluster     | Cluster-buying indicator, if provided by the API             |
| Event       | SEC filing/event type (e.g. Form 4)                          |

**Why Last Sell is shown but not Sell Value:** if a ticker has a good
score, the natural next question is "are insiders also selling?" —
so Last Sell answers that at a glance. But insider sells are a noisy
signal on their own (tax planning, RSU vesting, scheduled 10b5-1
plans, diversification all show up as "sells" with no negative
read-through), so the MVP intentionally doesn't dedicate a column to
sizing them. Insider buys are the cleaner signal and get the full
treatment (date *and* dollar value).

> Last Buy, Buy Value, Last Sell, and Cluster come from rollup fields
> the API computes per ticker (`lastBuyDate`, `lastBuyValue`,
> `lastSellDate`, `clusterCount`) — confirmed live and read correctly
> by the scanner. If a ticker has no buy or sell history at all, the
> corresponding field is `null` on the API response and the scanner
> shows `-` for that cell rather than a fabricated value.

---

## Status messages

| Message                                                        | Meaning                                              |
|------------------------------------------------------------------|-------------------------------------------------------|
| `Enter EDGAR Alert API key`                                      | The `ApiKey` input is empty.                          |
| `Enable WebRequest for https://api.edgaralert.com in MT5 settings` | WebRequest is not allowed for this URL (see above).  |
| `No signals returned`                                            | The API call succeeded but returned zero signals.    |
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
