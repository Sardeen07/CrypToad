# Roadmap

## Personal project milestones

- [x] SwiftUI prototype: home, round-ups, DCA, card, history
- [x] Local round-up calculation with simulated purchases
- [ ] Move state into an `ObservableObject` view model
- [ ] Live prices from a public market-data API
- [ ] Editable allocation sliders and DCA settings
- [ ] Persist data locally (SwiftData)
- [ ] Unit tests for round-up and allocation math
- [ ] Backend prototype: quote / trade / history endpoints with a PostgreSQL ledger
- [ ] Sign-in with Face ID

## Full-platform MVP (would require a company + licensed partners)

**Phase 1 — Foundation:** compliance strategy (FinCEN MSB registration, state money transmitter licensing), partner selection, onboarding flow with bank-linking sandbox.

**Phase 2 — Core build:** bank linking, KYC, fiat → crypto conversion, DCA scheduler, round-up batching, USDC → BTC/ETH conversion.

**Phase 3 — Card + wallet:** debit card issuance through a program manager, Apple Wallet provisioning, real-time crypto → fiat conversion, fraud alerts, pilot testing.

**Phase 4 — Expansion:** P2P transfers, portfolio analytics, savings vaults, custom card designs, multi-currency and Layer-2 support.
