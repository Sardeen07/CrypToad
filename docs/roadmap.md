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
- [x] Connect the app to the backend API (server mode, synced balances and history)
- [x] Accounts: Sign in with Apple, demo accounts, per-device sessions, account deletion
- [x] Server-side round-ups, DCA buys, card swipes, and a unified activity feed
- [x] Bank linking with Plaid (Sandbox) and Acorns-style round-ups of bank purchases
- [x] One-click backend deploy (Render Blueprint)
- [x] End-to-end UI test (XCUITest) against a running backend
- [ ] Plaid Link SDK in the app (link real banks instead of the Sandbox test bank)
- [ ] Database migrations (Alembic) and backend tests against PostgreSQL in CI
- [ ] TestFlight build
- [ ] Portfolio chart (Swift Charts) from transaction history
- [ ] Home-screen widget with portfolio value
- [ ] Local notifications for DCA buys and round-up milestones
- [ ] Tax export (CSV of buys with cost basis)

## Full-platform MVP (would require a company + licensed partners)

**Phase 1 — Foundation:** compliance strategy (FinCEN MSB registration, state money transmitter licensing), partner selection, onboarding flow with bank-linking sandbox.

**Phase 2 — Core build:** bank linking, KYC, fiat → crypto conversion, DCA scheduler, round-up batching, USDC → BTC/ETH conversion.

**Phase 3 — Card + wallet:** debit card issuance through a program manager, Apple Wallet provisioning, real-time crypto → fiat conversion, fraud alerts, pilot testing.

**Phase 4 — Expansion:** P2P transfers, portfolio analytics, savings vaults, custom card designs, multi-currency and Layer-2 support.
