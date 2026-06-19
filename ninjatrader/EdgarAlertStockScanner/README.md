# EDGAR Alert Stock Scanner — NinjaTrader (Planned)

This folder is reserved for the NinjaTrader port of the
EDGAR Alert Stock Scanner.

**Status: not yet implemented.**

NinjaTrader is the planned **second platform**, after MT5, for the
EDGAR Alert scanner. See `../../docs/architecture.md` for the
reasoning behind that sequencing and the plan to reuse the same
EDGAR Alert V1 API contract that the MT5 version uses.

## Planned scope (mirrors the MT5 MVP)

- NinjaScript indicator (C#) that calls the EDGAR Alert
  `GET /api/v1/alerts/latest` endpoint (or whatever V1 endpoint the
  scanner has standardized on by that point — see architecture.md).
- Same required user inputs: `ApiKey`, `ApiBaseUrl`, `RefreshSeconds`,
  `MaxRows`.
- Same display columns and bullish-first sort order: Ticker, Score,
  Signal, Last Buy, Buy Value, Last Sell, Cluster, Event.
- Same constraint: scanner/display only, no order placement.
- Distributed as a free NinjaTrader add-on (`.zip` import via
  NinjaTrader's Control Center → Tools → Import).

## Why this isn't built yet

The MT5 version ships first to validate the API contract, the
authentication flow (`X-API-Key` header), refresh/polling behavior,
and the display format with real users on a platform with broader
retail reach. Once that's proven, the same contract gets ported here
with platform-appropriate UI (a NinjaScript `Indicator` or `AddOn`
panel instead of chart-object labels).

No code should be added to this folder until the MT5 version is
stable and the V1 API additions described in `architecture.md` (if
any) have shipped.
