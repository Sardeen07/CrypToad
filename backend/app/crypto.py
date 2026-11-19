"""Encryption at rest for third-party secrets (Plaid access tokens).

A Plaid access token can read someone's bank transactions, so it is never stored
in plain text when ``CRYPTOAD_SECRET_KEY`` is set. Production would use a KMS
(see docs/security.md); Fernet (AES-128-CBC + HMAC-SHA256) keyed from an
environment secret is the self-hosted equivalent.
"""

import base64
import hashlib
import logging

from cryptography.fernet import Fernet

log = logging.getLogger(__name__)

_ENCRYPTED = "enc:"
_PLAIN = "plain:"


class SecretBox:
    def __init__(self, secret_key: str | None) -> None:
        if secret_key:
            # Derive a valid 32-byte Fernet key from any secret string.
            key = base64.urlsafe_b64encode(hashlib.sha256(secret_key.encode()).digest())
            self._fernet: Fernet | None = Fernet(key)
        else:
            self._fernet = None
            log.warning("CRYPTOAD_SECRET_KEY is not set: bank tokens are stored unencrypted (development only).")

    def seal(self, value: str) -> str:
        if self._fernet is None:
            return _PLAIN + value
        return _ENCRYPTED + self._fernet.encrypt(value.encode()).decode()

    def open(self, stored: str) -> str:
        if stored.startswith(_PLAIN):
            return stored[len(_PLAIN) :]
        if not stored.startswith(_ENCRYPTED) or self._fernet is None:
            raise ValueError("Stored secret can't be decrypted with the current CRYPTOAD_SECRET_KEY")
        return self._fernet.decrypt(stored[len(_ENCRYPTED) :].encode()).decode()
