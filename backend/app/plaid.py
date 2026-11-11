"""A small Plaid API client (bank linking + transactions), over plain HTTPS with httpx.

Docs: https://plaid.com/docs/api/. Works against the free Sandbox with test
credentials; switching ``CRYPTOAD_PLAID_ENV`` to ``production`` is a config
change once Plaid approves the app.
"""

from dataclasses import dataclass
from datetime import date

import httpx

from app.errors import BankProviderError

HOSTS = {
    "sandbox": "https://sandbox.plaid.com",
    "production": "https://production.plaid.com",
}

# "First Platypus Bank", Plaid's standard sandbox institution.
SANDBOX_INSTITUTION_ID = "ins_109508"
SANDBOX_INSTITUTION_NAME = "First Platypus Bank (Sandbox)"


@dataclass(frozen=True)
class BankTransaction:
    transaction_id: str
    merchant: str
    # Positive = money leaving the account (a purchase), per Plaid's sign convention.
    amount: str
    date: date
    pending: bool
    currency: str | None


@dataclass(frozen=True)
class SyncPage:
    added: list[BankTransaction]
    next_cursor: str
    has_more: bool
    update_status: str


class PlaidClient:
    def __init__(self, client_id: str, secret: str, env: str = "sandbox", http: httpx.Client | None = None) -> None:
        if env not in HOSTS:
            raise ValueError(f"Unknown Plaid environment: {env}")
        self.env = env
        self._auth = {"client_id": client_id, "secret": secret}
        self._http = http or httpx.Client(base_url=HOSTS[env], timeout=15.0)

    def _post(self, path: str, body: dict) -> dict:
        try:
            response = self._http.post(path, json={**self._auth, **body})
        except httpx.HTTPError as exc:
            raise BankProviderError(f"Couldn't reach Plaid: {exc}") from exc
        data = response.json() if response.content else {}
        if response.status_code != 200:
            # Plaid errors look like {"error_code": "...", "error_message": "...", "display_message": ...}
            message = data.get("display_message") or data.get("error_message") or f"HTTP {response.status_code}"
            raise BankProviderError(f"Plaid {data.get('error_code', 'error')}: {message}")
        return data

    # MARK: Linking

    def create_link_token(self, user_id: int) -> str:
        """For the Plaid Link SDK in the app (the production linking flow)."""
        data = self._post(
            "/link/token/create",
            {
                "client_name": "CrypToad",
                "user": {"client_user_id": str(user_id)},
                "products": ["transactions"],
                "country_codes": ["US"],
                "language": "en",
            },
        )
        return data["link_token"]

    def sandbox_public_token(self, institution_id: str = SANDBOX_INSTITUTION_ID) -> str:
        """Sandbox only: links a test bank without the Link UI."""
        data = self._post(
            "/sandbox/public_token/create",
            {"institution_id": institution_id, "initial_products": ["transactions"]},
        )
        return data["public_token"]

    def exchange_public_token(self, public_token: str) -> tuple[str, str]:
        """Returns ``(access_token, item_id)``."""
        data = self._post("/item/public_token/exchange", {"public_token": public_token})
        return data["access_token"], data["item_id"]

    def remove_item(self, access_token: str) -> None:
        self._post("/item/remove", {"access_token": access_token})

    # MARK: Transactions

    def sync_transactions(self, access_token: str, cursor: str | None, count: int = 250) -> SyncPage:
        body: dict = {"access_token": access_token, "count": count}
        if cursor:
            body["cursor"] = cursor
        data = self._post("/transactions/sync", body)
        added = [
            BankTransaction(
                transaction_id=t["transaction_id"],
                merchant=(t.get("merchant_name") or t.get("name") or "Purchase"),
                amount=str(t["amount"]),
                date=date.fromisoformat(t["date"]),
                pending=bool(t.get("pending")),
                currency=t.get("iso_currency_code"),
            )
            for t in data.get("added", [])
        ]
        return SyncPage(
            added=added,
            next_cursor=data.get("next_cursor", cursor or ""),
            has_more=bool(data.get("has_more")),
            update_status=data.get("transactions_update_status", "UNKNOWN"),
        )
