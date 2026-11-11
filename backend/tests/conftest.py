import hashlib
import time
from decimal import Decimal

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient
from sqlalchemy.pool import StaticPool

from app.apple import AppleIdentityVerifier
from app.assets import Asset
from app.config import Settings
from app.db import Database
from app.main import create_app
from app.pricing import StaticPriceProvider

# Round prices so expected quantities are easy to check by hand.
PRICES = StaticPriceProvider({Asset.BTC: Decimal("50000"), Asset.ETH: Decimal("2500"), Asset.USDC: Decimal("1")})


@pytest.fixture
def settings() -> Settings:
    return Settings(database_url="sqlite://", enable_dev_endpoints=True, price_source="static", _env_file=None)


@pytest.fixture
def database() -> Database:
    # One shared in-memory SQLite connection per test.
    db = Database("sqlite://", poolclass=StaticPool)
    db.create_all()
    return db


# A local RSA key stands in for Apple's signing key, so Sign in with Apple is tested end to end offline.
APPLE_TEST_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
APP_BUNDLE_ID = "com.sardeen07.cryptoad"


def apple_token(sub: str = "001234.apple-user", nonce: str | None = "raw-nonce", **overrides) -> str:
    now = int(time.time())
    claims = {
        "iss": "https://appleid.apple.com",
        "aud": APP_BUNDLE_ID,
        "sub": sub,
        "iat": now,
        "exp": now + 600,
        "email": "toad@privaterelay.appleid.com",
        "email_verified": "true",
    }
    if nonce is not None:
        claims["nonce"] = hashlib.sha256(nonce.encode()).hexdigest()
    claims.update(overrides)
    return jwt.encode(claims, APPLE_TEST_KEY, algorithm="RS256", headers={"kid": "test"})


@pytest.fixture
def apple_verifier() -> AppleIdentityVerifier:
    return AppleIdentityVerifier([APP_BUNDLE_ID], signing_key_for=lambda _token: APPLE_TEST_KEY.public_key())


@pytest.fixture
def client(settings: Settings, database: Database, apple_verifier: AppleIdentityVerifier) -> TestClient:
    return TestClient(create_app(settings=settings, database=database, prices=PRICES, apple_verifier=apple_verifier))


def make_user(client: TestClient, email: str = "ali@example.com", deposit: str | None = "1000", kyc_status: str = "verified") -> dict:
    """Creates a user (optionally funded) and returns auth headers."""
    response = client.post("/api/dev/users", json={"email": email, "kycStatus": kyc_status})
    assert response.status_code == 201, response.text
    headers = {"Authorization": f"Bearer {response.json()['token']}"}
    if deposit:
        assert client.post("/api/dev/deposit", json={"amount": deposit}, headers=headers).status_code == 200
    return headers


@pytest.fixture
def auth(client: TestClient) -> dict:
    return make_user(client)
