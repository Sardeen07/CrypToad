import json
from datetime import date, timedelta

import httpx
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select

from app.config import Settings
from app.db import Database
from app.main import create_app
from app.models import BankLink
from app.plaid import HOSTS, PlaidClient
from tests.conftest import PRICES, make_user

TODAY = date.today()


def txn(tid: str, amount: float, days_ago: int = 0, name: str = "Store", pending: bool = False, currency: str = "USD") -> dict:
    return {
        "transaction_id": tid,
        "amount": amount,
        "date": (TODAY - timedelta(days=days_ago)).isoformat(),
        "merchant_name": name,
        "name": name.upper(),
        "pending": pending,
        "iso_currency_code": currency,
    }


PAGES = {
    None: {
        "added": [
            txn("t1", 4.25, name="Starbucks"),
            txn("t2", -20.00, name="Refund"),  # money in: not a purchase
            txn("t3", 3.10, pending=True),  # not settled yet
            txn("t4", 9.99, days_ago=60),  # before the round-up window
        ],
        "next_cursor": "c1",
        "has_more": True,
        "transactions_update_status": "HISTORICAL_UPDATE_COMPLETE",
    },
    "c1": {
        "added": [txn("t5", 12.40, days_ago=1, name="Uber"), txn("t6", 30.00, name="Whole Foods"), txn("t7", 8.50, currency="EUR")],
        "next_cursor": "c2",
        "has_more": False,
        "transactions_update_status": "HISTORICAL_UPDATE_COMPLETE",
    },
    "c2": {"added": [], "next_cursor": "c2", "has_more": False, "transactions_update_status": "HISTORICAL_UPDATE_COMPLETE"},
}


class FakePlaid:
    """Answers the Plaid endpoints CrypToad uses, and checks every request is authenticated."""

    def __init__(self) -> None:
        self.calls: list[str] = []

    def __call__(self, request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content)
        assert body["client_id"] == "test-client" and body["secret"] == "test-secret"
        path = request.url.path
        self.calls.append(path)
        if path == "/sandbox/public_token/create":
            assert body["institution_id"] == "ins_109508"
            return httpx.Response(200, json={"public_token": "public-sandbox-1"})
        if path == "/item/public_token/exchange":
            return httpx.Response(200, json={"access_token": "access-sandbox-secret", "item_id": "item-1"})
        if path == "/transactions/sync":
            assert body["access_token"] == "access-sandbox-secret"
            return httpx.Response(200, json=PAGES[body.get("cursor")])
        if path == "/link/token/create":
            assert body["user"]["client_user_id"]
            return httpx.Response(200, json={"link_token": "link-sandbox-1"})
        if path == "/item/remove":
            return httpx.Response(200, json={})
        return httpx.Response(400, json={"error_code": "UNKNOWN_PATH", "error_message": path})


@pytest.fixture
def fake_plaid() -> FakePlaid:
    return FakePlaid()


@pytest.fixture
def bank_client(database: Database, apple_verifier, fake_plaid: FakePlaid) -> TestClient:
    settings = Settings(database_url="sqlite://", price_source="static", secret_key="test-secret-key", _env_file=None)
    http = httpx.Client(base_url=HOSTS["sandbox"], transport=httpx.MockTransport(fake_plaid))
    plaid = PlaidClient("test-client", "test-secret", "sandbox", http=http)
    return TestClient(create_app(settings=settings, database=database, prices=PRICES, apple_verifier=apple_verifier, plaid=plaid))


def test_bank_linking_is_unavailable_without_plaid_keys(client: TestClient, auth: dict) -> None:
    assert client.get("/api/bank", headers=auth).json()["available"] is False
    response = client.post("/api/bank/sandbox-link", headers=auth)
    assert response.status_code == 503
    assert response.json()["error"] == "bank_linking_unavailable"


def test_sandbox_link_stores_the_access_token_encrypted(bank_client: TestClient, database: Database) -> None:
    auth = make_user(bank_client)
    response = bank_client.post("/api/bank/sandbox-link", headers=auth)
    assert response.status_code == 200, response.text
    assert response.json()["linked"] is True
    assert response.json()["institutionName"] == "First Platypus Bank (Sandbox)"
    with database.session_factory() as session:
        stored = session.scalars(select(BankLink)).one().access_token
    assert stored.startswith("enc:") and "access-sandbox-secret" not in stored


def test_sync_rounds_up_new_settled_purchases_once(bank_client: TestClient, fake_plaid: FakePlaid) -> None:
    auth = make_user(bank_client)
    bank_client.post("/api/bank/sandbox-link", headers=auth)

    result = bank_client.post("/api/bank/sync", headers=auth).json()
    # t1 ($4.25 → $0.75) and t5 ($12.40 → $0.60) round up; t6 ($30.00) is recorded with no round-up.
    assert result == {"status": "HISTORICAL_UPDATE_COMPLETE", "added": 3, "roundedUp": 2, "skipped": 0, "totalRoundUp": "1.35"}
    # Bank purchases only move the spare change, and the 20% USDC share of it stays put:
    # $0.75 → $0.38 BTC + $0.22 ETH, $0.60 → $0.30 BTC + $0.18 ETH, so $1.08 leaves the USDC wallet.
    balances = bank_client.get("/api/balances", headers=auth).json()["balances"]
    assert balances["USDC"] == "998.92"

    activity = bank_client.get("/api/activity", headers=auth).json()["activity"]
    purchases = [a for a in activity if a["kind"] == "purchase"]
    assert {(p["title"], p["roundUp"], p["source"]) for p in purchases} == {
        ("Starbucks", "0.75", "bank"), ("Uber", "0.60", "bank"), ("Whole Foods", "0.00", "bank"),
    }

    # Syncing again picks up from the saved cursor: nothing new, nothing doubled.
    assert bank_client.post("/api/bank/sync", headers=auth).json()["added"] == 0
    assert bank_client.get("/api/balances", headers=auth).json()["balances"]["USDC"] == "998.92"


def test_replayed_transactions_are_never_rounded_up_twice(bank_client: TestClient, database: Database) -> None:
    auth = make_user(bank_client)
    bank_client.post("/api/bank/sandbox-link", headers=auth)
    bank_client.post("/api/bank/sync", headers=auth)
    with database.session_factory() as session:
        session.scalars(select(BankLink)).one().cursor = None  # simulate Plaid replaying history
        session.commit()
    assert bank_client.post("/api/bank/sync", headers=auth).json()["added"] == 0


def test_round_ups_that_dont_fit_are_skipped_not_failed(bank_client: TestClient) -> None:
    auth = make_user(bank_client, deposit="0.50")
    bank_client.post("/api/bank/sandbox-link", headers=auth)
    result = bank_client.post("/api/bank/sync", headers=auth).json()
    assert (result["roundedUp"], result["skipped"]) == (1, 1)  # $0.60 of crypto didn't fit, then $0.48 did
    skipped = [a for a in bank_client.get("/api/activity", headers=auth).json()["activity"] if a["status"] == "skipped"]
    assert [s["title"] for s in skipped] == ["Starbucks"]


def test_sync_requires_a_linked_bank(bank_client: TestClient) -> None:
    auth = make_user(bank_client)
    response = bank_client.post("/api/bank/sync", headers=auth)
    assert response.status_code == 409
    assert response.json()["error"] == "bank_not_linked"


def test_link_token_and_unlink(bank_client: TestClient, fake_plaid: FakePlaid) -> None:
    auth = make_user(bank_client)
    assert bank_client.post("/api/bank/link-token", headers=auth).json()["linkToken"] == "link-sandbox-1"
    bank_client.post("/api/bank/sandbox-link", headers=auth)
    assert bank_client.delete("/api/bank", headers=auth).status_code == 204
    assert bank_client.get("/api/bank", headers=auth).json()["linked"] is False
    assert "/item/remove" in fake_plaid.calls


def test_plaid_errors_surface_cleanly(database: Database, apple_verifier) -> None:
    def failing(_: httpx.Request) -> httpx.Response:
        return httpx.Response(400, json={"error_code": "INVALID_API_KEYS", "error_message": "invalid client_id or secret"})

    plaid = PlaidClient("bad", "bad", "sandbox", http=httpx.Client(base_url=HOSTS["sandbox"], transport=httpx.MockTransport(failing)))
    settings = Settings(database_url="sqlite://", price_source="static", _env_file=None)
    client = TestClient(create_app(settings=settings, database=database, prices=PRICES, apple_verifier=apple_verifier, plaid=plaid))
    response = client.post("/api/bank/sandbox-link", headers=make_user(client))
    assert response.status_code == 502
    assert response.json() == {"error": "bank_provider_error", "detail": "Plaid INVALID_API_KEYS: invalid client_id or secret"}
