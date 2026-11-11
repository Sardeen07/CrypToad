from decimal import Decimal

import pytest
from fastapi.testclient import TestClient

from app import ledger
from app.db import Database
from app.investing import Allocation, split, spare_change
from tests.conftest import make_user


def balances(client: TestClient, auth: dict) -> dict:
    return client.get("/api/balances", headers=auth).json()["balances"]


def swipe(client: TestClient, auth: dict, amount: str, merchant: str = "Starbucks"):
    return client.post("/api/dev/card-purchase", json={"merchant": merchant, "amount": amount}, headers=auth)


def put_settings(client: TestClient, auth: dict, *, enabled=True, multiplier=1, alloc=(50, 30, 20), frozen=False):
    return client.put(
        "/api/settings",
        json={
            "roundUps": {"enabled": enabled, "multiplier": multiplier, "allocation": dict(zip(("btc", "eth", "usdc"), alloc, strict=True))},
            "cardFrozen": frozen,
        },
        headers=auth,
    )


def assert_books_balance(database: Database) -> None:
    with database.session_factory() as session:
        assert all(total == 0 for total in ledger.trial_balance(session).values())


# MARK: Math (mirrors CrypToadCore's RoundUp and Allocation tests)


@pytest.mark.parametrize(
    ("amount", "multiplier", "expected"),
    [("4.25", 1, "0.75"), ("47.89", 1, "0.11"), ("5.00", 1, "0.00"), ("4.25", 2, "1.50"), ("0.01", 1, "0.99")],
)
def test_spare_change(amount: str, multiplier: int, expected: str) -> None:
    assert spare_change(Decimal(amount), multiplier) == Decimal(expected)


def test_split_never_loses_a_cent() -> None:
    allocation = Allocation(50, 30, 20)
    for cents in range(1, 5000):
        amount = Decimal(cents) / 100
        assert sum(split(amount, allocation).values()) == amount
    shares = split(Decimal("0.75"), allocation)
    assert [str(shares[a]) for a in shares] == ["0.38", "0.22", "0.15"]


# MARK: Card purchases


def test_card_purchase_pays_merchant_and_invests_round_up(client: TestClient, auth: dict, database: Database) -> None:
    response = swipe(client, auth, "4.25")
    assert response.status_code == 201, response.text
    body = response.json()
    assert body["kind"] == "purchase"
    assert body["source"] == "card"
    assert body["amount"] == "4.25"
    assert body["roundUp"] == "0.75"
    fills = {f["asset"]: f for f in body["fills"]}
    # $0.75 split 50/30/20 → $0.38 BTC at $50,000, $0.22 ETH at $2,500, $0.15 stays USDC
    assert fills["BTC"]["cost"] == "0.38" and fills["BTC"]["quantity"] == "0.0000076"
    assert fills["ETH"]["cost"] == "0.22" and fills["ETH"]["quantity"] == "0.000088"
    assert fills["USDC"]["cost"] == "0.15"

    assert balances(client, auth) == {"USDC": "995.15", "BTC": "0.0000076", "ETH": "0.000088"}
    assert_books_balance(database)


def test_multiplier_and_allocation_come_from_settings(client: TestClient, auth: dict) -> None:
    assert put_settings(client, auth, multiplier=2, alloc=(100, 0, 0)).status_code == 200
    body = swipe(client, auth, "4.25").json()
    assert body["roundUp"] == "1.50"
    assert [(f["asset"], f["cost"]) for f in body["fills"]] == [("BTC", "1.50")]


def test_round_ups_can_be_turned_off(client: TestClient, auth: dict) -> None:
    put_settings(client, auth, enabled=False)
    body = swipe(client, auth, "4.25").json()
    assert body["roundUp"] == "0.00" and body["fills"] == []
    assert balances(client, auth)["USDC"] == "995.75"


def test_frozen_card_declines_and_changes_nothing(client: TestClient, auth: dict) -> None:
    put_settings(client, auth, frozen=True)
    response = swipe(client, auth, "4.25")
    assert response.status_code == 403
    assert response.json()["error"] == "card_frozen"
    assert balances(client, auth)["USDC"] == "1000.00"


def test_purchase_plus_round_up_must_fit_the_balance(client: TestClient, database: Database) -> None:
    auth = make_user(client, deposit="4.30")
    response = swipe(client, auth, "4.25")  # needs $5.00 with the round-up
    assert response.status_code == 400
    assert response.json()["error"] == "insufficient_funds"
    assert balances(client, auth)["USDC"] == "4.30"
    assert_books_balance(database)


def test_settings_validate_allocation(client: TestClient, auth: dict) -> None:
    response = put_settings(client, auth, alloc=(50, 30, 30))
    assert response.status_code == 400
    assert response.json()["error"] == "invalid_allocation"
    assert client.get("/api/settings", headers=auth).json()["roundUps"]["allocation"] == {"btc": 50, "eth": 30, "usdc": 20}


# MARK: DCA


def invest(client: TestClient, auth: dict, amount: str = "100", alloc=(50, 30, 20), key: str | None = None):
    headers = {**auth, **({"Idempotency-Key": key} if key else {})}
    return client.post(
        "/api/invest", json={"amount": amount, "allocation": dict(zip(("btc", "eth", "usdc"), alloc, strict=True))}, headers=headers
    )


def test_dca_buy_splits_by_allocation(client: TestClient, auth: dict, database: Database) -> None:
    response = invest(client, auth)
    assert response.status_code == 201, response.text
    assert response.json()["kind"] == "dcaBuy"
    assert balances(client, auth) == {"USDC": "920.00", "BTC": "0.001", "ETH": "0.012"}
    assert_books_balance(database)


def test_dca_idempotency_key_prevents_double_buys(client: TestClient, auth: dict) -> None:
    first = invest(client, auth, key="dca-2026-11-11T09:00:00Z")
    again = invest(client, auth, key="dca-2026-11-11T09:00:00Z")
    assert first.status_code == 201 and again.status_code == 200
    assert first.json()["id"] == again.json()["id"]
    assert balances(client, auth)["USDC"] == "920.00"


def test_dca_needs_funds_even_for_all_usdc(client: TestClient) -> None:
    auth = make_user(client, deposit="50")
    assert invest(client, auth, "100", alloc=(0, 0, 100)).json()["error"] == "insufficient_funds"
    assert invest(client, auth, "100").json()["error"] == "insufficient_funds"
    assert invest(client, auth, "50", alloc=(0, 0, 100)).status_code == 201


def test_dca_rejects_bad_allocations(client: TestClient, auth: dict) -> None:
    assert invest(client, auth, alloc=(60, 60, 0)).json()["error"] == "invalid_allocation"


# MARK: Activity


def test_activity_merges_everything_newest_first(client: TestClient, auth: dict) -> None:
    swipe(client, auth, "4.25")
    invest(client, auth, "10")
    quote = client.get("/api/trade/quote", params={"from": "USDC", "to": "ETH", "amount": "25"}, headers=auth).json()
    client.post("/api/trade", json={"quoteId": quote["quoteId"]}, headers=auth)

    activity = client.get("/api/activity", headers=auth).json()["activity"]
    assert [a["kind"] for a in activity] == ["trade", "dcaBuy", "purchase", "deposit"]
    trade = activity[0]
    assert trade["title"] == "Bought Ethereum" and trade["fee"] == "0.25" and trade["fills"][0]["asset"] == "ETH"


def test_activity_is_private(client: TestClient, auth: dict) -> None:
    swipe(client, auth, "4.25")
    other = make_user(client, email="other@example.com", deposit=None)
    assert client.get("/api/activity", headers=other).json()["activity"] == []
