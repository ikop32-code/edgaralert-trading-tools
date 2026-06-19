# MT5 Install — Quick Reference

Full details: [`../mt5/EdgarAlertStockScanner/README.md`](../mt5/EdgarAlertStockScanner/README.md)

## 5-minute setup

1. **Get an API key** at https://www.edgaralert.com (free).
2. **Copy the file:**
   `File → Open Data Folder → MQL5 → Indicators`
   Place `EdgarAlertStockScanner.mq5` in that folder.
3. **Refresh the Navigator** (Ctrl+N → right-click Indicators →
   Refresh).
4. **Allow WebRequest:**
   `Tools → Options → Expert Advisors`
   → check **Allow WebRequest for listed URL**
   → add `https://api.edgaralert.com`
5. **Drag the indicator** onto any chart.
6. **Fill in inputs:**
   - `ApiKey` = your key (required)
   - `ApiBaseUrl` = `https://api.edgaralert.com` (default)
   - `RefreshSeconds` = `900` (default, 15 min)
   - `MaxRows` = `10` (default)
7. Click **OK** — the signal table should appear top-left on the
   chart.

## Common issues

| Symptom                                                          | Fix                                                                 |
|---------------------------------------------------------------------|------------------------------------------------------------------------|
| "Enter EDGAR Alert API key"                                       | Re-open indicator properties → Inputs tab → fill in `ApiKey`.        |
| "Enable WebRequest for https://api.edgaralert.com in MT5 settings"| Repeat step 4 above. Must match `ApiBaseUrl` exactly, including `https://`. |
| "API error: invalid or unauthorized API key"                     | Double-check the key was copied correctly, no extra spaces.          |
| "No signals returned"                                              | Working correctly — there are simply no recent signals to show.      |
| Table doesn't update                                                | Check `RefreshSeconds`; the first load is immediate, later ones follow that interval. |

For the full table-column reference, status-message list, and
disclaimer, see the platform README linked above.
