"""Round-ups and allocation-based investing (card purchases, bank purchases, DCA buys).

The math mirrors CrypToadCore on iOS (RoundUp.swift, Allocation.swift) so the app
and the server always agree to the cent.
"""

from dataclasses import dataclass
from datetime import datetime
from decimal import ROUND_CEILING, ROUND_DOWN, ROUND_HALF_UP, Decimal

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app import ledger
from app.assets import BASE_ASSET, Asset, from_minor, to_minor
from app.config import Settings
from app.errors import CardFrozenError
from app.models import Investment, Purchase, User, UserSettings, utcnow
from app.pricing import PriceProvider
from app.trading import (
    InsufficientFundsError,
    InvalidAllocationError,
    InvalidAmountError,
    KycRequiredError,
    audit,
    require_kyc,
)

# Same order as CrypToadCore's Asset.allCases; ties for "largest weight" go to the first.
ALLOCATION_ORDER = (Asset.BTC, Asset.ETH, Asset.USDC)
CENT = Decimal("0.01")


def to_cents(amount: Decimal) -> Decimal:
    return amount.quantize(CENT, rounding=ROUND_HALF_UP)


@dataclass(frozen=True)
class Allocation:
    btc: int
    eth: int
    usdc: int

    def __getitem__(self, asset: Asset) -> int:
        return {Asset.BTC: self.btc, Asset.ETH: self.eth, Asset.USDC: self.usdc}[asset]

    def validate(self) -> "Allocation":
        if self.btc < 0 or self.eth < 0 or self.usdc < 0 or self.btc + self.eth + self.usdc != 100:
            raise InvalidAllocationError("Allocation percentages must be non-negative and add up to 100")
        return self

    @classmethod
    def from_settings(cls, row: UserSettings) -> "Allocation":
        return cls(row.allocation_btc, row.allocation_eth, row.allocation_usdc)


def split(amount: Decimal, allocation: Allocation) -> dict[Asset, Decimal]:
    """Each share rounds down to the cent; leftover cents go to the largest weight, so shares
    always add up to exactly ``amount``."""
    total = to_cents(amount)
    shares = {asset: (total * allocation[asset] / 100).quantize(CENT, rounding=ROUND_DOWN) for asset in ALLOCATION_ORDER}
    leftover = total - sum(shares.values())
    if leftover:
        largest = max(ALLOCATION_ORDER, key=lambda a: allocation[a])
        shares[largest] += leftover
    return shares


def spare_change(amount: Decimal, multiplier: int = 1) -> Decimal:
    """$4.25 → $0.75. Whole-dollar purchases don't round up."""
    price = to_cents(amount)
    if price <= 0:
        return Decimal("0.00")
    return (price.to_integral_value(rounding=ROUND_CEILING) - price) * max(multiplier, 0)


def user_settings(session: Session, user: User) -> UserSettings:
    row = session.get(UserSettings, user.id)
    if row is None:
        row = UserSettings(
            user_id=user.id, roundups_enabled=True, roundup_multiplier=1,
            allocation_btc=50, allocation_eth=30, allocation_usdc=20, card_frozen=False,
        )
        session.add(row)
        session.flush()
    return row


class PriceBook:
    """Prices looked up at most once per operation, so every fill in one entry uses the same price."""

    def __init__(self, provider: PriceProvider) -> None:
        self.provider = provider
        self._prices: dict[Asset, Decimal] = {}

    def __call__(self, asset: Asset) -> Decimal:
        if asset not in self._prices:
            self._prices[asset] = self.provider.price_usd(asset)
        return self._prices[asset]


def _fill(asset: Asset, quantity: Decimal, price: Decimal, cost: Decimal) -> dict:
    return {"asset": asset.value, "quantity": str(quantity), "price": str(price), "cost": str(cost)}


def _investment_lines(
    session: Session, user: User, usd: Decimal, allocation: Allocation, prices: PriceBook, usdc_wallet
) -> tuple[list[ledger.Line], list[dict]]:
    """Ledger lines that convert ``usd`` of the user's USDC per ``allocation``.
    The USDC share simply stays in the wallet."""
    lines: list[ledger.Line] = []
    fills: list[dict] = []
    for asset, share in split(usd, allocation).items():
        if share <= 0:
            continue
        if asset is BASE_ASSET:
            fills.append(_fill(asset, share, Decimal(1), share))
            continue
        price = prices(asset)
        quantity = (share / price).quantize(Decimal(1).scaleb(-asset.scale), rounding=ROUND_DOWN)
        quantity_minor = to_minor(quantity, asset)
        if quantity_minor == 0:
            fills.append(_fill(BASE_ASSET, share, Decimal(1), share))
            continue
        share_minor = to_minor(share, BASE_ASSET)
        lines += [
            ledger.Line(usdc_wallet, -share_minor),
            ledger.Line(ledger.get_account(session, kind="liquidity", asset=BASE_ASSET), share_minor),
            ledger.Line(ledger.get_account(session, kind="liquidity", asset=asset), -quantity_minor),
            ledger.Line(ledger.wallet(session, user.id, asset), quantity_minor),
        ]
        fills.append(_fill(asset, from_minor(quantity_minor, asset), price, share))
    return lines, fills


def _post(session: Session, kind: str, memo: str, lines: list[ledger.Line]):
    try:
        return ledger.post(session, kind=kind, memo=memo, lines=lines)
    except ledger.InsufficientFundsError as exc:
        session.rollback()
        needed, available = from_minor(exc.needed_minor, BASE_ASSET), from_minor(exc.available_minor, BASE_ASSET)
        raise InsufficientFundsError(f"Insufficient USDC: needed {needed:.2f}, available {available:.2f}") from exc


# MARK: Card purchases


def record_card_purchase(session: Session, user: User, *, merchant: str, amount: Decimal, prices: PriceProvider) -> Purchase:
    """A swipe of the CrypToad card: pays the merchant from USDC and invests the round-up, atomically."""
    settings = user_settings(session, user)
    if settings.card_frozen:
        raise CardFrozenError("Your card is frozen. Unfreeze it to make purchases.")
    require_kyc(user)
    price = to_cents(amount)
    if price <= 0:
        raise InvalidAmountError("Purchase amount must be positive")
    spare = spare_change(price, settings.roundup_multiplier) if settings.roundups_enabled else Decimal("0.00")

    book = PriceBook(prices)
    usdc_wallet = ledger.wallet(session, user.id, BASE_ASSET, lock=True)
    price_minor = to_minor(price, BASE_ASSET)
    lines = [
        ledger.Line(usdc_wallet, -price_minor),
        ledger.Line(ledger.get_account(session, kind="merchant", asset=BASE_ASSET), price_minor),
    ]
    fills: list[dict] = []
    if spare > 0:
        extra, fills = _investment_lines(session, user, spare, Allocation.from_settings(settings), book, usdc_wallet)
        lines += extra

    entry = _post(session, "purchase", f"card: {merchant}", lines)
    purchase = Purchase(
        user_id=user.id, entry_id=entry.id, source="card", merchant=merchant[:100],
        amount_minor=price_minor, round_up_minor=to_minor(spare, BASE_ASSET), fills=fills,
    )
    session.add(purchase)
    audit(session, user, "card.purchase", {"merchant": merchant[:100], "amount": str(price), "round_up": str(spare)})
    session.commit()
    return purchase


# MARK: Bank purchases (Plaid)


def record_bank_purchase(
    session: Session,
    user: User,
    *,
    external_id: str,
    merchant: str,
    amount: Decimal,
    occurred_at: datetime,
    prices: PriceBook,
) -> Purchase | None:
    """A purchase seen in a linked bank account. Only the spare change is invested (from USDC).
    Returns ``None`` if this transaction was already recorded."""
    exists = session.scalars(select(Purchase.id).where(Purchase.user_id == user.id, Purchase.external_id == external_id)).first()
    if exists:
        return None

    settings = user_settings(session, user)
    price = to_cents(amount)
    spare = spare_change(price, settings.roundup_multiplier) if settings.roundups_enabled else Decimal("0.00")
    purchase = Purchase(
        user_id=user.id, source="bank", external_id=external_id[:100], merchant=merchant[:100],
        amount_minor=to_minor(price, BASE_ASSET), round_up_minor=to_minor(spare, BASE_ASSET), created_at=occurred_at,
    )

    if spare > 0:
        try:
            require_kyc(user)
            usdc_wallet = ledger.wallet(session, user.id, BASE_ASSET, lock=True)
            lines, fills = _investment_lines(session, user, spare, Allocation.from_settings(settings), prices, usdc_wallet)
            entry = _post(session, "roundup", f"bank: {merchant}", lines)
            purchase.entry_id = entry.id
            purchase.fills = fills
        except (InsufficientFundsError, KycRequiredError):
            # Not enough USDC (or not verified): keep the purchase in history, skip the round-up.
            session.rollback()
            purchase.status = "skipped"

    session.add(purchase)
    session.commit()
    return purchase


# MARK: Dollar-cost averaging


def invest(
    session: Session,
    user: User,
    *,
    amount: Decimal,
    allocation: Allocation,
    prices: PriceProvider,
    settings: Settings,
    idempotency_key: str | None = None,
) -> tuple[Investment, bool]:
    """One DCA buy. Returns ``(investment, created)``; a repeated idempotency key returns the original."""
    if idempotency_key:
        existing = session.scalars(
            select(Investment).where(Investment.user_id == user.id, Investment.idempotency_key == idempotency_key)
        ).first()
        if existing:
            return existing, False

    allocation.validate()
    require_kyc(user)
    value = to_cents(amount)
    if value < settings.minimum_trade_usd:
        raise InvalidAmountError(f"Minimum investment is ${settings.minimum_trade_usd}")

    usdc_wallet = ledger.wallet(session, user.id, BASE_ASSET, lock=True)
    lines, fills = _investment_lines(session, user, value, allocation, PriceBook(prices), usdc_wallet)
    # Fully-USDC allocations move nothing, but still need enough USDC to count as an investment.
    if not lines and ledger.balance_minor(session, usdc_wallet) < to_minor(value, BASE_ASSET):
        available = from_minor(ledger.balance_minor(session, usdc_wallet), BASE_ASSET)
        raise InsufficientFundsError(f"Insufficient USDC: needed {value:.2f}, available {available:.2f}")
    entry = _post(session, "invest", "DCA buy", lines) if lines else None

    record = Investment(
        user_id=user.id, entry_id=entry.id if entry else None, amount_minor=to_minor(value, BASE_ASSET),
        fills=fills, idempotency_key=idempotency_key, created_at=utcnow(),
    )
    session.add(record)
    audit(session, user, "dca.buy", {"amount": str(value), "fills": fills})
    try:
        session.commit()
    except IntegrityError:
        session.rollback()
        if idempotency_key:
            existing = session.scalars(
                select(Investment).where(Investment.user_id == user.id, Investment.idempotency_key == idempotency_key)
            ).first()
            if existing:
                return existing, False
        raise
    return record, True
