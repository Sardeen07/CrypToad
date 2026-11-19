# CrypToad API

The CrypToad server: accounts (Sign in with Apple), round-ups, DCA buys, quote → trade, and Plaid
bank linking, all on top of a double-entry ledger. The iOS app uses it when signed in.

**Stack:** Python 3.12, FastAPI, SQLAlchemy 2, PostgreSQL (SQLite for tests), PyJWT, CoinGecko prices, Plaid.

> Upgrading from v0.2? The account tables changed and there are no migrations yet (prototype):
> run `docker compose down -v` (or delete `cryptoad.db`) once to start fresh.

## Run it

```bash
cd backend
docker compose up --build
open http://localhost:8000/docs      # interactive Swagger UI
```

Without Docker (uses a local SQLite file):

```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
uvicorn app.main:create_app --factory --reload
```

## Try the flow

```bash
B=http://localhost:8000
TOKEN=$(curl -s -X POST $B/api/auth/demo -H 'content-type: application/json' -d '{}' \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')   # comes with $1,000 USDC
H="Authorization: Bearer $TOKEN"

curl -s -X POST $B/api/dev/card-purchase -H "$H" -H 'content-type: application/json' \
  -d '{"merchant":"Starbucks","amount":"4.25"}'                         # pays $4.25, invests $0.75
curl -s -X POST $B/api/invest -H "$H" -H 'Idempotency-Key: dca-1' -H 'content-type: application/json' \
  -d '{"amount":"100","allocation":{"btc":50,"eth":30,"usdc":20}}'      # a DCA buy
curl -s "$B/api/trade/quote?from=USDC&to=BTC&amount=100" -H "$H"
curl -s -X POST $B/api/trade -H "$H" -H 'Idempotency-Key: my-first-trade' \
  -H 'content-type: application/json' -d '{"quoteId":"<quoteId from above>"}'
curl -s $B/api/activity -H "$H"
curl -s $B/api/balances -H "$H"
```

## Endpoints

| Method | Path | What it does |
|---|---|---|
| `POST` | `/api/auth/apple` | Sign in with Apple: verifies the identity token (signature, audience, expiry, nonce); creates the account on first sign-in |
| `POST` | `/api/auth/demo` | Creates a demo account with simulated USDC *(demo servers only)* |
| `POST` | `/api/auth/logout` | Revokes this device's session |
| `GET` / `DELETE` | `/api/me` | The signed-in user / delete the account (App Store requirement) |
| `GET` | `/api/balances` | USDC / BTC / ETH balances |
| `GET` | `/api/activity` | Deposits, purchases, trades, and DCA buys, newest first |
| `GET` / `PUT` | `/api/settings` | Round-up on/off, multiplier, allocation; card freeze |
| `POST` | `/api/invest` | A DCA buy split by allocation, `Idempotency-Key` supported |
| `GET` | `/api/trade/quote?from=USDC&to=BTC&amount=100` | Prices a conversion, adds the 1% fee, locks the rate for 45s |
| `POST` | `/api/trade` | Executes a quote (`{"quoteId": ...}`), optional `Idempotency-Key` header |
| `GET` | `/api/trade/history?limit=50` | The signed-in user's trades, newest first |
| `GET` | `/api/bank` | Bank link status |
| `POST` | `/api/bank/link-token` | A Plaid Link token (for the Link SDK) |
| `POST` | `/api/bank/exchange` | Finishes Plaid Link with its `public_token` |
| `POST` | `/api/bank/sandbox-link` | Links Plaid's test bank in one call *(Sandbox only)* |
| `POST` | `/api/bank/sync` | Pulls new bank transactions and rounds up each purchase once |
| `DELETE` | `/api/bank` | Unlinks the bank |
| `GET` | `/api/info` | Server version and which features are on |
| `POST` | `/api/dev/card-purchase` | Simulates a card swipe: pays the merchant, invests the round-up *(demo servers only)* |
| `POST` | `/api/dev/deposit` | Simulates a paycheck arriving as USDC *(demo servers only)* |
| `POST` | `/api/dev/users` | Creates a test user and returns a token *(demo servers only)* |

Errors come back as `{"error": "<code>", "detail": "<message>"}`:
`unsupported_pair`, `invalid_amount`, `invalid_allocation`, `insufficient_funds` (400),
`invalid_credentials` (401), `kyc_required`, `card_frozen` (403), `quote_not_found` (404),
`quote_already_used`, `bank_not_linked` (409), `quote_expired` (410), `bank_provider_error` (502),
`price_unavailable`, `bank_linking_unavailable` (503).

## Design notes

- **Double-entry ledger.** Every balance change is a journal entry whose postings sum to zero per
  asset. A $100 BTC buy debits the user's USDC wallet $100, credits fees $1 and the liquidity
  provider $99, debits the provider's BTC, and credits the user's BTC. Balances are sums of
  postings, so the history can always be replayed and audited. Tests assert the trial balance is zero.
- **Integer minor units.** Amounts are stored as integers (micro-USDC, satoshis), never floats.
  Prices and API amounts are decimal strings.
- **No double spending.** The paying wallet row is locked (`SELECT … FOR UPDATE`) during a trade,
  each quote can only be used once, and `Idempotency-Key` makes client retries safe.
- **Rate lock.** Quotes expire after 45 seconds (`CRYPTOAD_QUOTE_TTL_SECONDS`), so users trade at
  the price they saw or get a clear `quote_expired`.
- **Auth.** Sign in with Apple identity tokens are verified against Apple's public keys (RS256),
  our bundle ID, expiry, and a per-sign-in nonce. Each device then gets its own random bearer token;
  only SHA-256 hashes are stored, and signing out revokes just that device. Every query uses the
  token's user, never a `userId` parameter, so one user can't read another's data.
- **Round-ups.** Card swipes pay the merchant and invest the spare change in one journal entry, so
  either both happen or neither does. Bank purchases (Plaid) invest only the spare change, and each
  Plaid transaction id is recorded so a re-sync never rounds up twice. Round-ups that don't fit the
  USDC balance are recorded as skipped instead of failing the sync.
- **Plaid tokens encrypted at rest** with a key derived from `CRYPTOAD_SECRET_KEY` (Fernet).
- **Account deletion** removes personal data, sign-in methods, and bank links and revokes every
  session; ledger rows stay (anonymized) so the books still balance.
- **Compliance hooks.** KYC status gates trading, every trade writes an append-only audit event,
  and trades of $10,000+ are flagged for review.

The spec mentions Redis for quote caching; quotes live in Postgres here to keep the stack small.
Redis would be a drop-in addition once quote volume justifies it.

## Tests

```bash
pip install -r requirements-dev.txt
pytest
```

## Configuration

| Variable | Default |
|---|---|
| `CRYPTOAD_DATABASE_URL` | `sqlite:///./cryptoad.db` |
| `CRYPTOAD_PRICE_SOURCE` | `coingecko` (or `static` for fixed demo prices) |
| `CRYPTOAD_FEE_RATE` | `0.01` |
| `CRYPTOAD_QUOTE_TTL_SECONDS` | `45` |
| `CRYPTOAD_ENABLE_DEV_ENDPOINTS` | `true` — demo accounts and simulated swipes/paychecks; set `false` anywhere real |
| `CRYPTOAD_APPLE_AUDIENCES` | `com.sardeen07.cryptoad` (comma-separated bundle IDs) |
| `CRYPTOAD_SECRET_KEY` | unset — set to a long random string to encrypt Plaid tokens (required in production) |
| `CRYPTOAD_PLAID_CLIENT_ID` / `CRYPTOAD_PLAID_SECRET` | unset — bank linking is off until set |
| `CRYPTOAD_PLAID_ENV` | `sandbox` (or `production`) |
| `CRYPTOAD_PLAID_ROUNDUP_LOOKBACK_DAYS` | `7` — when a bank is linked, round up purchases this far back |

Put local values in `backend/.env` (see [`.env.example`](.env.example)); it's git-ignored.
