"""Linking a bank account and rounding up its purchases (the Acorns-style flow).

Plaid reports the user's bank transactions; every new purchase is rounded up and
the spare change is invested from the user's USDC balance per their allocation.
Each Plaid transaction id is recorded, so syncing again never double-counts.
"""

from dataclasses import dataclass, field
from datetime import datetime, time, timedelta, timezone
from decimal import Decimal, InvalidOperation

from sqlalchemy import select
from sqlalchemy.orm import Session

from app import investing
from app.config import Settings
from app.crypto import SecretBox
from app.errors import BankNotLinkedError, BankUnavailableError
from app.models import BankLink, User, utcnow
from app.plaid import SANDBOX_INSTITUTION_NAME, PlaidClient
from app.pricing import PriceProvider
from app.trading import audit

# Safety valve: one sync never processes more than this many pages of 250 transactions.
MAX_SYNC_PAGES = 8


@dataclass
class SyncResult:
    status: str
    added: int = 0
    rounded_up: int = 0
    skipped: int = 0
    total_round_up: Decimal = Decimal("0.00")
    purchase_ids: list[str] = field(default_factory=list)


def require_plaid(plaid: PlaidClient | None) -> PlaidClient:
    if plaid is None:
        raise BankUnavailableError("Bank linking isn't configured on this server (set CRYPTOAD_PLAID_CLIENT_ID and CRYPTOAD_PLAID_SECRET)")
    return plaid


def get_link(session: Session, user: User) -> BankLink | None:
    return session.scalars(select(BankLink).where(BankLink.user_id == user.id)).first()


def link_bank(
    session: Session,
    user: User,
    *,
    plaid: PlaidClient,
    box: SecretBox,
    settings: Settings,
    public_token: str,
    institution_name: str | None,
) -> BankLink:
    access_token, item_id = plaid.exchange_public_token(public_token)
    existing = get_link(session, user)
    if existing is not None:
        session.delete(existing)
        session.flush()
    link = BankLink(
        user_id=user.id,
        item_id=item_id,
        access_token=box.seal(access_token),
        institution_name=institution_name,
        round_up_from=(utcnow() - timedelta(days=settings.plaid_roundup_lookback_days)).date(),
    )
    session.add(link)
    audit(session, user, "bank.linked", {"provider": "plaid", "institution": institution_name})
    session.commit()
    return link


def link_sandbox_bank(session: Session, user: User, *, plaid: PlaidClient, box: SecretBox, settings: Settings) -> BankLink:
    if plaid.env != "sandbox":
        raise BankUnavailableError("Test-bank linking only works in Plaid's sandbox environment")
    public_token = plaid.sandbox_public_token()
    return link_bank(
        session, user, plaid=plaid, box=box, settings=settings, public_token=public_token, institution_name=SANDBOX_INSTITUTION_NAME
    )


def unlink_bank(session: Session, user: User, *, plaid: PlaidClient | None, box: SecretBox) -> None:
    link = get_link(session, user)
    if link is None:
        return
    if plaid is not None:
        try:
            plaid.remove_item(box.open(link.access_token))
        except Exception:  # noqa: BLE001 — unlinking locally must succeed even if Plaid is unreachable
            pass
    session.delete(link)
    audit(session, user, "bank.unlinked", {"provider": "plaid"})
    session.commit()


def sync(session: Session, user: User, *, plaid: PlaidClient, box: SecretBox, prices: PriceProvider) -> SyncResult:
    link = get_link(session, user)
    if link is None:
        raise BankNotLinkedError("Link a bank account first")

    access_token = box.open(link.access_token)
    cursor = link.cursor
    book = investing.PriceBook(prices)
    result = SyncResult(status="ok")
    round_up_from = link.round_up_from

    for _ in range(MAX_SYNC_PAGES):
        page = plaid.sync_transactions(access_token, cursor)
        result.status = page.update_status
        for txn in page.added:
            if txn.pending or (txn.currency not in (None, "USD")) or txn.date < round_up_from:
                continue
            try:
                amount = Decimal(txn.amount)
            except InvalidOperation:
                continue
            if amount <= 0:  # refunds and deposits aren't purchases
                continue
            occurred_at = datetime.combine(txn.date, time(12, 0), tzinfo=timezone.utc)
            purchase = investing.record_bank_purchase(
                session, user, external_id=txn.transaction_id, merchant=txn.merchant,
                amount=amount, occurred_at=occurred_at, prices=book,
            )
            if purchase is None:
                continue
            result.added += 1
            result.purchase_ids.append(purchase.id)
            if purchase.status == "skipped":
                result.skipped += 1
            elif purchase.round_up_minor > 0:
                result.rounded_up += 1
                result.total_round_up += Decimal(purchase.round_up_minor).scaleb(-6)

        cursor = page.next_cursor
        # Save progress after every page so a failure mid-sync never replays a page.
        link = get_link(session, user)
        link.cursor = cursor
        link.last_synced_at = utcnow()
        session.commit()
        if not page.has_more:
            break

    result.total_round_up = result.total_round_up.quantize(Decimal("0.01"))
    return result
