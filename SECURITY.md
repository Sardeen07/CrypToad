# Security Policy

CrypToad is a **prototype**. It does not handle real money, real
cryptocurrency, real card numbers, or real user accounts. Balances and
transactions are simulated; market prices are real (CoinGecko) but no
trades reach a real exchange.

## Reporting a vulnerability

If you find a security issue in this repository, please open a private
security advisory on GitHub (Security → Advisories → Report a vulnerability)
rather than a public issue.

## Planned security model

The intended production security design (Argon2id password hashing, MFA,
Secure Enclave biometrics, encryption at rest, audit logging) is documented
in [`docs/security.md`](docs/security.md). Implemented so far: the Face ID app
lock in the iOS app, and hashed API tokens, row locking, idempotency keys, and
an append-only audit log in the backend prototype.
