# EDGAR Alert Trading Tools

<p align="center">
  <img src="https://edgaralert.com/images/telegram-edgaralert.jpg"
       alt="EDGAR Alert"
       width="10"
       style="vertical-align:middle; margin-right:12px;" />

  <strong>
    Free stock-market tools powered by SEC filings, Form 4 insider buying,
    insider trading activity, 8-K management changes, activist investor filings,
    and EDGAR Alert intelligence.
  </strong>
</p>

<p align="center">
  <a href="https://edgaralert.com">Website</a> •
  <a href="https://edgaralert.com/pricing">API Access</a> •
  <a href="https://edgaralert.com/research-app">Research</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="License">
  <img src="https://img.shields.io/badge/MT5-Available-blue" alt="MT5">
  <img src="https://img.shields.io/badge/NinjaTrader-Planned-orange" alt="NinjaTrader">
  <img src="https://img.shields.io/badge/SEC-EDGAR-red" alt="SEC EDGAR">
</p>

---

## What Is EDGAR Alert?

EDGAR Alert helps investors discover market-moving signals hidden inside SEC filings.

Our platform analyzes:

* Form 4 insider buying and insider selling
* Executive and director transactions
* Cluster buying activity
* 8-K management changes
* Activist investor filings (13D)
* Institutional ownership disclosures
* Corporate events and SEC filings
* Insider trading trends
* Proprietary insider activity scoring

This repository contains free trading-platform plugins that connect to the EDGAR Alert API and display those signals directly inside trading software.

---

## Available Tools

| Tool                      | Platform     | Status    |
| ------------------------- | ------------ | --------- |
| EDGAR Alert Stock Scanner | MetaTrader 5 | Available |
| EDGAR Alert Stock Scanner | NinjaTrader  | Planned   |

---

## Why This Is Different

Most trading indicators analyze:

* Price action
* Volume
* Moving averages
* Technical patterns

EDGAR Alert focuses on:

* SEC filings
* Insider buying
* Insider selling
* Executive transactions
* Management changes
* Activist investors
* Institutional ownership
* Corporate events

Our goal is to surface information that often appears before it becomes widely discussed by the market.

---

## Features

### Current

* Stock Scanner
* Market Scanner
* Form 4 Insider Buying Signals
* Insider Trading Analytics
* Cluster Buy Detection
* SEC Filing Monitoring

### Planned

* 8-K Management Change Alerts
* Activist Investor Tracking
* Institutional Ownership Monitoring
* Custom Watchlists
* Real-Time Notifications
* Multi-Platform Support

---

## Repository Structure

```text
edgaralert-trading-tools/
├── mt5/
│   └── EdgarAlertStockScanner/
│       ├── EdgarAlertStockScanner.mq5
│       └── README.md
├── ninjatrader/
│   └── EdgarAlertStockScanner/
│       └── README.md
├── docs/
│   ├── architecture.md
│   └── mt5-install.md
├── LICENSE
└── README.md
```

## Getting Started

### MetaTrader 5

See:

```text
mt5/EdgarAlertStockScanner/README.md
```

for installation instructions and configuration.

### NinjaTrader

Coming soon.

---

## Requirements

All tools in this repository require an EDGAR Alert account and API key.

Create a free account:

https://edgaralert.com

---

## Keywords

SEC Filings • Form 4 • Insider Buying • Insider Trading • Stock Scanner • Market Scanner • SEC EDGAR • 8-K Monitoring • Management Change Detection • Activist Investor Tracking • Institutional Ownership • Financial Data • Stock Market Research • Algorithmic Trading • MT5 • NinjaTrader

---

## Contributing

Issues and pull requests are welcome.

This repository contains client-side trading platform integrations only. Proprietary signal-generation logic and EDGAR Alert backend services are not included.

---

## License

MIT License

See LICENSE for details.

---

Powered by EDGAR Alert

https://edgaralert.com
