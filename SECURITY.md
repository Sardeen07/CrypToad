# Security Policy

CrypToad is currently a **UI prototype**. It does not handle real money, real
cryptocurrency, real card numbers, or real user accounts. All balances,
prices, and transactions in the app are mock data.

## Reporting a vulnerability

If you find a security issue in this repository, please open a private
security advisory on GitHub (Security → Advisories → Report a vulnerability)
rather than a public issue.

## Planned security model

The intended production security design (Argon2id password hashing, MFA,
Secure Enclave biometrics, encryption at rest, audit logging) is documented
in [`docs/security.md`](docs/security.md). None of it is implemented yet.
