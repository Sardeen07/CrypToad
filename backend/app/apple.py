"""Sign in with Apple: verifying the identity token the iOS app receives.

The app gets a signed JWT from Apple and sends it here. We check that Apple
signed it (RS256, keys from Apple's JWKS endpoint), that it was issued for our
app's bundle ID, that it hasn't expired, and that it carries the nonce the app
generated for this sign-in, which stops a captured token from being replayed.
"""

import hashlib
from collections.abc import Callable
from dataclasses import dataclass
from typing import Any

import jwt

from app.errors import AuthError

APPLE_ISSUER = "https://appleid.apple.com"
APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys"


@dataclass(frozen=True)
class AppleIdentity:
    subject: str
    email: str | None
    email_verified: bool


class AppleIdentityVerifier:
    def __init__(self, audiences: list[str], signing_key_for: Callable[[str], Any] | None = None) -> None:
        self.audiences = audiences
        if signing_key_for is None:
            jwks = jwt.PyJWKClient(APPLE_JWKS_URL, cache_keys=True, lifespan=3600)
            signing_key_for = lambda token: jwks.get_signing_key_from_jwt(token).key  # noqa: E731
        self._signing_key_for = signing_key_for

    def verify(self, identity_token: str, raw_nonce: str | None = None) -> AppleIdentity:
        try:
            key = self._signing_key_for(identity_token)
            claims = jwt.decode(
                identity_token,
                key=key,
                algorithms=["RS256"],
                audience=self.audiences,
                issuer=APPLE_ISSUER,
                options={"require": ["exp", "iat", "sub", "aud", "iss"]},
            )
        except (jwt.PyJWTError, ValueError) as exc:
            raise AuthError(f"Apple sign-in failed: {exc}") from exc

        if raw_nonce is not None:
            expected = hashlib.sha256(raw_nonce.encode()).hexdigest()
            if claims.get("nonce") != expected:
                raise AuthError("Apple sign-in failed: nonce mismatch")

        email_verified = claims.get("email_verified") in (True, "true")
        return AppleIdentity(subject=str(claims["sub"]), email=claims.get("email"), email_verified=email_verified)
