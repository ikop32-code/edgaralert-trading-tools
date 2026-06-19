# EDGAR Alert Trading Tools

Free trading-platform plugins that connect to the
[EDGAR Alert](https://www.edgaralert.com) API and surface SEC/insider
activity signals directly inside trading platforms.

These tools are **scanners and displays only**. None of them place
trades, modify orders, or manage positions. EDGAR Alert is a SEC
filing intelligence platform, not a brokerage or trading system — see
[`docs/architecture.md`](docs/architecture.md) for the full reasoning.

## Status

| Platform     | Status        | Folder                                  |
|--------------|---------------|-------------------------------------------|
| MetaTrader 5 | MVP available | [`mt5/EdgarAlertStockScanner`](mt5/EdgarAlertStockScanner) |
| NinjaTrader  | Planned, not started | [`ninjatrader/EdgarAlertStockScanner`](ninjatrader/EdgarAlertStockScanner) |

## Folder structure

```
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

## Getting started

- **MT5 users:** go to
  [`mt5/EdgarAlertStockScanner/README.md`](mt5/EdgarAlertStockScanner/README.md)
  for install steps, or the condensed version at
  [`docs/mt5-install.md`](docs/mt5-install.md).
- **Contributors:** read [`docs/architecture.md`](docs/architecture.md)
  first — it covers how this project fits into the public EDGAR Alert
  API, why TradingView/Thinkorswim are out of scope for now, and why
  the platforms are sequenced MT5 → NinjaTrader.

## Requirements

All scanners in this repo require a free EDGAR Alert API key. Sign up
at https://www.edgaralert.com.

## Contributing

Issues and pull requests are welcome. This repo is client-only — it
contains no EDGAR Alert backend or proprietary signal-generation code,
only plugins that call the public, documented API.

## License

[MIT](LICENSE) — free to use, modify, and redistribute. See
[`LICENSE`](LICENSE) for the full text.
