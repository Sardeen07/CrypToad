"""Double-entry ledger.

Every change to a balance is a journal entry whose postings sum to zero per
asset. Money is never created or destroyed inside the system: a user's +BTC is
always matched by the liquidity account's -BTC, and so on. Balances are the sum
of postings, so the full history can always be replayed and audited.
"""

from collections import defaultdict
from dataclasses import dataclass

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.assets import Asset
from app.models import JournalEntry, LedgerAccount, Posting


class UnbalancedEntryError(ValueError):
    pass


class InsufficientFundsError(ValueError):
    def __init__(self, needed_minor: int, available_minor: int, asset: Asset) -> None:
        super().__init__(f"Insufficient {asset.value}: needed {needed_minor}, available {available_minor}")
        self.needed_minor = needed_minor
        self.available_minor = available_minor
        self.asset = asset


@dataclass(frozen=True)
class Line:
    account: LedgerAccount
    amount_minor: int


def get_account(session: Session, *, kind: str, asset: Asset, owner_id: int | None = None, lock: bool = False) -> LedgerAccount:
    """Fetches (or creates) an account. With ``lock=True`` the row is locked until commit
    (``SELECT ... FOR UPDATE`` on Postgres), which serializes concurrent trades for the same wallet
    so two requests can't both spend the same USDC."""
    stmt = select(LedgerAccount).where(
        LedgerAccount.kind == kind,
        LedgerAccount.asset == asset.value,
        LedgerAccount.owner_id.is_(None) if owner_id is None else LedgerAccount.owner_id == owner_id,
    )
    if lock:
        stmt = stmt.with_for_update()
    account = session.scalars(stmt).first()
    if account is None:
        account = LedgerAccount(kind=kind, asset=asset.value, owner_id=owner_id)
        session.add(account)
        session.flush()
    return account


def wallet(session: Session, user_id: int, asset: Asset, lock: bool = False) -> LedgerAccount:
    return get_account(session, kind="user_wallet", asset=asset, owner_id=user_id, lock=lock)


def balance_minor(session: Session, account: LedgerAccount) -> int:
    total = session.scalar(select(func.coalesce(func.sum(Posting.amount_minor), 0)).where(Posting.account_id == account.id))
    return int(total or 0)


def post(session: Session, *, kind: str, memo: str, lines: list[Line]) -> JournalEntry:
    """Writes a journal entry. Raises if the lines don't net to zero per asset,
    or if any user wallet would go negative."""
    totals: dict[str, int] = defaultdict(int)
    for line in lines:
        totals[line.account.asset] += line.amount_minor
    unbalanced = {asset: total for asset, total in totals.items() if total != 0}
    if unbalanced:
        raise UnbalancedEntryError(f"Entry does not balance: {unbalanced}")

    for line in lines:
        if line.account.kind == "user_wallet" and line.amount_minor < 0:
            available = balance_minor(session, line.account)
            if available + line.amount_minor < 0:
                raise InsufficientFundsError(-line.amount_minor, available, Asset(line.account.asset))

    entry = JournalEntry(kind=kind, memo=memo)
    entry.postings = [
        Posting(account_id=line.account.id, asset=line.account.asset, amount_minor=line.amount_minor) for line in lines if line.amount_minor != 0
    ]
    session.add(entry)
    session.flush()
    return entry


def trial_balance(session: Session) -> dict[str, int]:
    """Sum of all postings per asset. Must be zero for every asset at all times."""
    rows = session.execute(select(Posting.asset, func.sum(Posting.amount_minor)).group_by(Posting.asset)).all()
    return {asset: int(total) for asset, total in rows}
