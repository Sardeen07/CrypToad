# Security Design (Planned)

> Status: design document. Not implemented in the current prototype.

## Passwords
- Minimum 12 characters, mixed case, number, and symbol.
- Rejected if found in known breach lists (HaveIBeenPwned k-anonymity API).
- Hashed with **Argon2id**, unique salt per password. Never stored in plain text.
- Reset links expire in 10–15 minutes and require re-authentication.

## Multi-Factor Authentication
- **Primary:** authenticator app (TOTP), in-app push approval, Face ID / Touch ID.
- **Fallback:** SMS or email one-time codes (less secure).
- **Advanced:** FIDO2 / WebAuthn hardware keys.
- Biometric data is handled by the Secure Enclave and never sent to the server.

## Sessions
- Short-lived access tokens (15–30 minutes).
- Refresh tokens stored securely and rotated.
- Risk-based MFA on new device or IP.
- Account lockout after repeated failed attempts.

## Data Protection
- TLS 1.3 in transit, AES-256 at rest.
- Role-based access control for internal access.
- Secrets managed in KMS or Vault; never hard-coded.
- Every login, MFA challenge, reset, and trade written to an immutable audit log.

## Standards to follow
- NIST SP 800-63B (digital identity)
- PCI DSS (card data)
- SOC 2 (operational controls)
