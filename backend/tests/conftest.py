from decimal import Decimal

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.pool import StaticPool

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


@pytest.fixture
def client(settings: Settings, database: Database) -> TestClient:
    return TestClient(create_app(settings=settings, database=database, prices=PRICES))


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
