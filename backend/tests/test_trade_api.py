from datetime import timedelta

from fastapi.testclient import TestClient

from app import ledger
from app.db import Database
from app.models import AuditEvent, Quote
from tests.conftest import make_user


def quote(client: TestClient, auth: dict, amount: str = "100", to: str = "BTC") -> dict:
    response = client.get("/api/trade/quote", params={"from": "USDC", "to": to, "amount": amount}, headers=auth)
    assert response.status_code == 200, response.text
    return response.json()


def balances(client: TestClient, auth: dict) -> dict:
    return client.get("/api/balances", headers=auth).json()["balances"]


# MARK: Auth


def test_requires_auth(client: TestClient) -> None:
    assert client.get("/api/trade/history").status_code == 401
    assert client.get("/api/trade/history", headers={"Authorization": "Bearer nope"}).status_code == 401


# MARK: Quotes


def test_quote_math(client: TestClient, auth: dict) -> None:
    body = quote(client, auth, "100")
    # $100 − 1% fee = $99 converted at $50,000 → 0.00198 BTC
    assert body["amount"] == "100.00"
    assert body["fee"] == "1.00"
    assert body["netAmount"] == "99.00"
    assert body["rate"] == "50000.00"
    assert body["estimatedAmount"] == "0.00198"
    assert body["quoteId"]


def test_fee_rounds_up_to_the_cent(client: TestClient, auth: dict) -> None:
    assert quote(client, auth, "10.50", to="ETH")["fee"] == "0.11"


def test_unsupported_pairs_are_rejected(client: TestClient, auth: dict) -> None:
    for params in ({"from": "BTC", "to": "ETH"}, {"from": "USDC", "to": "USDC"}):
        response = client.get("/api/trade/quote", params={**params, "amount": "10"}, headers=auth)
        assert response.status_code == 400
        assert response.json()["error"] == "unsupported_pair"
    unknown = client.get("/api/trade/quote", params={"from": "USDC", "to": "DOGE", "amount": "10"}, headers=auth)
    assert unknown.status_code == 422


def test_minimum_amount(client: TestClient, auth: dict) -> None:
    response = client.get("/api/trade/quote", params={"from": "USDC", "to": "BTC", "amount": "0.50"}, headers=auth)
    assert response.status_code == 400
    assert response.json()["error"] == "invalid_amount"


# MARK: Trades


def test_trade_moves_balances_and_keeps_ledger_balanced(client: TestClient, auth: dict, database: Database) -> None:
    q = quote(client, auth, "100")
    response = client.post("/api/trade", json={"quoteId": q["quoteId"]}, headers=auth)
    assert response.status_code == 201, response.text
    trade = response.json()
    assert trade["cryptoReceived"] == "0.00198"
    assert trade["status"] == "completed"

    assert balances(client, auth) == {"USDC": "900.00", "BTC": "0.00198", "ETH": "0"}

    with database.session_factory() as session:
        # Every asset nets to zero across all accounts — money was moved, not created.
        assert all(total == 0 for total in ledger.trial_balance(session).values())


def test_quote_can_only_be_used_once(client: TestClient, auth: dict) -> None:
    q = quote(client, auth)
    assert client.post("/api/trade", json={"quoteId": q["quoteId"]}, headers=auth).status_code == 201
    again = client.post("/api/trade", json={"quoteId": q["quoteId"]}, headers=auth)
    assert again.status_code == 409
    assert again.json()["error"] == "quote_already_used"


def test_expired_quote_is_rejected(client: TestClient, auth: dict, database: Database) -> None:
    q = quote(client, auth)
    with database.session_factory() as session:
        stored = session.get(Quote, q["quoteId"])
        stored.expires_at = stored.expires_at - timedelta(minutes=5)
        session.commit()
    response = client.post("/api/trade", json={"quoteId": q["quoteId"]}, headers=auth)
    assert response.status_code == 410
    assert balances(client, auth)["USDC"] == "1000.00"


def test_cannot_use_someone_elses_quote(client: TestClient, auth: dict) -> None:
    q = quote(client, auth)
    other = make_user(client, "other@example.com")
    assert client.post("/api/trade", json={"quoteId": q["quoteId"]}, headers=other).status_code == 404


def test_insufficient_funds_changes_nothing(client: TestClient, database: Database) -> None:
    poor = make_user(client, "poor@example.com", deposit="50")
    q = quote(client, poor, "100")
    response = client.post("/api/trade", json={"quoteId": q["quoteId"]}, headers=poor)
    assert response.status_code == 400
    assert response.json()["error"] == "insufficient_funds"
    assert balances(client, poor) == {"USDC": "50.00", "BTC": "0", "ETH": "0"}
    # The quote wasn't consumed, so the user can top up and retry.
    client.post("/api/dev/deposit", json={"amount": "50"}, headers=poor)
    assert client.post("/api/trade", json={"quoteId": q["quoteId"]}, headers=poor).status_code == 201


def test_unverified_user_cannot_trade(client: TestClient) -> None:
    pending = make_user(client, "pending@example.com", kyc_status="pending")
    q = quote(client, pending)
    response = client.post("/api/trade", json={"quoteId": q["quoteId"]}, headers=pending)
    assert response.status_code == 403
    assert response.json()["error"] == "kyc_required"


def test_idempotency_key_prevents_double_spend(client: TestClient, auth: dict) -> None:
    q = quote(client, auth)
    headers = {**auth, "Idempotency-Key": "retry-123"}
    first = client.post("/api/trade", json={"quoteId": q["quoteId"]}, headers=headers)
    retry = client.post("/api/trade", json={"quoteId": q["quoteId"]}, headers=headers)
    assert first.status_code == 201
    assert retry.status_code == 200
    assert retry.json()["tradeId"] == first.json()["tradeId"]
    assert balances(client, auth)["USDC"] == "900.00"


def test_large_trades_are_flagged_for_review(client: TestClient, database: Database) -> None:
    whale = make_user(client, "whale@example.com", deposit="20000")
    q = quote(client, whale, "15000")
    client.post("/api/trade", json={"quoteId": q["quoteId"]}, headers=whale)
    with database.session_factory() as session:
        events = session.query(AuditEvent).filter_by(action="trade.executed").all()
        assert [e.flagged for e in events] == [True]


# MARK: History


def test_history_is_newest_first_and_private(client: TestClient, auth: dict) -> None:
    for amount, asset in (("10", "BTC"), ("20", "ETH")):
        q = quote(client, auth, amount, to=asset)
        client.post("/api/trade", json={"quoteId": q["quoteId"]}, headers=auth)

    other = make_user(client, "other@example.com")
    q = quote(client, other, "30")
    client.post("/api/trade", json={"quoteId": q["quoteId"]}, headers=other)

    trades = client.get("/api/trade/history", headers=auth).json()["trades"]
    assert [t["toAsset"] for t in trades] == ["ETH", "BTC"]
    assert [t["amount"] for t in trades] == ["20.00", "10.00"]

    assert len(client.get("/api/trade/history", headers=other).json()["trades"]) == 1


def test_dev_endpoints_can_be_disabled(settings, database) -> None:
    from app.main import create_app
    from tests.conftest import PRICES

    settings.enable_dev_endpoints = False
    locked_down = TestClient(create_app(settings=settings, database=database, prices=PRICES))
    assert locked_down.post("/api/dev/users", json={"email": "x@example.com"}).status_code == 404
