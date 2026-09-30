# Roadmap

## Personal project milestones

- [x] SwiftUI prototype: home, round-ups, DCA, card, history
- [x] Local round-up calculation with simulated purchases
- [x] Move state into an `@Observable` store backed by the CrypToadCore package
- [x] Live prices from a public market-data API
- [x] Editable allocation sliders and DCA settings
- [x] Persist data locally (JSON file store in CrypToadCore — testable on any platform)
- [x] Unit tests for round-up and allocation math
- [x] Backend prototype: quote / trade / history endpoints with a PostgreSQL ledger
- [x] Face ID app lock
- [x] Buy BTC/ETH with USDC (quote, 1% fee, confirm)
- [x] Scheduled DCA that catches up on missed buys
- [x] CI: core tests on Linux + macOS, iOS build, backend tests
- [ ] Connect the app to the backend API
- [ ] Portfolio chart (Swift Charts) from transaction history
- [ ] Home-screen widget with portfolio value
- [ ] Local notifications for DCA buys and round-up milestones
- [ ] Tax export (CSV of buys with cost basis)

## Full-platform MVP (would require a company + licensed partners)

**Phase 1 — Foundation:** compliance strategy (FinCEN MSB registration, state money transmitter licensing), partner selection, onboarding flow with bank-linking sandbox.

**Phase 2 — Core build:** bank linking, KYC, fiat → crypto conversion, DCA scheduler, round-up batching, USDC → BTC/ETH conversion.

**Phase 3 — Card + wallet:** debit card issuance through a program manager, Apple Wallet provisioning, real-time crypto → fiat conversion, fraud alerts, pilot testing.

**Phase 4 — Expansion:** P2P transfers, portfolio analytics, savings vaults, custom card designs, multi-currency and Layer-2 support.
