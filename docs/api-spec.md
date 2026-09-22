# Trading API Specification (Planned)

> Status: design document. Not implemented.

All endpoints require an authenticated session (short-lived JWT).

---

## `GET /api/trade/quote`

Get a conversion quote.

**Query params:** `from` (must be `USDC`), `to` (`BTC` | `ETH`), `amount`

**Logic**
1. Validate that `from` is USDC and `to` is a supported asset.
2. Fetch the current rate from the liquidity provider.
3. Add conversion fee and network fee.
4. Cache the quote in Redis for 30–60 seconds.
5. Return the quote.

**Example response**
```json
{
  "quoteId": "q_8f2a1c",
  "from": "USDC",
  "to": "BTC",
  "amount": 100.00,
  "rate": 92340.00,
  "fee": 1.00,
  "estimatedReceive": 0.00107213,
  "expiresAt": "2026-01-01T12:00:60Z"
}
```

---

## `POST /api/trade`

Execute a trade from a quote.

**Body**
```json
{ "quoteId": "q_8f2a1c" }
```

**Logic**
1. Validate the user (KYC complete, account active).
2. Confirm sufficient USDC balance.
3. Lock the USDC amount to prevent double spending.
4. Execute the trade via the liquidity provider.
   - Success → credit crypto to the user's balance.
   - Failure → release the lock, return an error.
5. Record the trade in PostgreSQL.
6. Push a confirmation notification.
7. Write an audit log entry.

**Example response**
```json
{
  "tradeId": "t_4b91e0",
  "status": "completed",
  "fromAsset": "USDC",
  "toAsset": "BTC",
  "amount": 100.00,
  "cryptoReceived": 0.00107213,
  "timestamp": "2026-01-01T12:00:12Z"
}
```

---

## `GET /api/trade/history`

Return the authenticated user's trade history. Users can only read their own
history; the user is taken from the session, not a query parameter.

**Example response**
```json
{
  "trades": [
    {
      "tradeId": "t_4b91e0",
      "fromAsset": "USDC",
      "toAsset": "BTC",
      "amount": 100.00,
      "cryptoReceived": 0.00107213,
      "status": "completed",
      "timestamp": "2026-01-01T12:00:12Z"
    }
  ]
}
```
