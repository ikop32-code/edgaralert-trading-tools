//+------------------------------------------------------------------+
//|                                    EdgarAlertStockScanner.mq5    |
//|                                          Powered by EDGARAlert.com|
//+------------------------------------------------------------------+
//|
//| EDGAR Alert Stock Scanner (MT5 Expert Advisor)
//|
//| FREE scanner / display tool. Pulls the latest insider-activity
//| signals from the EDGAR Alert API and shows them in a simple
//| on-chart table.
//|
//| This is an Expert Advisor, not a custom indicator -- that's a
//| hard requirement, not a style choice. WebRequest() can only be
//| called from an EA or a script in MQL5; calling it from an
//| indicator's OnCalculate() thread always fails with error 4014
//| ("Function is not allowed for call"), even with the URL correctly
//| allowlisted in Tools -> Options -> Expert Advisors. See
//| mql5.com/en/docs/network/webrequest. This file was originally
//| compiled as an indicator (#property indicator_chart_window) with
//| WebRequest already in it, which would never have worked for
//| anyone who actually attached it to a chart -- fixed by converting
//| to a proper EA: no indicator_* properties, no OnCalculate, polling
//| happens on a timer via OnInit/OnTimer like any other EA without
//| per-tick trading logic.
//|
//| This EA does NOT place trades, modify orders, or touch the
//| account in any way. It only reads data and draws labels.
//|
//| API endpoint used:
//|   GET {ApiBaseUrl}/api/v1/alerts/latest?limit={MaxRows}
//|   Header: X-API-Key: {ApiKey}
//|
//| Before using, you must:
//|   1. Get a free API key at https://www.edgaralert.com
//|   2. Allow WebRequest for your ApiBaseUrl in
//|      MT5 -> Tools -> Options -> Expert Advisors
//|      (see README.md for exact steps)
//|   3. Attach this to a chart the same way you'd attach any EA
//|      (drag from Navigator -> Expert Advisors, not from
//|      Navigator -> Indicators -> Custom)
//|
//+------------------------------------------------------------------+
#property copyright "EDGARAlert.com"
#property link      "https://www.edgaralert.com"
#property version   "1.00"
#property strict

//--- Scope filter -------------------------------------------------------
// Mirrors the API's own scope=watchlist|universe query parameter (see
// GET /api/v1/alerts/latest in the V1 API repo). This is how ticker
// filtering actually works on this endpoint today -- there is no
// separate "list of tickers" request parameter; instead, you build a
// watchlist on the EDGAR Alert website (Dashboard -> Watchlist) and set
// it as your account's default, then pass scope=watchlist here to
// restrict every alert this EA shows to just that list.
enum ENUM_ALERT_SCOPE
{
   SCOPE_UNIVERSE,   // All tickers (no filter)
   SCOPE_WATCHLIST   // Only my watchlist tickers
};

//--- Inputs -----------------------------------------------------------
input string         ApiKey         = "";                              // EDGAR Alert API key (required)
input string         ApiBaseUrl     = "https://api.edgaralert.com";     // API base URL
input int            RefreshSeconds = 900;                              // Refresh interval (seconds)
input int            MaxRows        = 10;                               // Max rows to display (1-50)
input ENUM_ALERT_SCOPE Scope        = SCOPE_UNIVERSE;                   // Ticker filter -- Watchlist requires a default watchlist set on edgaralert.com first

//--- Constants ----------------------------------------------------------
#define EA_PREFIX        "EAS_"          // prefix for every chart object we create, for clean cleanup
#define EA_TITLE         "EDGAR Alert Stock Scanner"
#define EA_FOOTER        "Powered by EDGARAlert.com"
#define HEADER_Y         48
#define STATUS_LINE_HEIGHT 18  // single text-line spacing, used for the
                                // title/status/footer chrome -- separate
                                // from CARD_HEIGHT below, which is sized
                                // for an actual two-line data row, not
                                // a single status/footer line
#define PANEL_X          12
#define FONT_NAME        "Consolas"
#define FONT_SIZE_HEADER 10
#define FONT_SIZE_ROW    9
#define FONT_SIZE_TITLE  11
#define FONT_SIZE_STATUS 9

// Panel backing rectangle, so the table is readable over candles instead
// of floating directly on the chart with no backing.
#define PANEL_WIDTH      550
#define PANEL_BG_COLOR   C'10,10,10'      // near-black, distinct from pure chart black
#define PANEL_BORDER_COLOR clrDimGray

// ── Card row layout ─────────────────────────────────────────────────
// Replaced the original 8-column grid (Ticker/Score/Signal/Last Buy/
// Buy Value/Last Sell/Cluster/Event all crammed into fixed-width cells
// on one line) with a two-line card per alert:
//   Line 1: TICKER  SCORE SIGNAL                 <headline, bold>
//   Line 2: side $value · date                    [badge] [badge] ...
// This exists because summary.title strings ("Large Sell vs History")
// are English phrases, not abbreviated codes -- they need room to read
// as prose, not be squeezed into a fixed grid cell next to numbers. A
// card is also what actually saves vertical space for the common case
// (most alerts have 0-2 badges): the old grid forced a wide Event
// column on every single row whether or not that row needed it, while
// a card's second line only takes the room its own content needs.
#define CARD_HEIGHT      50    // total height per card, including the
                                // 8px gap to the next card
#define CARD_GAP         8
#define CARD_LINE1_Y     6     // y offset of line 1, relative to card top
#define CARD_LINE2_Y     24    // y offset of line 2, relative to card top
#define CARD_BADGE_Y     22    // y offset of the badge row, relative to card top
#define CARD_LEFT_W      130   // width reserved for the ticker/score/signal
                                // block before the headline starts
#define BADGE_HEIGHT     14
#define BADGE_PAD_X      8     // horizontal padding inside each badge pill
#define BADGE_GAP        6     // horizontal gap between badges
#define BADGE_FONT_SIZE  8

//--- State ---------------------------------------------------------------
datetime g_lastRefresh   = 0;
bool     g_firstRunDone  = false;
string   g_statusMessage = "";
color    g_statusColor   = clrSilver;

//+------------------------------------------------------------------+
//| One parsed signal row                                            |
//+------------------------------------------------------------------+
struct SignalRow
{
   string ticker;
   string score;
   string signal;
   string lastBuy;
   string buyValue;
   string lastSell;
   string cluster;
   string eventType;

   // This alert's OWN transaction, from details.side / details.
   // transactionValue (see AlertDetailsDto in the V1 API repo) -- NOT
   // the same as lastBuy/buyValue/lastSell above, which are the
   // ticker-wide rollup (this ticker's most recent buy/sell across all
   // insiders, possibly a different event entirely). The card's second
   // line describes what THIS alert is, so it needs the per-alert
   // values, not the rollup. ownValue is already FormatCompactValue'd.
   string ownSide;
   string ownValue;
   string ownDate;

   // From the row's nested "summary" object (see AlertSummaryDto in the
   // V1 API repo). headline has the " \u2014 TICKER" suffix stripped --
   // the ticker is already its own field/shown separately in the card
   // layout, so repeating it inside the headline read as redundant.
   // Falls back to a humanized eventType if summary/title is absent
   // (older API response, or this alert type predates Summary support).
   string headline;
   string subtitle;
   string scoreBucket;
   string badges[];
};

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   ChartSetInteger(0, CHART_EVENT_OBJECT_CREATE, false);
   ChartSetInteger(0, CHART_EVENT_OBJECT_DELETE, false);

   if(MaxRowsClamped() != MaxRows)
      Print("EdgarAlertStockScanner: MaxRows clamped to ", MaxRowsClamped());

   DrawStaticChrome();

   if(StringLen(ApiKey) == 0)
   {
      SetStatus("Enter EDGAR Alert API key", clrOrangeRed);
      DrawStatusOnly();
      // Still set a timer so the panel updates instantly if the user
      // edits inputs and reloads, but we won't call the API with no key.
      EventSetTimer(5);
      return(INIT_SUCCEEDED);
   }

   // Kick off an immediate fetch, then refresh on a timer.
   EventSetTimer(MathMax(5, RefreshSeconds));
   RefreshSignals();

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, EA_PREFIX);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Timer handler - periodic refresh                                 |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(StringLen(ApiKey) == 0)
   {
      SetStatus("Enter EDGAR Alert API key", clrOrangeRed);
      DrawStatusOnly();
      return;
   }
   RefreshSignals();
}

//+------------------------------------------------------------------+
//| Returns MaxRows clamped to a sane range                          |
//+------------------------------------------------------------------+
int MaxRowsClamped()
{
   int v = MaxRows;
   if(v < 1)  v = 1;
   if(v > 50) v = 50;
   return v;
}

//+------------------------------------------------------------------+
//| Pull latest signals from the API and redraw the table            |
//+------------------------------------------------------------------+
void RefreshSignals()
{
   string url = BuildUrl();

   string headers = "X-API-Key: " + ApiKey + "\r\n";
   char   post[];
   char   result[];
   string resultHeaders;

   ResetLastError();
   int timeout = 8000; // ms
   int res = WebRequest("GET", url, headers, timeout, post, result, resultHeaders);

   if(res == -1)
   {
      int err = GetLastError();
      if(err == 4060)
      {
         SetStatus("Enable WebRequest for " + ApiBaseUrl + " in MT5 settings", clrOrangeRed);
      }
      else
      {
         SetStatus("API error: WebRequest failed (error " + IntegerToString(err) + ")", clrOrangeRed);
      }
      DrawStatusOnly();
      return;
   }

   string body = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);

   if(res == 401 || res == 403)
   {
      SetStatus("API error: invalid or unauthorized API key (HTTP " + IntegerToString(res) + ")", clrOrangeRed);
      DrawStatusOnly();
      return;
   }
   if(res == 429)
   {
      SetStatus("API error: rate limit exceeded, try again later", clrOrangeRed);
      DrawStatusOnly();
      return;
   }
   if(res != 200)
   {
      SetStatus("API error: HTTP " + IntegerToString(res), clrOrangeRed);
      DrawStatusOnly();
      return;
   }

   SignalRow rows[];
   string parseError = "";
   if(!ParseSignals(body, rows, parseError))
   {
      SetStatus("API error: " + parseError, clrOrangeRed);
      DrawStatusOnly();
      return;
   }

   if(ArraySize(rows) == 0)
   {
      if(Scope == SCOPE_WATCHLIST)
      {
         // scope=watchlist matches NOTHING if the account has no default
         // watchlist configured (see WatchlistPredicate in the V1 API
         // repo's AlertRepository: "No default list configured -> matches
         // nothing, never everything"). Zero rows here is ambiguous --
         // could be a genuinely quiet watchlist, or a watchlist that was
         // never set up -- so say so rather than letting it look
         // identical to "nothing happening right now".
         SetStatus("No signals (check your default watchlist is set at edgaralert.com)", clrOrange);
      }
      else
      {
         SetStatus("No signals returned", clrSilver);
      }
      DrawTable(rows); // draws header + footer + "no signals" status, no data rows
      g_lastRefresh = TimeLocal();
      return;
   }

   SetStatus("Updated " + TimeToString(TimeLocal(), TIME_DATE | TIME_MINUTES) +
              "  (" + IntegerToString(ArraySize(rows)) + " signals)", clrLimeGreen);
   DrawTable(rows);
   g_lastRefresh = TimeLocal();
}

//+------------------------------------------------------------------+
//| Build the request URL                                            |
//+------------------------------------------------------------------+
string BuildUrl()
{
   string base = ApiBaseUrl;
   // Strip a trailing slash if the user included one.
   int len = StringLen(base);
   if(len > 0 && StringSubstr(base, len - 1, 1) == "/")
      base = StringSubstr(base, 0, len - 1);

   string url = base + "/api/v1/alerts/latest?limit=" + IntegerToString(MaxRowsClamped());

   // scope=watchlist restricts results to the account's default
   // watchlist (see GET /api/v1/alerts/latest's scope param in the V1
   // API repo). Omitted entirely for SCOPE_UNIVERSE rather than sending
   // scope=universe explicitly -- both behave identically server-side
   // (the API's own WatchlistPredicate treats "anything other than
   // watchlist" as no restriction), so there's no functional reason to
   // add a redundant query parameter to every request.
   if(Scope == SCOPE_WATCHLIST)
      url += "&scope=watchlist";

   return url;
}

//+------------------------------------------------------------------+
//| Minimal JSON array-of-objects parser for the alerts/latest shape |
//| Tolerant by design: missing fields just render as "-".           |
//| Not a general-purpose JSON parser; built for this one endpoint.  |
//+------------------------------------------------------------------+
bool ParseSignals(const string &json, SignalRow &rows[], string &errorOut)
{
   string s = json;
   StringTrimLeft(s);
   StringTrimRight(s);

   if(StringLen(s) == 0)
   {
      errorOut = "empty response body";
      return false;
   }

   // The API may wrap the array in an object, e.g. {"data":[...]} or
   // {"message":"..."} for the "no rows" case. Handle both shapes:
   // 1) a bare JSON array: [ {...}, {...} ]
   // 2) an object with a top-level array value (first array found)
   int arrStart = StringFind(s, "[");
   int arrEnd   = StringFindLastBracket(s, "]");

   if(arrStart == -1 || arrEnd == -1 || arrEnd < arrStart)
   {
      // No array present at all -- check for a known "message" field
      // (e.g. {"message":"No weekly data available yet."}) and treat
      // that as zero rows rather than an error, since that pattern is
      // used elsewhere in this API for empty results.
      if(StringFind(s, "\"message\"") >= 0)
      {
         ArrayResize(rows, 0);
         return true;
      }
      errorOut = "unrecognized response format";
      return false;
   }

   string arrBody = StringSubstr(s, arrStart + 1, arrEnd - arrStart - 1);
   StringTrimLeft(arrBody);
   StringTrimRight(arrBody);

   if(StringLen(arrBody) == 0)
   {
      ArrayResize(rows, 0);
      return true; // valid empty array
   }

   // Split into top-level objects by tracking brace depth so that
   // nested objects/arrays (e.g. message_json blobs) don't break the split.
   string objects[];
   int objCount = SplitTopLevelObjects(arrBody, objects);

   if(objCount <= 0)
   {
      errorOut = "could not parse signal objects";
      return false;
   }

   ArrayResize(rows, objCount);
   for(int i = 0; i < objCount; i++)
   {
      SignalRow r;

      // NOTE on this whole block: MQL5 reference parameters (the
      // "const string &key" / "const string &defaultVal" params on
      // JsonGetString/JsonGetNumberAsString/ShortenDate) can only bind to
      // an actual variable, never directly to the return value of another
      // function call -- "parameter passed as reference, variable
      // expected" is the compiler telling you exactly that. Every
      // fallback chain below is written as a flat sequence of named
      // variables for that reason: compute the innermost/deepest fallback
      // first, store it, then use that variable (never the call
      // expression itself) as the defaultVal one level up.

      string tickerFallback = JsonGetString(objects[i], "ticker", "-");
      r.ticker = JsonGetString(objects[i], "Ticker", tickerFallback);

      string scoreFallback2 = JsonGetNumberAsString(objects[i], "score", "-");
      string scoreFallback1 = JsonGetNumberAsString(objects[i], "signalScore", scoreFallback2);
      r.score = JsonGetNumberAsString(objects[i], "SignalScore", scoreFallback1);

      string signalFallback2 = ScoreToSignalLabel(r.score);
      string signalFallback1 = JsonGetString(objects[i], "signal", signalFallback2);
      r.signal = JsonGetString(objects[i], "Signal", signalFallback1);

      string eventTypeFallback = JsonGetString(objects[i], "eventType", "-");
      r.eventType = JsonGetString(objects[i], "EventType", eventTypeFallback);

      // summary: presentation-ready title/subtitle/badges/scoreBucket,
      // see AlertSummaryDto in the V1 API repo. Scoped to the nested
      // "summary": {...} object (not a flat JsonGetString call) so its
      // fields can't collide with a same-named field elsewhere in the
      // row, and so badges (a JSON array) can be read correctly --
      // JsonGetString has no concept of array brackets.
      string summaryObj = JsonExtractObject(objects[i], "summary");

      string rawHeadline;
      if(StringLen(summaryObj) > 0)
      {
         string headlineFallback = HumanizeEventType(r.eventType);
         rawHeadline = JsonGetString(summaryObj, "title", headlineFallback);
         r.subtitle  = JsonGetString(summaryObj, "subtitle", "");
         r.scoreBucket = JsonGetString(summaryObj, "scoreBucket", "");
         JsonGetStringArray(summaryObj, "badges", r.badges);
      }
      else
      {
         // No summary object on this row (older API response, or this
         // alert type isn't covered by AlertSummaryBuilder yet) --
         // degrade gracefully instead of showing a blank headline.
         rawHeadline = HumanizeEventType(r.eventType);
         r.subtitle = "";
         r.scoreBucket = "";
         ArrayResize(r.badges, 0);
      }
      r.headline = StripTickerSuffix(rawHeadline, r.ticker);

      // clusterCount: the live API field is "clusterCount" (int), not
      // "Cluster"/"cluster" -- those keys never matched a real response
      // field, so this column always fell back to "-". See
      // AlertEventDto.ClusterCount in the V1 API repo. JsonGetNumberAsString
      // is fine here, same as the score fields above.
      string clusterFallback2 = JsonGetString(objects[i], "cluster", "-");
      string clusterFallback1 = JsonGetString(objects[i], "Cluster", clusterFallback2);
      r.cluster = JsonGetNumberAsString(objects[i], "clusterCount", clusterFallback1);

      // details: scoped extraction of the nested "details" object (see
      // AlertDetailsDto in the V1 API repo), now that JsonExtractObject
      // exists. Previously "side" was read via an unscoped JsonGetString
      // search across the whole row, relying on the fact that no other
      // unescaped "side" key happens to exist elsewhere in a real row --
      // true today, but scoping to the actual details object removes
      // the dependency on that assumption staying true as the API
      // grows new fields. Same applies to transactionValue (r.ownValue
      // below), which has no top-level fallback at all to fall back on.
      string detailsObj = JsonExtractObject(objects[i], "details");
      string side;
      string ownValueRaw;
      if(StringLen(detailsObj) > 0)
      {
         side = JsonGetString(detailsObj, "side", "");
         ownValueRaw = JsonGetNumberAsString(detailsObj, "transactionValue", "-");
      }
      else
      {
         side = "";
         ownValueRaw = "-";
      }
      r.ownSide  = side;
      r.ownValue = FormatCompactValue(ownValueRaw);

      string eventDateFallback = JsonGetString(objects[i], "eventDate", "-");
      string eventDateRaw = JsonGetString(objects[i], "EventDate", eventDateFallback);
      string eventDate = ShortenDate(eventDateRaw);
      r.ownDate = eventDate;

      // lastBuyDate/lastBuyValue/lastSellDate: the live API fields are
      // camelCase lastBuyDate / lastBuyValue / lastSellDate (see
      // AlertEventDto in the V1 API repo, added specifically for
      // trading-platform scanners like this one), not "LastBuy"/"lastBuy"/
      // "LastSell"/"lastSell"/"BuyValue"/"buyValue" -- none of which were
      // ever real field names, so these always fell back to per-row
      // inference from side+eventDate below. Old keys kept as a deeper
      // fallback in case an older API version ever sends the short names,
      // but the real field names are tried first now.
      string lastBuyFallback2 = JsonGetString(objects[i], "lastBuy", "");
      string lastBuyFallback1 = JsonGetString(objects[i], "LastBuy", lastBuyFallback2);
      string lastBuyRaw = JsonGetString(objects[i], "lastBuyDate", lastBuyFallback1);
      string explicitLastBuy = ShortenDate(lastBuyRaw);

      string lastSellFallback2 = JsonGetString(objects[i], "lastSell", "");
      string lastSellFallback1 = JsonGetString(objects[i], "LastSell", lastSellFallback2);
      string lastSellRaw = JsonGetString(objects[i], "lastSellDate", lastSellFallback1);
      string explicitLastSell = ShortenDate(lastSellRaw);

      string buyValueFallback2 = JsonGetString(objects[i], "buyValue", "-");
      string buyValueFallback1 = JsonGetString(objects[i], "BuyValue", buyValueFallback2);
      string buyValueRaw = JsonGetNumberAsString(objects[i], "lastBuyValue", buyValueFallback1);
      // lastBuyValue comes back from the API as a raw DECIMAL(24,6), e.g.
      // "234789.120000" -- 13+ unformatted characters, which is what was
      // blowing out the Buy Value column width and smearing into Last
      // Sell. FormatCompactValue collapses that to "$235K" / "$1.2M" etc,
      // matching how the score/value columns read everywhere else in
      // trading-tool UI conventions.
      r.buyValue = FormatCompactValue(buyValueRaw);

      if(StringLen(explicitLastBuy) > 0 && explicitLastBuy != "-")
         r.lastBuy = explicitLastBuy;
      else if(StringToUpperCopy(side) == "BUY")
         r.lastBuy = eventDate;
      else
         r.lastBuy = "-";

      if(StringLen(explicitLastSell) > 0 && explicitLastSell != "-")
         r.lastSell = explicitLastSell;
      else if(StringToUpperCopy(side) == "SELL")
         r.lastSell = eventDate;
      else
         r.lastSell = "-";

      rows[i] = r;
   }

   // Bullish-first ordering: EDGAR Alert's core edge is insider buying, so
   // BUY-side / higher-score rows should surface above SELL-side rows
   // regardless of what order the API returned them in.
   SortRowsBullishFirst(rows);

   return true;
}

//+------------------------------------------------------------------+
//| Uppercase copy helper (StringToUpper mutates in place in MQL5)   |
//+------------------------------------------------------------------+
string StringToUpperCopy(string s)
{
   string copy = s;
   StringToUpper(copy);
   return copy;
}

//+------------------------------------------------------------------+
//| Sort rows so BUY-signal rows lead, SELL-only rows trail, and      |
//| each group is ordered by score (highest first). Simple insertion |
//| sort -- row counts here are small (MaxRows <= 50).                |
//+------------------------------------------------------------------+
void SortRowsBullishFirst(SignalRow &rows[])
{
   int n = ArraySize(rows);
   for(int i = 1; i < n; i++)
   {
      SignalRow key = rows[i];
      int j = i - 1;
      while(j >= 0 && RowRank(rows[j]) > RowRank(key))
      {
         rows[j + 1] = rows[j];
         j--;
      }
      rows[j + 1] = key;
   }
}

//+------------------------------------------------------------------+
//| Lower rank = higher priority. Has-a-buy beats no-buy; within that,|
//| higher score sorts first.                                         |
//+------------------------------------------------------------------+
double RowRank(SignalRow &r)
{
   bool hasBuy = (r.lastBuy != "-" && StringLen(r.lastBuy) > 0);
   double score = StringToDouble(r.score);
   if(r.score == "-" || StringLen(r.score) == 0)
      score = 0;

   // Buy rows: rank 0..(-score), so higher score = more negative = sorts first.
   // Sell-only rows: rank starts at 1000, so they always sort after every buy row,
   // still ordered by score among themselves.
   double bucket = hasBuy ? 0.0 : 1000.0;
   return bucket - score;
}

//+------------------------------------------------------------------+
//| Find the LAST occurrence of a bracket character (for arr end)    |
//+------------------------------------------------------------------+
int StringFindLastBracket(const string &s, const string &ch)
{
   int last = -1;
   int from = 0;
   while(true)
   {
      int pos = StringFind(s, ch, from);
      if(pos == -1) break;
      last = pos;
      from = pos + 1;
   }
   return last;
}

//+------------------------------------------------------------------+
//| Split a JSON array body into top-level {...} object strings      |
//+------------------------------------------------------------------+
int SplitTopLevelObjects(const string &arrBody, string &outObjects[])
{
   int n = StringLen(arrBody);
   int depth = 0;
   int start = -1;
   bool inString = false;
   int count = 0;
   ArrayResize(outObjects, 0);

   for(int i = 0; i < n; i++)
   {
      ushort c = StringGetCharacter(arrBody, i);

      if(c == '"')
      {
         // toggle string mode unless this quote is escaped
         bool escaped = (i > 0 && StringGetCharacter(arrBody, i - 1) == '\\');
         if(!escaped)
            inString = !inString;
         continue;
      }

      if(inString)
         continue;

      if(c == '{')
      {
         if(depth == 0)
            start = i;
         depth++;
      }
      else if(c == '}')
      {
         depth--;
         if(depth == 0 && start >= 0)
         {
            string obj = StringSubstr(arrBody, start, i - start + 1);
            count++;
            ArrayResize(outObjects, count);
            outObjects[count - 1] = obj;
            start = -1;
         }
      }
   }

   return count;
}

//+------------------------------------------------------------------+
//| Extract the JSON object value of "key": { ... } from obj, e.g.   |
//| pulling the nested "summary": {...} object out of an alert row   |
//| so its fields (title/subtitle/badges/scoreBucket) can be read    |
//| without risk of colliding with a same-named field elsewhere in   |
//| the row. Returns "" if the key isn't present or its value isn't  |
//| an object (e.g. it's null, on an alert type where summary fields |
//| weren't computed). Uses the same brace-depth-tracking approach   |
//| as SplitTopLevelObjects above, since a naive "find the next }"    |
//| would stop at the first nested closing brace instead of the      |
//| matching one (summary itself contains a nested object: the       |
//| badges array doesn't nest braces, but probability-bearing alert  |
//| types elsewhere in this API do have nested objects, so this is   |
//| written to be correct in general, not just for today's shape).   |
//+------------------------------------------------------------------+
string JsonExtractObject(const string &obj, const string &key)
{
   string pattern = "\"" + key + "\"";
   int keyPos = StringFind(obj, pattern);
   if(keyPos == -1)
      return "";

   int colonPos = StringFind(obj, ":", keyPos + StringLen(pattern));
   if(colonPos == -1)
      return "";

   int n = StringLen(obj);
   int i = colonPos + 1;
   while(i < n && IsJsonWhitespace(StringGetCharacter(obj, i)))
      i++;

   if(i >= n || StringGetCharacter(obj, i) != '{')
      return ""; // null, or not an object -- nothing to extract

   int depth = 0;
   bool inString = false;
   int start = i;
   for(int j = i; j < n; j++)
   {
      ushort c = StringGetCharacter(obj, j);

      if(c == '"')
      {
         bool escaped = (j > 0 && StringGetCharacter(obj, j - 1) == '\\');
         if(!escaped)
            inString = !inString;
         continue;
      }
      if(inString)
         continue;

      if(c == '{')
      {
         depth++;
      }
      else if(c == '}')
      {
         depth--;
         if(depth == 0)
            return StringSubstr(obj, start, j - start + 1);
      }
   }

   return ""; // unterminated object -- malformed, treat as absent
}

//+------------------------------------------------------------------+
//| Extract a JSON string array value for "key": ["a","b",...] from  |
//| obj. Returns the count and fills outValues. Skips non-string      |
//| array elements rather than failing the whole array (defensive,    |
//| same philosophy as JsonGetString's tolerance of missing fields).  |
//| Used for summary.badges, which JsonGetString itself can't read    |
//| correctly -- its unquoted-literal fallback path has no concept    |
//| of array brackets or nested quoted strings, so calling it on an   |
//| array value would return a single garbled fragment instead of     |
//| the actual list.                                                  |
//+------------------------------------------------------------------+
int JsonGetStringArray(const string &obj, const string &key, string &outValues[])
{
   ArrayResize(outValues, 0);

   string pattern = "\"" + key + "\"";
   int keyPos = StringFind(obj, pattern);
   if(keyPos == -1)
      return 0;

   int colonPos = StringFind(obj, ":", keyPos + StringLen(pattern));
   if(colonPos == -1)
      return 0;

   int n = StringLen(obj);
   int i = colonPos + 1;
   while(i < n && IsJsonWhitespace(StringGetCharacter(obj, i)))
      i++;

   if(i >= n || StringGetCharacter(obj, i) != '[')
      return 0; // null, or not an array

   int count = 0;
   int j = i + 1;
   while(j < n)
   {
      ushort c = StringGetCharacter(obj, j);

      if(IsJsonWhitespace(c) || c == ',')
      {
         j++;
         continue;
      }
      if(c == ']')
         break; // end of array

      if(c == '"')
      {
         int k = j + 1;
         string val = "";
         while(k < n)
         {
            ushort ck = StringGetCharacter(obj, k);
            if(ck == '\\' && k + 1 < n)
            {
               ushort next = StringGetCharacter(obj, k + 1);
               if(next == 'u')
               {
                  int consumed = 1;
                  val += DecodeUnicodeEscape(obj, k + 1, consumed);
                  k += 1 + consumed;
                  continue;
               }
               val += ShortToString(next);
               k += 2;
               continue;
            }
            if(ck == '"')
               break;
            val += ShortToString(ck);
            k++;
         }
         count++;
         ArrayResize(outValues, count);
         outValues[count - 1] = val;
         j = k + 1;
         continue;
      }

      // Non-string element (shouldn't happen for badges, but skip
      // gracefully rather than mis-parsing) -- advance past it.
      j++;
   }

   return count;
}

//+------------------------------------------------------------------+
//| Hex digit '0'-'9'/'a'-'f'/'A'-'F' -> 0-15, or -1 if not a hex     |
//| digit. Used by DecodeUnicodeEscape below.                        |
//+------------------------------------------------------------------+
int HexDigitValue(ushort c)
{
   if(c >= '0' && c <= '9') return (int)(c - '0');
   if(c >= 'a' && c <= 'f') return (int)(c - 'a') + 10;
   if(c >= 'A' && c <= 'F') return (int)(c - 'A') + 10;
   return -1;
}

//+------------------------------------------------------------------+
//| Decodes a \uXXXX JSON unicode escape starting at obj[uPos] (uPos |
//| points at the 'u', not the backslash) into a one-character        |
//| string. Returns "" if the four characters after 'u' aren't valid  |
//| hex digits, so the caller can fall back gracefully instead of     |
//| emitting garbage. consumedOut is set to the number of characters  |
//| consumed starting from 'u' (always 5 on success: 'u' + 4 hex      |
//| digits) so the caller's scan position advances correctly.        |
//|                                                                    |
//| This exists because System.Text.Json (the serializer the V1 API   |
//| uses) escapes ALL non-ASCII characters as \uXXXX by default,      |
//| including the em dash in summary.title ("Large Buy vs History     |
//| \u2014 TPC") -- confirmed against System.Text.Json's documented    |
//| default JavaScriptEncoder behavior, not assumed. Without this,    |
//| the old fallback (ShortToString(next) on whatever follows the     |
//| backslash) would emit a literal 'u' character and then continue   |
//| parsing "2014" as regular text, corrupting every title that       |
//| contains a non-ASCII character.                                  |
//+------------------------------------------------------------------+
string DecodeUnicodeEscape(const string &obj, int uPos, int &consumedOut)
{
   consumedOut = 1; // just the 'u' itself, on failure
   int n = StringLen(obj);
   if(uPos + 4 >= n)
      return "";

   int codePoint = 0;
   for(int k = 1; k <= 4; k++)
   {
      int digit = HexDigitValue(StringGetCharacter(obj, uPos + k));
      if(digit < 0)
         return "";
      codePoint = codePoint * 16 + digit;
   }

   consumedOut = 5; // 'u' + 4 hex digits
   return ShortToString((ushort)codePoint);
}

//+------------------------------------------------------------------+
//| Extract a JSON string value for "key": "value" or "key": value   |
//| Falls back to defaultVal if the key is missing or null.          |
//+------------------------------------------------------------------+
string JsonGetString(const string &obj, const string &key, const string &defaultVal)
{
   string pattern = "\"" + key + "\"";
   int keyPos = StringFind(obj, pattern);
   if(keyPos == -1)
      return defaultVal;

   int colonPos = StringFind(obj, ":", keyPos + StringLen(pattern));
   if(colonPos == -1)
      return defaultVal;

   int i = colonPos + 1;
   int n = StringLen(obj);
   // skip whitespace
   while(i < n && IsJsonWhitespace(StringGetCharacter(obj, i)))
      i++;

   if(i >= n)
      return defaultVal;

   ushort c = StringGetCharacter(obj, i);

   if(c == 'n') // null
      return defaultVal;

   if(c == '"')
   {
      int j = i + 1;
      string val = "";
      while(j < n)
      {
         ushort cj = StringGetCharacter(obj, j);
         if(cj == '\\' && j + 1 < n)
         {
            ushort next = StringGetCharacter(obj, j + 1);
            if(next == 'n') { val += "\n"; j += 2; continue; }
            if(next == 't') { val += "\t"; j += 2; continue; }
            if(next == 'u')
            {
               int consumed = 1;
               string decoded = DecodeUnicodeEscape(obj, j + 1, consumed);
               val += decoded; // "" on a malformed escape -- drop it
                                // silently rather than emit garbage
               j += 1 + consumed; // skip the backslash + 'u' + hex digits
               continue;
            }
            val += ShortToString(next);
            j += 2;
            continue;
         }
         if(cj == '"')
            break;
         val += ShortToString(cj);
         j++;
      }
      if(StringLen(val) == 0)
         return defaultVal;
      return val;
   }

   // Unquoted literal (number/bool) - read until , or } or whitespace
   int j = i;
   string val = "";
   while(j < n)
   {
      ushort cj = StringGetCharacter(obj, j);
      if(cj == ',' || cj == '}' || IsJsonWhitespace(cj))
         break;
      val += ShortToString(cj);
      j++;
   }
   if(StringLen(val) == 0)
      return defaultVal;
   return val;
}

//+------------------------------------------------------------------+
//| Same as JsonGetString but only matches numeric-looking values    |
//+------------------------------------------------------------------+
string JsonGetNumberAsString(const string &obj, const string &key, const string &defaultVal)
{
   string raw = JsonGetString(obj, key, "");
   if(StringLen(raw) == 0)
      return defaultVal;
   return raw;
}

bool IsJsonWhitespace(ushort c)
{
   return (c == ' ' || c == '\t' || c == '\r' || c == '\n');
}

//+------------------------------------------------------------------+
//| Best-effort signal label from a numeric score string, matching   |
//| EDGAR Alert's published thresholds (45+ = BUY, 60+ = STRONG,     |
//| 80+ = VERY STRONG). Used only if the API does not send a label.  |
//+------------------------------------------------------------------+
string ScoreToSignalLabel(const string &scoreStr)
{
   if(scoreStr == "-" || StringLen(scoreStr) == 0)
      return "-";

   double score = StringToDouble(scoreStr);
   if(score >= 80) return "VERY STRONG";
   if(score >= 60) return "STRONG";
   if(score >= 45) return "BUY";
   return "WATCH";
}

//+------------------------------------------------------------------+
//| summary.title from AlertSummaryBuilder always ends with           |
//| " <em-dash> TICKER" (see Services/AlertSummaryBuilder.cs in the   |
//| V1 API repo -- both the BUY/SELL and MGMT branches append it).    |
//| The card layout already shows ticker as its own field, so leaving |
//| it in the headline reads as a repeated word right next to itself  |
//| ("TPC ... Large Buy vs History \u2014 TPC"). Strips it if present,  |
//| leaves the title untouched if it doesn't match (e.g. an older API |
//| version, or this title came from the eventType fallback instead   |
//| of a real summary object).                                       |
//+------------------------------------------------------------------+
string StripTickerSuffix(const string &title, const string &ticker)
{
   if(StringLen(ticker) == 0)
      return title;

   string emDash = ShortToString((ushort)0x2014);
   string suffix = " " + emDash + " " + ticker;

   int titleLen  = StringLen(title);
   int suffixLen = StringLen(suffix);
   if(titleLen <= suffixLen)
      return title;

   string tail = StringSubstr(title, titleLen - suffixLen, suffixLen);
   if(tail == suffix)
      return StringSubstr(title, 0, titleLen - suffixLen);

   return title;
}

//+------------------------------------------------------------------+
//| Turns a raw eventType constant into a readable headline when no   |
//| summary object is present on the row (older API response, or an   |
//| alert type AlertSummaryBuilder doesn't recognize yet). Covers the |
//| documented EVENT_TYPES list; falls back to the raw eventType      |
//| (still better than nothing) for anything unrecognized.            |
//+------------------------------------------------------------------+
string HumanizeEventType(const string &eventType)
{
   if(eventType == "INSIDER_BUY")             return "Insider Buy";
   if(eventType == "INSIDER_SELL")            return "Insider Sell";
   if(eventType == "FIRST_OBSERVED_BUY")      return "First-Time Buyer";
   if(eventType == "FIRST_OBSERVED_SELL")     return "First-Time Seller";
   if(eventType == "LARGE_BUY_VS_HISTORY")    return "Large Buy vs History";
   if(eventType == "LARGE_SELL_VS_HISTORY")   return "Large Sell vs History";
   if(eventType == "CLUSTER_BUY")             return "Cluster Buy";
   if(eventType == "CLUSTER_SELL")            return "Cluster Sell";
   if(eventType == "MGMT_CEO_APPOINTED")      return "CEO Appointed";
   if(eventType == "MGMT_CFO_APPOINTED")      return "CFO Appointed";
   if(eventType == "MGMT_CEO_RESIGNED")       return "CEO Resigned";
   if(eventType == "MGMT_CFO_RETIRED")        return "CFO Retired";
   if(eventType == "MGMT_DIRECTOR_APPOINTED") return "Director Appointed";
   if(eventType == "-" || StringLen(eventType) == 0)
      return "Insider Alert";
   return eventType; // unrecognized -- show the raw constant rather than nothing
}

//+------------------------------------------------------------------+
//| Shorten an ISO date/time string to just the date portion         |
//+------------------------------------------------------------------+
string ShortenDate(const string &iso)
{
   if(iso == "-" || StringLen(iso) == 0)
      return "-";
   int tPos = StringFind(iso, "T");
   if(tPos > 0)
      return StringSubstr(iso, 0, tPos);
   return iso;
}

//+------------------------------------------------------------------+
//| Format a raw dollar-value string ("234789.120000") as compact    |
//| currency ("$235K", "$1.2M", "$890") for the Buy Value column.    |
//| The API returns lastBuyValue as a raw DECIMAL(24,6) -- 13+        |
//| unformatted characters -- which is wider than the column was      |
//| ever sized for and was overlapping into Last Sell. Returns "-"    |
//| for anything that doesn't parse as a real positive number.        |
//+------------------------------------------------------------------+
string FormatCompactValue(const string &raw)
{
   if(raw == "-" || StringLen(raw) == 0)
      return "-";

   double v = StringToDouble(raw);
   if(v <= 0)
      return "-";

   // Thresholds are set just below the exact unit boundary, not at it,
   // so a value like 999,999,999.99 -- which rounds to "1000.0M" at one
   // decimal place if checked against the 1,000,000,000 threshold
   // directly -- correctly bumps up to "$1.0B" instead. Same reasoning
   // one tier down for the K/M boundary.
   if(v >= 999950000.0)
      return "$" + DoubleToString(v / 1000000000.0, 1) + "B";
   if(v >= 1000000.0)
      return "$" + DoubleToString(v / 1000000.0, 1) + "M";
   if(v >= 999500.0)
      return "$" + DoubleToString(v / 1000000.0, 1) + "M";
   if(v >= 1000.0)
      return "$" + DoubleToString(v / 1000.0, 0) + "K";
   return "$" + DoubleToString(v, 0);
}

//+------------------------------------------------------------------+
//| Set the status line text/color (drawn at the bottom of panel)    |
//+------------------------------------------------------------------+
void SetStatus(string msg, color clr)
{
   g_statusMessage = msg;
   g_statusColor   = clr;
}

//+------------------------------------------------------------------+
//| Draw title + footer (chrome that's always visible)               |
//+------------------------------------------------------------------+
void DrawStaticChrome()
{
   // Small initial panel -- DrawStatusOnly/DrawTable resize it correctly
   // as soon as real content is known, this just avoids a single frame
   // with the title floating with no backing at all on first load.
   // STATUS_LINE_HEIGHT (18px) is the same single-text-line spacing the
   // old grid called ROW_HEIGHT, kept as its own constant now that the
   // card layout has its own, larger CARD_HEIGHT for actual data rows.
   DrawPanelBackground(HEADER_Y + STATUS_LINE_HEIGHT + 20);
   CreateLabel(EA_PREFIX + "Title", PANEL_X, 20, EA_TITLE, FONT_SIZE_TITLE, clrWhite, true);
}

//+------------------------------------------------------------------+
//| Draw just the status line (used for error / empty-key states)    |
//+------------------------------------------------------------------+
void DrawStatusOnly()
{
   ObjectsDeleteAll(0, EA_PREFIX + "Row");
   ObjectsDeleteAll(0, EA_PREFIX + "Col");
   int panelHeight = HEADER_Y + STATUS_LINE_HEIGHT + 6 + STATUS_LINE_HEIGHT + 10;
   DrawPanelBackground(panelHeight);
   CreateLabel(EA_PREFIX + "Status", PANEL_X, HEADER_Y, g_statusMessage, FONT_SIZE_STATUS, g_statusColor, false);
   CreateLabel(EA_PREFIX + "Footer", PANEL_X, HEADER_Y + STATUS_LINE_HEIGHT + 6, EA_FOOTER, FONT_SIZE_STATUS, clrGray, false);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Draw the full signal list as a stack of two-line cards            |
//+------------------------------------------------------------------+
void DrawTable(SignalRow &rows[])
{
   ObjectsDeleteAll(0, EA_PREFIX + "Row");
   ObjectsDeleteAll(0, EA_PREFIX + "Col");
   ObjectsDeleteAll(0, EA_PREFIX + "Card");
   ObjectsDeleteAll(0, EA_PREFIX + "Badge");

   int rowCount  = ArraySize(rows);
   int listTop   = HEADER_Y + 14;
   int footerY   = listTop + CARD_HEIGHT * rowCount + 10;
   DrawPanelBackground(footerY + 16);

   // Status line just under the title
   CreateLabel(EA_PREFIX + "Status", PANEL_X, HEADER_Y, g_statusMessage, FONT_SIZE_STATUS, g_statusColor, false);

   for(int r = 0; r < rowCount; r++)
   {
      int cardTop = listTop + CARD_HEIGHT * r;
      DrawSignalCard(r, cardTop, rows[r]);
   }

   CreateLabel(EA_PREFIX + "Footer", PANEL_X, footerY, EA_FOOTER, FONT_SIZE_STATUS, clrGray, false);

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Draw one alert as a two-line card:                                |
//|   Line 1: TICKER  SCORE SIGNAL                 <headline>         |
//|   Line 2: Side $value \u00b7 date                  [badge] [badge]   |
//| cardTop is this card's y-offset from the panel's content origin   |
//| (PANEL_X-relative, same coordinate space CreateLabel already      |
//| uses everywhere else in this file).                                |
//+------------------------------------------------------------------+
void DrawSignalCard(int rowIndex, int cardTop, SignalRow &row)
{
   string prefix = EA_PREFIX + "Row" + IntegerToString(rowIndex);
   color rowColor = SignalColor(row.signal);

   // Subtle per-card background, one shade lighter than the main panel,
   // so cards read as distinct rows without needing a drawn border on
   // every one (a border per card would be visually noisy at 50px tall).
   DrawCardBackground(prefix + "Bg", cardTop, CARD_HEIGHT - CARD_GAP);

   // ── Line 1: ticker, score+signal, headline ──────────────────────
   CreateLabel(prefix + "Ticker", PANEL_X + 4, cardTop + CARD_LINE1_Y,
               row.ticker, FONT_SIZE_HEADER, rowColor, true);

   string scoreSignal = row.score + " " + row.signal;
   CreateLabel(prefix + "ScoreSignal", PANEL_X + 46, cardTop + CARD_LINE1_Y,
               scoreSignal, FONT_SIZE_ROW, rowColor, false);

   CreateLabel(prefix + "Headline", PANEL_X + CARD_LEFT_W, cardTop + CARD_LINE1_Y,
               row.headline, FONT_SIZE_HEADER, clrWhite, true);

   // ── Line 2 left: this alert's own side + value + date ───────────
   string detailLine = BuildDetailLine(row);
   color detailColor = (StringToUpperCopy(row.ownSide) == "SELL") ? clrSalmon
                        : (StringToUpperCopy(row.ownSide) == "BUY") ? clrLimeGreen
                        : clrSilver;
   CreateLabel(prefix + "Detail", PANEL_X + 4, cardTop + CARD_LINE2_Y,
               detailLine, FONT_SIZE_STATUS, detailColor, false);

   // ── Line 2 right: badges ─────────────────────────────────────────
   int badgeX = PANEL_X + CARD_LEFT_W;
   int badgeCount = ArraySize(row.badges);
   for(int b = 0; b < badgeCount; b++)
   {
      int badgeW = DrawBadge(prefix + "Badge" + IntegerToString(b),
                              badgeX, cardTop + CARD_BADGE_Y, row.badges[b], rowColor);
      badgeX += badgeW + BADGE_GAP;
   }
}

//+------------------------------------------------------------------+
//| Builds the line-2 detail string, e.g. "Buy $1.2M \u00b7 2026-03-06",  |
//| "Sell \u00b7 2026-02-25" (MGMT-type alert, no dollar value), or just   |
//| the date if side is unknown.                                      |
//+------------------------------------------------------------------+
string BuildDetailLine(SignalRow &row)
{
   string sideLabel = "";
   string upperSide = StringToUpperCopy(row.ownSide);
   if(upperSide == "BUY")  sideLabel = "Buy";
   if(upperSide == "SELL") sideLabel = "Sell";

   string middot = ShortToString((ushort)0x00B7); // ·

   string parts = "";
   if(StringLen(sideLabel) > 0)
      parts += sideLabel;
   if(row.ownValue != "-" && StringLen(row.ownValue) > 0)
      parts += (StringLen(parts) > 0 ? " " : "") + row.ownValue;
   if(row.ownDate != "-" && StringLen(row.ownDate) > 0)
      parts += (StringLen(parts) > 0 ? " " + middot + " " : "") + row.ownDate;

   if(StringLen(parts) == 0)
      return "-";
   return parts;
}

//+------------------------------------------------------------------+
//| Pick a row color based on the signal label                       |
//+------------------------------------------------------------------+
color SignalColor(string signal)
{
   if(signal == "VERY STRONG") return clrLime;
   if(signal == "STRONG")      return clrYellowGreen;
   if(signal == "BUY")         return clrKhaki;
   return clrWhite;
}

//+------------------------------------------------------------------+
//| Create (or update) a single chart text label object              |
//+------------------------------------------------------------------+
void CreateLabel(string name, int x, int y, string text, int fontSize, color clr, bool bold)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }

   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, bold ? FONT_NAME : FONT_NAME);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
//| Create or resize the solid backing panel behind the whole table, |
//| so text is readable over candles instead of floating directly on |
//| the chart with nothing behind it. height is the total panel      |
//| height needed for the current content (varies with row count),  |
//| so this is called fresh on every redraw, not just once in init.  |
//| OBJPROP_BACK=true is required here specifically: CreateLabel's   |
//| labels are created with OBJPROP_BACK=false (foreground), and a   |
//| background-layer object always renders behind foreground ones    |
//| regardless of creation order -- but creating/updating this first |
//| each redraw keeps the draw sequence easy to follow regardless.   |
//+------------------------------------------------------------------+
void DrawPanelBackground(int height)
{
   string name = EA_PREFIX + "PanelBg";

   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   }

   // A few pixels of padding around the text content on every side.
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, PANEL_X - 8);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 6);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, PANEL_WIDTH);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, PANEL_BG_COLOR);
   ObjectSetInteger(0, name, OBJPROP_COLOR, PANEL_BORDER_COLOR);
}

//+------------------------------------------------------------------+
//| Draw one card's background -- a shade lighter than the main panel |
//| so cards read as distinct rows without a drawn border on every    |
//| one (a border per card at 50px tall reads as noisy/striped --     |
//| a flat color shift is enough separation and looks calmer).        |
//+------------------------------------------------------------------+
void DrawCardBackground(string name, int y, int height)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   }

   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, PANEL_X - 2);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, PANEL_WIDTH - 12);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, C'18,18,18');
   ObjectSetInteger(0, name, OBJPROP_COLOR, C'18,18,18');
}

//+------------------------------------------------------------------+
//| Draw one small rounded-looking badge pill (a colored background   |
//| rect with the badge text on top) at (x, y). Returns the pill's    |
//| total width in pixels, so the caller can position the next badge  |
//| right after it.                                                   |
//|                                                                    |
//| MQL5's OBJ_RECTANGLE_LABEL has no text-measurement API to ask     |
//| "how wide will this string render at this font/size" -- so width  |
//| is estimated the same way every other column/spacing decision in  |
//| this file is: chars * an empirically-reasonable px/char for       |
//| Consolas at this size, plus fixed padding. Width is recalculated  |
//| per badge text length rather than using one fixed pill width,     |
//| since badge text length varies a lot ("ESPP" vs                   |
//| "Scheduled (10b5-1)") and a one-size pill would either clip the    |
//| long ones or waste a lot of space on the short ones.              |
//+------------------------------------------------------------------+
int DrawBadge(string name, int x, int y, const string &text, color rowColor)
{
   double charWidth = 4.8; // Consolas at BADGE_FONT_SIZE=8, same estimation
                            // approach as the column-width math elsewhere
                            // in this file (FormatCompactValue's column,
                            // the old grid's ColX) -- not exact kerning,
                            // close enough that real text doesn't clip.
   int textWidth = (int)MathRound(StringLen(text) * charWidth);
   int pillWidth = textWidth + (BADGE_PAD_X * 2);

   string bgName = name + "Bg";
   if(ObjectFind(0, bgName) < 0)
   {
      ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bgName, OBJPROP_BACK, false); // sits on top of
                                                          // the card background,
                                                          // below the text label
      ObjectSetInteger(0, bgName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, bgName, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   }
   ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, bgName, OBJPROP_XSIZE, pillWidth);
   ObjectSetInteger(0, bgName, OBJPROP_YSIZE, BADGE_HEIGHT);
   color pillColor = BadgeFillColor(rowColor);
   ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, pillColor);
   ObjectSetInteger(0, bgName, OBJPROP_COLOR, pillColor);

   CreateLabel(name + "Text", x + BADGE_PAD_X, y + 2, text, BADGE_FONT_SIZE, rowColor, false);

   return pillWidth;
}

//+------------------------------------------------------------------+
//| Dim background fill for a badge pill, derived from the row's      |
//| signal color so badges read as "part of this row" rather than a   |
//| fixed unrelated color. Picks a fixed dark tint per color family    |
//| rather than computing one mathematically -- MQL5's color type has |
//| no built-in HSL/brightness adjustment helpers, and a small fixed  |
//| set covers every value SignalColor() actually returns.            |
//+------------------------------------------------------------------+
color BadgeFillColor(color rowColor)
{
   if(rowColor == clrLime)         return C'20,46,20';  // VERY STRONG
   if(rowColor == clrYellowGreen)  return C'38,46,20';  // STRONG
   if(rowColor == clrKhaki)        return C'46,42,20';  // BUY
   return C'30,30,30';                                   // WATCH / default
}

//+------------------------------------------------------------------+

