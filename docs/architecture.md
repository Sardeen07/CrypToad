# Architecture (Planned)

> Status: design document. The current repository contains only the iOS
> client prototype with mock data. Everything below describes the intended
> production system.

## System Overview

```
┌──────────────┐     HTTPS/TLS 1.3     ┌─────────────────────┐
│  iOS App     │ ────────────────────▶ │  Backend API        │
│  (SwiftUI)   │ ◀──────────────────── │                     │
└──────┬───────┘   push (APNs/FCM)     └──┬──────┬──────┬────┘
       │                                  │      │      │
       │ PassKit                          ▼      ▼      ▼
       ▼                            PostgreSQL  Redis  Partner APIs
  Apple Wallet                       (ledger)  (cache,  (bank linking,
                                               queue)   custody, card
                                                        issuing, KYC)
```

## Backend Service Layers

| Layer | Responsibility |
|---|---|
| **Validation** | KYC status check, balance check against the ledger, asset whitelist (USDC → BTC/ETH) |
| **Trading** | Wrapper around the liquidity provider API, retry via Redis queue, 30–60s rate lock after a quote |
| **Ledger** | Double-entry accounting: debit USDC, credit BTC/ETH, every movement balanced |
| **Notification** | Push confirmations (APNs/Firebase), email receipts |
| **Compliance** | Immutable audit log, suspicious-activity flags, tax report generation |

## Data Storage

| Data | Where |
|---|---|
| User profile, preferences, transaction history | PostgreSQL (encrypted at rest, AES-256) |
| Balances | Double-entry ledger in PostgreSQL |
| Password hashes | PostgreSQL (Argon2id, unique salts) |
| MFA secrets | KMS / HSM |
| Biometrics | Never leaves the device (Secure Enclave) |
| Crypto private keys | Custody provider HSMs — never in the app DB |
| Fiat balances | Card-issuing partner |
| Audit logs | Write-once object storage |
| API keys / secrets | KMS or Vault, injected via environment |

## Key Flows

### Round-Up
1. Card purchase authorized → backend receives transaction event.
2. Round-up = `ceil(amount) - amount`.
3. Round-up added to a pending batch for the user.
4. Batch executed daily/weekly according to user allocation.
5. Ledger updated, user notified.

### USDC → BTC Trade
1. Client requests quote → backend fetches rate, adds fees, caches quote.
2. Client confirms → backend validates KYC and balance.
3. USDC is locked → trade executed via liquidity provider.
4. On success, BTC credited; on failure, USDC released.
5. Transaction recorded, user notified, audit log written.
