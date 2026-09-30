# CrypToad API

Backend prototype for the trade flow in [`docs/api-spec.md`](../docs/api-spec.md):
quote → trade → history, on top of a double-entry ledger.

**Stack:** Python 3.12, FastAPI, SQLAlchemy 2, PostgreSQL (SQLite for tests), CoinGecko prices.

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
TOKEN=$(curl -s -X POST $B/api/dev/users -H 'content-type: application/json' \
  -d '{"email":"me@example.com"}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
H="Authorization: Bearer $TOKEN"

curl -s -X POST $B/api/dev/deposit -H "$H" -H 'content-type: application/json' -d '{"amount":"2500"}'
curl -s "$B/api/trade/quote?from=USDC&to=BTC&amount=100" -H "$H"
curl -s -X POST $B/api/trade -H "$H" -H 'Idempotency-Key: my-first-trade' \
  -H 'content-type: application/json' -d '{"quoteId":"<quoteId from above>"}'
curl -s $B/api/trade/history -H "$H"
curl -s $B/api/balances -H "$H"
```

## Endpoints

| Method | Path | What it does |
|---|---|---|
| `GET` | `/api/trade/quote?from=USDC&to=BTC&amount=100` | Prices a conversion, adds the 1% fee, locks the rate for 45s |
| `POST` | `/api/trade` | Executes a quote (`{"quoteId": ...}`), optional `Idempotency-Key` header |
| `GET` | `/api/trade/history?limit=50` | The signed-in user's trades, newest first |
| `GET` | `/api/balances` | USDC / BTC / ETH balances |
| `POST` | `/api/dev/users` | Creates a test user and returns a token *(dev only)* |
| `POST` | `/api/dev/deposit` | Simulates a paycheck arriving as USDC *(dev only)* |

Errors come back as `{"error": "<code>", "detail": "<message>"}`:
`unsupported_pair`, `invalid_amount` (400), `insufficient_funds` (400), `kyc_required` (403),
`quote_not_found` (404), `quote_already_used` (409), `quote_expired` (410), `price_unavailable` (503).

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
- **Auth.** Bearer tokens; only SHA-256 hashes are stored. History uses the token's user, never a
  `userId` parameter, so one user can't read another's trades.
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
| `CRYPTOAD_ENABLE_DEV_ENDPOINTS` | `true` — set `false` anywhere real |
