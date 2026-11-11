from fastapi.testclient import TestClient

from tests.conftest import apple_token, make_user


def sign_in(client: TestClient, token: str, nonce: str | None = "raw-nonce", **extra):
    return client.post("/api/auth/apple", json={"identityToken": token, "nonce": nonce, **extra})


def test_apple_sign_in_creates_then_reuses_the_account(client: TestClient) -> None:
    first = sign_in(client, apple_token(), fullName="Ali")
    assert first.status_code == 201, first.text
    body = first.json()
    assert body["created"] is True
    assert body["user"]["signInMethod"] == "apple"
    assert body["user"]["email"] == "toad@privaterelay.appleid.com"
    assert body["user"]["displayName"] == "Ali"

    # Apple omits the email on later sign-ins; the same account comes back.
    again = sign_in(client, apple_token(email=None))
    assert again.status_code == 200
    assert again.json()["created"] is False
    assert again.json()["user"]["userId"] == body["user"]["userId"]

    # Each sign-in is its own session, and both work.
    for token in (body["token"], again.json()["token"]):
        assert client.get("/api/me", headers={"Authorization": f"Bearer {token}"}).status_code == 200


def test_apple_tokens_for_another_app_are_rejected(client: TestClient) -> None:
    response = sign_in(client, apple_token(aud="com.someone.else"))
    assert response.status_code == 401
    assert response.json()["error"] == "invalid_credentials"


def test_expired_apple_tokens_are_rejected(client: TestClient) -> None:
    assert sign_in(client, apple_token(exp=1_000_000_000)).status_code == 401


def test_nonce_must_match(client: TestClient) -> None:
    assert sign_in(client, apple_token(nonce="raw-nonce"), nonce="different").status_code == 401


def test_tokens_not_signed_by_apple_are_rejected(client: TestClient) -> None:
    assert sign_in(client, apple_token() + "tampered").status_code == 401


def test_demo_account_comes_funded(client: TestClient) -> None:
    response = client.post("/api/auth/demo", json={"startingBalance": "750"})
    assert response.status_code == 201
    headers = {"Authorization": f"Bearer {response.json()['token']}"}
    assert response.json()["user"]["signInMethod"] == "demo"
    assert client.get("/api/balances", headers=headers).json()["balances"]["USDC"] == "750.00"
    activity = client.get("/api/activity", headers=headers).json()["activity"]
    assert [a["kind"] for a in activity] == ["deposit"]


def test_demo_accounts_are_off_when_dev_endpoints_are_disabled(client: TestClient) -> None:
    client.app.state.settings.enable_dev_endpoints = False
    assert client.post("/api/auth/demo").status_code == 404


def test_logout_revokes_only_that_session(client: TestClient) -> None:
    a = sign_in(client, apple_token()).json()["token"]
    b = sign_in(client, apple_token()).json()["token"]
    assert client.post("/api/auth/logout", headers={"Authorization": f"Bearer {a}"}).status_code == 204
    assert client.get("/api/me", headers={"Authorization": f"Bearer {a}"}).status_code == 401
    assert client.get("/api/me", headers={"Authorization": f"Bearer {b}"}).status_code == 200


def test_delete_account_signs_out_everywhere_and_frees_the_apple_id(client: TestClient) -> None:
    first = sign_in(client, apple_token()).json()
    headers = {"Authorization": f"Bearer {first['token']}"}
    assert client.delete("/api/me", headers=headers).status_code == 204
    assert client.get("/api/me", headers=headers).status_code == 401

    # Signing in again with the same Apple ID starts a brand-new, empty account.
    fresh = sign_in(client, apple_token())
    assert fresh.status_code == 201
    assert fresh.json()["user"]["userId"] != first["user"]["userId"]


def test_me_uses_the_token_user(client: TestClient) -> None:
    headers = make_user(client, email="someone@example.com", deposit=None)
    assert client.get("/api/me", headers=headers).json()["email"] == "someone@example.com"
