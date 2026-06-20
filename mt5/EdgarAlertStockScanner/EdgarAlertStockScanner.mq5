//+------------------------------------------------------------------+
//|                                    EdgarAlertStockScanner.mq5    |
//|                                          Powered by EDGARAlert.com|
//+------------------------------------------------------------------+
//|
//| EDGAR Alert Stock Scanner (MT5)
//|
//| FREE scanner / display tool. Pulls the latest insider-activity
//| signals from the EDGAR Alert API and shows them in a simple
//| on-chart table.
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
//|
//+------------------------------------------------------------------+
#property copyright "EDGARAlert.com"
#property link      "https://www.edgaralert.com"
#property version   "1.00"
#property strict
#property indicator_chart_window
#property indicator_plots 0

//--- Inputs -----------------------------------------------------------
input string   ApiKey         = "";                              // EDGAR Alert API key (required)
input string   ApiBaseUrl     = "https://api.edgaralert.com";     // API base URL
input int      RefreshSeconds = 900;                              // Refresh interval (seconds)
input int      MaxRows        = 10;                               // Max rows to display (1-50)

//--- Constants ----------------------------------------------------------
#define EA_PREFIX        "EAS_"          // prefix for every chart object we create, for clean cleanup
#define EA_TITLE         "EDGAR Alert Stock Scanner"
#define EA_FOOTER        "Powered by EDGARAlert.com"
#define COL_COUNT        8
#define ROW_HEIGHT       18
#define HEADER_Y         48
#define PANEL_X          12
#define FONT_NAME        "Consolas"
#define FONT_SIZE_HEADER 10
#define FONT_SIZE_ROW    9
#define FONT_SIZE_TITLE  11
#define FONT_SIZE_STATUS 9

// Column x-offsets (relative to PANEL_X), tuned for Consolas at FONT_SIZE_ROW
// Order matches the MVP column set: Ticker, Score, Signal, Last Buy, Buy Value,
// Last Sell, Cluster, Event. Sell Value is intentionally omitted for the MVP --
// insider buys are the clean signal; sells are noisy (tax planning, RSU vesting,
// 10b5-1 plans, diversification), so we show *that* a sell happened without
// dedicating a column to its size.
int ColX[COL_COUNT] = {0, 60, 115, 185, 260, 335, 405, 465};
string ColHeader[COL_COUNT] = {"Ticker","Score","Signal","Last Buy","Buy Value","Last Sell","Cluster","Event"};

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
};

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME, "EdgarAlertStockScanner");

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
//| Custom indicator iteration function (required, unused)           |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                 const int prev_calculated,
                 const datetime &time[],
                 const double &open[],
                 const double &high[],
                 const double &low[],
                 const double &close[],
                 const long &tick_volume[],
                 const long &volume[],
                 const int &spread[])
{
   return(rates_total);
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
      SetStatus("No signals returned", clrSilver);
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

   return base + "/api/v1/alerts/latest?limit=" + IntegerToString(MaxRowsClamped());
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
      r.ticker    = JsonGetString(objects[i], "Ticker",     JsonGetString(objects[i], "ticker", "-"));
      r.score     = JsonGetNumberAsString(objects[i], "SignalScore", JsonGetNumberAsString(objects[i], "signalScore",
                       JsonGetNumberAsString(objects[i], "score", "-")));
      r.signal    = JsonGetString(objects[i], "Signal", JsonGetString(objects[i], "signal",
                       ScoreToSignalLabel(r.score)));
      r.eventType = JsonGetString(objects[i], "EventType", JsonGetString(objects[i], "eventType", "-"));

      // clusterCount: the live API field is "clusterCount" (int), not
      // "Cluster"/"cluster" -- those keys never matched a real response
      // field, so this column always fell back to "-". See
      // AlertEventDto.ClusterCount in the V1 API repo. JsonGetNumberAsString
      // is fine here, same as the score fields above.
      r.cluster   = JsonGetNumberAsString(objects[i], "clusterCount",
                       JsonGetString(objects[i], "Cluster", JsonGetString(objects[i], "cluster", "-")));

      // side: NOT a top-level field on the live API. It only exists nested
      // at details.side (added alongside the typed "details" object that
      // replaced raw messageJson parsing -- see AlertDetailsDto.Side in the
      // V1 API repo). The flat key search below still finds it correctly
      // even though it's nested, because JsonGetString does an unscoped
      // substring search for "side": -- it doesn't care which object the
      // key lives in, as long as the text "side" appears unescaped (it
      // won't accidentally match the copy of "side" trapped inside the
      // escaped messageJson string, since that copy is serialized as
      // \"side\" with literal backslashes, not "side"). The old top-level
      // "Side"/"side" checks never matched anything real, and the
      // "MessageJson.side" fallback after them was dead code (JSON keys
      // don't have dots; that's not a path expression here, just a literal
      // key name that never exists) -- replaced both with the one that
      // actually works.
      string side = JsonGetString(objects[i], "side", "");
      string eventDate = ShortenDate(JsonGetString(objects[i], "EventDate", JsonGetString(objects[i], "eventDate", "-")));

      // lastBuyDate/lastBuyValue/lastSellDate: the live API fields are
      // camelCase lastBuyDate / lastBuyValue / lastSellDate (see
      // AlertEventDto in the V1 API repo, added specifically for
      // trading-platform scanners like this one), not "LastBuy"/"lastBuy"/
      // "LastSell"/"lastSell"/"BuyValue"/"buyValue" -- none of which were
      // ever real field names, so these always fell back to per-row
      // inference from side+eventDate below. Old keys kept as a deeper
      // fallback in case an older API version ever sends the short names,
      // but the real field names are tried first now.
      string explicitLastBuy  = JsonGetString(objects[i], "lastBuyDate",
                                    JsonGetString(objects[i], "LastBuy", JsonGetString(objects[i], "lastBuy", "")));
      explicitLastBuy = ShortenDate(explicitLastBuy);
      string explicitLastSell = JsonGetString(objects[i], "lastSellDate",
                                    JsonGetString(objects[i], "LastSell", JsonGetString(objects[i], "lastSell", "")));
      explicitLastSell = ShortenDate(explicitLastSell);
      r.buyValue  = JsonGetNumberAsString(objects[i], "lastBuyValue",
                       JsonGetString(objects[i], "BuyValue", JsonGetString(objects[i], "buyValue", "-")));

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
            if(next == 'n') val += "\n";
            else if(next == 't') val += "\t";
            else val += ShortToString(next);
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
   CreateLabel(EA_PREFIX + "Title", PANEL_X, 20, EA_TITLE, FONT_SIZE_TITLE, clrWhite, true);
}

//+------------------------------------------------------------------+
//| Draw just the status line (used for error / empty-key states)    |
//+------------------------------------------------------------------+
void DrawStatusOnly()
{
   ObjectsDeleteAll(0, EA_PREFIX + "Row");
   ObjectsDeleteAll(0, EA_PREFIX + "Col");
   CreateLabel(EA_PREFIX + "Status", PANEL_X, HEADER_Y, g_statusMessage, FONT_SIZE_STATUS, g_statusColor, false);
   CreateLabel(EA_PREFIX + "Footer", PANEL_X, HEADER_Y + ROW_HEIGHT + 6, EA_FOOTER, FONT_SIZE_STATUS, clrGray, false);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Draw the full signal table                                       |
//+------------------------------------------------------------------+
void DrawTable(SignalRow &rows[])
{
   ObjectsDeleteAll(0, EA_PREFIX + "Row");
   ObjectsDeleteAll(0, EA_PREFIX + "Col");

   // Status line just under the title
   CreateLabel(EA_PREFIX + "Status", PANEL_X, HEADER_Y, g_statusMessage, FONT_SIZE_STATUS, g_statusColor, false);

   int tableTop = HEADER_Y + ROW_HEIGHT + 4;

   // Column headers
   for(int c = 0; c < COL_COUNT; c++)
   {
      CreateLabel(EA_PREFIX + "ColHdr" + IntegerToString(c),
                  PANEL_X + ColX[c], tableTop,
                  ColHeader[c], FONT_SIZE_HEADER, clrDodgerBlue, true);
   }

   int rowCount = ArraySize(rows);
   for(int r = 0; r < rowCount; r++)
   {
      int y = tableTop + ROW_HEIGHT * (r + 1);
      color rowColor = SignalColor(rows[r].signal);

      DrawCell(r, 0, y, rows[r].ticker,    rowColor);
      DrawCell(r, 1, y, rows[r].score,     rowColor);
      DrawCell(r, 2, y, rows[r].signal,    rowColor);
      DrawCell(r, 3, y, rows[r].lastBuy,   rows[r].lastBuy  == "-" ? clrGray : clrLimeGreen);
      DrawCell(r, 4, y, rows[r].buyValue,  clrSilver);
      DrawCell(r, 5, y, rows[r].lastSell,  rows[r].lastSell == "-" ? clrGray : clrSalmon);
      DrawCell(r, 6, y, rows[r].cluster,   clrSilver);
      DrawCell(r, 7, y, rows[r].eventType, clrSilver);
   }

   int footerY = tableTop + ROW_HEIGHT * (rowCount + 1) + 8;
   CreateLabel(EA_PREFIX + "Footer", PANEL_X, footerY, EA_FOOTER, FONT_SIZE_STATUS, clrGray, false);

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Draw one table cell as a chart label object                      |
//+------------------------------------------------------------------+
void DrawCell(int row, int col, int y, string text, color clr)
{
   string name = EA_PREFIX + "Row" + IntegerToString(row) + "Col" + IntegerToString(col);
   CreateLabel(name, PANEL_X + ColX[col], y, text, FONT_SIZE_ROW, clr, false);
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
