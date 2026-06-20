# MT5 Install — Quick Reference

Full details: [`../mt5/EdgarAlertStockScanner/README.md`](../mt5/EdgarAlertStockScanner/README.md)

This is an **Expert Advisor (EA)**, not a custom indicator — MQL5's
`WebRequest()` only works from an EA or script, never from an
indicator, so it has to be installed and attached as one.

## 5-minute setup

1. **Get an API key** at https://www.edgaralert.com (free).
2. **Copy the file:**
   `File → Open Data Folder → MQL5 → Experts`
   Place `EdgarAlertStockScanner.mq5` in that folder.
3. **Refresh the Navigator** (Ctrl+N → right-click Expert Advisors →
   Refresh).
4. **Allow algorithmic trading and WebRequest:**
   `Tools → Options → Expert Advisors`
   → check **Allow algorithmic trading**
   → check **Allow WebRequest for listed URL**
   → add `https://api.edgaralert.com`
5. **Drag the EA** from **Expert Advisors** onto any chart.
6. **Fill in inputs:**
   - `ApiKey` = your key (required)
   - `ApiBaseUrl` = `https://api.edgaralert.com` (default)
   - `RefreshSeconds` = `900` (default, 15 min)
   - `MaxRows` = `10` (default)
   - `Scope` = `All tickers (no filter)` (default), or `Only my watchlist tickers` to restrict to a watchlist you've set as default at edgaralert.com
7. Make sure the **Algo Trading** toolbar button is green/enabled.
8. Click **OK** — the signal panel should appear top-left on the
   chart.

## Common issues

| Symptom                                                          | Fix                                                                 |
|---------------------------------------------------------------------|------------------------------------------------------------------------|
| Error 4014 / "Function is not allowed for call" in the Experts log | The .mq5 was compiled/attached as an indicator instead of an EA. Re-copy it into `MQL5 → Experts` (not `MQL5 → Indicators`) and drag it from the **Expert Advisors** branch of the Navigator. |
| EA attaches but nothing happens, smiley face missing/red in corner | The **Algo Trading** toolbar button is off, or **Allow algorithmic trading** is unchecked in Tools → Options → Expert Advisors — both are required even though this EA never trades. |
| "Enter EDGAR Alert API key"                                       | Re-open EA properties → Inputs tab → fill in `ApiKey`.        |
| "Enable WebRequest for https://api.edgaralert.com in MT5 settings"| Repeat step 4 above. Must match `ApiBaseUrl` exactly, including `https://`. |
| "API error: invalid or unauthorized API key"                     | Double-check the key was copied correctly, no extra spaces.          |
| "No signals returned"                                              | Working correctly — there are simply no recent signals to show.      |
| "No signals (check your default watchlist is set...)"              | `Scope` is set to watchlist mode but no default watchlist is configured on edgaralert.com yet — the API returns zero rows in that case, not everything. Set a default watchlist on the website, or switch `Scope` back to "All tickers". |
| Panel doesn't update                                                | Check `RefreshSeconds`; the first load is immediate, later ones follow that interval. |

For the full card-layout reference, status-message list, and
disclaimer, see the platform README linked above.
