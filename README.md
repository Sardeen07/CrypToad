<div align="center">

# 🐸 CrypToad

**A crypto-linked debit card app concept — turn paychecks into crypto, spend it anywhere, and invest your spare change.**

![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)
![SwiftUI](https://img.shields.io/badge/SwiftUI-iOS%2017-blue?logo=apple)
![Status](https://img.shields.io/badge/status-prototype-yellow)
![License](https://img.shields.io/badge/license-MIT-green)

</div>

---

## Overview

CrypToad is an iOS app concept that connects everyday spending with
cryptocurrency investing. The idea: your paycheck lands in USDC (a
dollar-pegged stablecoin), you spend it with a debit card that converts
crypto to fiat at checkout, and every purchase is rounded up with the spare
change invested into BTC, ETH, or USDC.

This repository contains a **working SwiftUI prototype** of the core user
experience, plus the product design, API spec, and security architecture
for the full platform.

> ⚠️ **Prototype status:** The app runs on mock data. There is no backend,
> no real card, no real crypto, and no bank connection yet. See
> [What's built vs. planned](#whats-built-vs-planned).

## Screenshots

| Home | Round-Ups | Invest (DCA) | Card |
|:---:|:---:|:---:|:---:|
| ![Home](docs/screenshots/home.png) | ![Round-Ups](docs/screenshots/roundup.png) | ![DCA](docs/screenshots/dca.png) | ![Card](docs/screenshots/card.png) |

## Features

### Built (prototype)

- **Portfolio dashboard** — total portfolio value and holdings for USDC, BTC, and ETH, calculated from balances and prices
- **Round-up investing** — simulate a card purchase and watch the spare change get calculated and added to your round-up total
- **Round-up controls** — enable/pause toggle, allocation breakdown (BTC / ETH / USDC), and round-up history
- **Dollar-cost averaging (DCA)** — recurring investment settings with preset strategies (Balanced Growth, Aggressive Bitcoin, Stablecoin Saver)
- **Debit card screen** — card design with Apple Wallet, freeze, and PIN controls (UI only)
- **Transaction history** — purchases, paycheck deposits, DCA buys, and P2P transfers

### Planned

- Payroll direct-deposit conversion into USDC
- Real-time crypto → fiat conversion at checkout
- Apple Wallet provisioning via PassKit
- Peer-to-peer crypto transfers
- USDC → BTC/ETH trading through a liquidity provider
- Secure authentication with MFA and Face ID
- Backend API with a double-entry ledger

## What's built vs. planned

| Area | Status |
|---|---|
| SwiftUI app shell, navigation, all screens | ✅ Built |
| Round-up calculation logic | ✅ Built (local, mock data) |
| Portfolio valuation | ✅ Built (static prices) |
| Live market prices | 🔲 Planned |
| Backend API + PostgreSQL ledger | 🔲 Planned — see [`docs/api-spec.md`](docs/api-spec.md) |
| Authentication, MFA, biometrics | 🔲 Planned — see [`docs/security.md`](docs/security.md) |
| Card issuing, bank linking, crypto custody | 🔲 Planned — requires licensed partners |

## Tech Stack

**Current:** Swift, SwiftUI, iOS 17

**Planned:** PostgreSQL (double-entry ledger), Redis (quote caching and job queue), Firebase / APNs (push notifications), PassKit (Apple Wallet), Plaid (bank linking), a crypto liquidity/custody provider, and a card-issuing partner.

## Getting Started

### Requirements

- macOS with **Xcode 15** or later
- iOS 17 simulator or device

### Option A — XcodeGen (recommended)

```bash
brew install xcodegen
git clone https://github.com/Sardeen07/CrypToad.git
cd CrypToad
xcodegen generate
open CrypToad.xcodeproj
```

Then pick an iPhone simulator and press **⌘R**.

### Option B — Manual

1. In Xcode, create a new **iOS App** project named `CrypToad` (SwiftUI interface).
2. Delete the generated `ContentView.swift` and `CrypToadApp.swift`.
3. Drag the `CrypToad/` source folder from this repo into the project.
4. Build and run.

### Try it

On the Home tab, tap **Simulate Purchase**. A random purchase is added to
your activity, the round-up is calculated (e.g. $4.25 → $0.75), and your
round-up total updates.

## Project Structure

```
CrypToad/
├── CrypToad/
│   ├── App/
│   │   └── CrypToadApp.swift          # App entry point
│   ├── Models/
│   │   ├── Balance.swift
│   │   ├── Transaction.swift
│   │   └── DCASettings.swift
│   └── Views/
│       ├── ContentView.swift          # Root state + screen routing
│       ├── Screens/
│       │   ├── HomeView.swift
│       │   ├── RoundUpView.swift
│       │   ├── DCAView.swift
│       │   ├── CardView.swift
│       │   └── TransactionHistoryView.swift
│       └── Components/
│           ├── HeaderView.swift
│           ├── BottomNavView.swift
│           ├── BalanceRow.swift
│           ├── TransactionRow.swift
│           ├── AllocationBar.swift
│           ├── StrategyCard.swift
│           └── SettingsButton.swift
├── docs/
│   ├── architecture.md                # Planned system design
│   ├── api-spec.md                    # Planned trading API
│   ├── security.md                    # Planned auth + data security
│   ├── roadmap.md                     # MVP phases
│   └── screenshots/
├── project.yml                        # XcodeGen spec
├── SECURITY.md
└── LICENSE
```

## How Round-Ups Work

1. User buys a coffee for **$4.25** with the CrypToad card.
2. The purchase rounds up to **$5.00**.
3. The **$0.75** difference is set aside for investing.
4. It's split according to the user's allocation (e.g. 50% BTC / 30% ETH / 20% USDC).
5. In production, round-ups would be batched daily or weekly to reduce fees.

## Documentation

- [Architecture](docs/architecture.md)
- [API Specification](docs/api-spec.md)
- [Security Design](docs/security.md)
- [Roadmap](docs/roadmap.md)

## Roadmap

- [x] SwiftUI prototype of core screens
- [x] Local round-up calculation
- [ ] Refactor state into an `ObservableObject` view model
- [ ] Live prices from a public market-data API
- [ ] Editable allocation and DCA settings
- [ ] Backend API (quote, trade, history) with PostgreSQL ledger
- [ ] Authentication with Face ID
- [ ] Unit tests for round-up and allocation logic

## Disclaimer

CrypToad is a personal/educational project. It is not a licensed financial
product, does not hold or move real funds, and nothing in it is financial
advice. A production version would require money transmitter licensing,
KYC/AML compliance, and partnerships with a licensed card issuer and crypto
custodian.

## Author

**Ali** — Computer Science @ UT Dallas
GitHub: [@Sardeen07](https://github.com/Sardeen07)

## License

[MIT](LICENSE)
