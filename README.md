<div align="center">

# 🐸 CrypToad

**A crypto-linked debit card app concept — turn paychecks into crypto, spend it anywhere, and invest your spare change.**

[![CI](https://github.com/Sardeen07/CrypToad/actions/workflows/ci.yml/badge.svg)](https://github.com/Sardeen07/CrypToad/actions/workflows/ci.yml)
![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)
![SwiftUI](https://img.shields.io/badge/SwiftUI-iOS%2017-blue?logo=apple)
![FastAPI](https://img.shields.io/badge/FastAPI-PostgreSQL-009688?logo=fastapi)
![Status](https://img.shields.io/badge/status-prototype-yellow)
![License](https://img.shields.io/badge/license-MIT-green)

</div>

---

## Overview

CrypToad is an iOS app concept that connects everyday spending with
cryptocurrency investing. Your paycheck lands in USDC (a dollar-pegged
stablecoin), you spend it with a debit card, and every purchase is rounded up
with the spare change invested into BTC, ETH, or USDC.

The repo has three parts:

| Part | What it is |
|---|---|
| [`CrypToad/`](CrypToad) | SwiftUI iOS app |
| [`CrypToadCore/`](CrypToadCore) | Swift package with all the money logic, fully unit-tested |
| [`backend/`](backend) | FastAPI + PostgreSQL trading API with a double-entry ledger |

> ⚠️ **Prototype:** market prices are real (CoinGecko), but balances, the card,
> and trades are simulated. No real money or crypto moves. See
> [What's built vs. planned](#whats-built-vs-planned).

<!-- Add screenshots with ./scripts/screenshot.sh, then uncomment:
<p align="center">
  <img src="docs/screenshots/home.png" width="200">
  <img src="docs/screenshots/roundup.png" width="200">
  <img src="docs/screenshots/dca.png" width="200">
  <img src="docs/screenshots/trade.png" width="200">
</p>
-->

## Features

- **Live portfolio** — BTC/ETH prices and 24h change from CoinGecko, refreshed every minute and on pull-to-refresh, with offline fallback to the last known prices
- **Round-up investing** — every card purchase rounds up to the next dollar; the spare change actually buys BTC/ETH at live prices, split by your allocation. Optional 2×/3×/5× multiplier
- **Allocation editor** — sliders that always total 100%, plus presets (Balanced, Aggressive Bitcoin, Stablecoin Saver)
- **Dollar-cost averaging** — set amount and frequency; scheduled buys run automatically, including ones missed while the app was closed
- **Buy BTC / ETH with USDC** — live quote with a 1% fee breakdown before you confirm
- **Card controls** — freeze the card (blocks purchases) and reveal the PIN behind Face ID
- **Face ID app lock** — locks when the app leaves the screen
- **Saved locally** — everything persists between launches
- **Transaction history** — filter by spending, investing, or deposits

## Engineering highlights

- **Money is `Decimal`, never `Double`.** Floating point can't represent values like $0.10 exactly. `Decimal.exact("47.89")` avoids even the float-literal trap (`let x: Decimal = 47.89` is actually 47.89000000000000512).
- **No lost cents.** Splitting $0.75 across 50/30/20 rounds each share down, then gives leftover cents to the largest weight, so shares always add up exactly. A test checks this for thousands of amounts.
- **Failed operations change nothing.** Ledger operations validate funds, prices, and card state *before* touching balances. The store applies them to a copy and only commits on success.
- **Logic is separate from UI.** `CrypToadCore` has no SwiftUI dependency, so the same tests run on macOS and Linux in CI.
- **Double-entry backend.** Every trade is a journal entry that nets to zero per asset; amounts are stored as integer minor units; row locks, single-use quotes, and idempotency keys prevent double spending. See [`backend/README.md`](backend/README.md).

## What's built vs. planned

| Area | Status |
|---|---|
| SwiftUI app: home, round-ups, DCA, card, history, trade, settings | ✅ Built |
| Round-up, allocation, DCA, and trade logic (`CrypToadCore`) | ✅ Built + tested |
| Live market prices (CoinGecko) | ✅ Built |
| Local persistence | ✅ Built |
| Face ID / Touch ID lock | ✅ Built |
| Backend API: quote, trade, history, PostgreSQL ledger | ✅ Built + tested |
| CI (GitHub Actions) | ✅ Built |
| App ↔ backend connection | 🔲 Next up |
| Bank linking, KYC, card issuing, crypto custody | 🔲 Planned — requires licensed partners |

## Tech Stack

**iOS:** Swift, SwiftUI, Observation (`@Observable`), async/await, LocalAuthentication, XcodeGen
**Core:** Swift package, XCTest
**Backend:** Python 3.12, FastAPI, SQLAlchemy 2, PostgreSQL, pytest, Docker
**Data:** CoinGecko public API

## Getting Started

### Requirements

- macOS with **Xcode 15** or later
- iOS 17 simulator or device

### Run the app

```bash
brew install xcodegen
git clone https://github.com/Sardeen07/CrypToad.git
cd CrypToad
xcodegen generate
open CrypToad.xcodeproj
```

Pick an iPhone simulator and press **⌘R**.

> Face ID in the simulator: **Features → Face ID → Enrolled**, then
> **Features → Face ID → Matching Face** when prompted.

### Run the tests

```bash
swift test --package-path CrypToadCore     # Swift logic (macOS or Linux)
cd backend && pip install -r requirements-dev.txt && pytest   # API
```

### Run the backend

```bash
cd backend
docker compose up --build
open http://localhost:8000/docs
```

### Try it

- **Home → Simulate Purchase** adds a random card purchase and invests its round-up at live prices.
- **Home → Buy BTC / ETH** shows a live quote with the fee before you confirm.
- **Round-Up → Customize Allocation** opens the sliders.
- **Invest → Buy Now** runs a DCA buy; **Edit Schedule** changes amount and frequency.
- **Card → Freeze Card**, then try a purchase.
- **⚙️ → Require Face ID**, then background the app.

## Project Structure

```
CrypToad/
├── CrypToad/                      # iOS app
│   ├── App/
│   │   ├── CrypToadApp.swift      # Entry point, dependency setup
│   │   ├── PortfolioStore.swift   # @Observable store: prices, actions, persistence
│   │   └── AppLock.swift          # Face ID / Touch ID
│   ├── Support/                   # Theme + formatting
│   └── Views/
│       ├── RootView.swift         # Lock screen overlay
│       ├── ContentView.swift      # Navigation + sheets
│       ├── Screens/               # Home, Round-Up, DCA, Card, History
│       ├── Sheets/                # Trade, Allocation editor, DCA schedule, Settings
│       └── Components/
├── CrypToadCore/                  # Swift package (no UI)
│   ├── Sources/CrypToadCore/
│   │   ├── Money.swift            # Decimal helpers
│   │   ├── RoundUp.swift
│   │   ├── Allocation.swift       # Splitting + slider rebalancing
│   │   ├── PortfolioState.swift   # Ledger: purchases, DCA, trades, valuation
│   │   ├── Trading.swift          # Quotes + fees
│   │   ├── Prices.swift / CoinGeckoPriceService.swift
│   │   └── Persistence.swift
│   └── Tests/CrypToadCoreTests/
├── backend/                       # FastAPI + PostgreSQL
├── docs/                          # Architecture, API spec, security, roadmap
├── scripts/screenshot.sh
└── project.yml                    # XcodeGen spec
```

## How Round-Ups Work

1. You buy a coffee for **$4.25** with the CrypToad card.
2. The purchase rounds up to **$5.00**.
3. The **$0.75** difference is split by your allocation: 50/30/20 → $0.38 BTC, $0.22 ETH, $0.15 USDC.
4. The BTC and ETH shares are bought at the current price (e.g. $0.38 ÷ $92,340 = 0.00000411 BTC).
5. In production, round-ups would be batched daily or weekly to reduce fees.

## Documentation

- [Architecture](docs/architecture.md)
- [API Specification](docs/api-spec.md) · [Backend README](backend/README.md)
- [Security Design](docs/security.md)
- [Roadmap](docs/roadmap.md)

## Disclaimer

CrypToad is a personal/educational project. It is not a licensed financial
product, does not hold or move real funds, and nothing in it is financial
advice. A production version would require money transmitter licensing,
KYC/AML compliance, and partnerships with a licensed card issuer and crypto
custodian. Price data provided by [CoinGecko](https://www.coingecko.com).

## Author

**Ali** — Computer Science @ UT Dallas
GitHub: [@Sardeen07](https://github.com/Sardeen07)

## License

[MIT](LICENSE)
