"""Business logic for quotes, trades, deposits, and balances.

Route handlers stay thin; everything that touches money lives here so it can be
tested directly.
"""

from datetime import datetime, timedelta
from decimal import ROUND_DOWN, Decimal

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app import ledger
from app.assets import BASE_ASSET, TRADEABLE, Asset, cents, cents_up, from_minor, to_minor
from app.config import Settings
from app.models import AuditEvent, Quote, Trade, User, as_utc, utcnow
from app.pricing import PriceProvider


class TradingError(Exception):
    status_code = 400
    code = "trading_error"


class UnsupportedPairError(TradingError):
    code = "unsupported_pair"


class InvalidAmountError(TradingError):
    code = "invalid_amount"


class QuoteNotFoundError(TradingError):
    status_code = 404
    code = "quote_not_found"


class QuoteAlreadyUsedError(TradingError):
    status_code = 409
    code = "quote_already_used"


class QuoteExpiredError(TradingError):
    status_code = 410
    code = "quote_expired"


class KycRequiredError(TradingError):
    status_code = 403
    code = "kyc_required"


class InsufficientFundsError(TradingError):
    code = "insufficient_funds"


def audit(session: Session, user: User | None, action: str, detail: dict, flagged: bool = False) -> None:
    session.add(AuditEvent(user_id=user.id if user else None, action=action, detail=detail, flagged=flagged))


# MARK: Quotes


def create_quote(
    session: Session,
    user: User,
    *,
    from_asset: Asset,
    to_asset: Asset,
    amount: Decimal,
    prices: PriceProvider,
    settings: Settings,
    now: datetime | None = None,
) -> Quote:
    """Validate → price → fee → quantity → store with an expiry (the "rate lock")."""
    now = now or utcnow()
    if from_asset != BASE_ASSET or to_asset not in TRADEABLE:
        raise UnsupportedPairError(f"Only {BASE_ASSET.value} → {', '.join(a.value for a in TRADEABLE)} is supported")

    spend = cents(amount)
    if spend < settings.minimum_trade_usd:
        raise InvalidAmountError(f"Minimum trade is ${settings.minimum_trade_usd}")

    price = prices.price_usd(to_asset)
    fee = cents_up(spend * settings.fee_rate)
    quantity = ((spend - fee) / price).quantize(Decimal(1).scaleb(-to_asset.scale), rounding=ROUND_DOWN)
    if quantity <= 0:
        raise InvalidAmountError("Amount is too small to buy any crypto")

    quote = Quote(
        user_id=user.id,
        from_asset=from_asset.value,
        to_asset=to_asset.value,
        spend_minor=to_minor(spend, BASE_ASSET),
        fee_minor=to_minor(fee, BASE_ASSET),
        quantity_minor=to_minor(quantity, to_asset),
        price=str(price),
        created_at=now,
        expires_at=now + timedelta(seconds=settings.quote_ttl_seconds),
    )
    session.add(quote)
    session.commit()
    return quote


# MARK: Trades


def execute_trade(
    session: Session,
    user: User,
    *,
    quote_id: str,
    settings: Settings,
    idempotency_key: str | None = None,
    now: datetime | None = None,
) -> tuple[Trade, bool]:
    """Executes a quoted trade. Returns ``(trade, created)``; ``created`` is False when an
    idempotency key replays an earlier request, so client retries can never double-spend."""
    now = now or utcnow()

    if idempotency_key:
        existing = session.scalars(select(Trade).where(Trade.user_id == user.id, Trade.idempotency_key == idempotency_key)).first()
        if existing:
            return existing, False

    quote = session.get(Quote, quote_id)
    if quote is None or quote.user_id != user.id:
        raise QuoteNotFoundError("Quote not found")
    if quote.used_at is not None:
        raise QuoteAlreadyUsedError("Quote has already been used")
    if as_utc(quote.expires_at) < now:
        raise QuoteExpiredError("Quote expired; request a new one")
    if user.kyc_status != "verified":
        raise KycRequiredError("Identity verification is required before trading")

    to_asset = Asset(quote.to_asset)
    # Lock the paying wallet so concurrent requests for the same user run one at a time.
    usdc_wallet = ledger.wallet(session, user.id, BASE_ASSET, lock=True)
    lines = [
        ledger.Line(usdc_wallet, -quote.spend_minor),
        ledger.Line(ledger.get_account(session, kind="fees", asset=BASE_ASSET), quote.fee_minor),
        ledger.Line(ledger.get_account(session, kind="liquidity", asset=BASE_ASSET), quote.spend_minor - quote.fee_minor),
        ledger.Line(ledger.get_account(session, kind="liquidity", asset=to_asset), -quote.quantity_minor),
        ledger.Line(ledger.wallet(session, user.id, to_asset), quote.quantity_minor),
    ]

    try:
        entry = ledger.post(session, kind="trade", memo=f"quote {quote.id}", lines=lines)
    except ledger.InsufficientFundsError as exc:
        session.rollback()
        needed, available = from_minor(exc.needed_minor, BASE_ASSET), from_minor(exc.available_minor, BASE_ASSET)
        raise InsufficientFundsError(f"Insufficient USDC: needed {needed:.2f}, available {available:.2f}") from exc

    quote.used_at = now
    trade = Trade(
        user_id=user.id,
        quote_id=quote.id,
        entry_id=entry.id,
        from_asset=quote.from_asset,
        to_asset=quote.to_asset,
        spend_minor=quote.spend_minor,
        fee_minor=quote.fee_minor,
        quantity_minor=quote.quantity_minor,
        price=quote.price,
        idempotency_key=idempotency_key,
        created_at=now,
    )
    session.add(trade)
    spend = from_minor(quote.spend_minor, BASE_ASSET)
    audit(
        session,
        user,
        "trade.executed",
        {"quote_id": quote.id, "to": quote.to_asset, "spend": str(spend), "quantity": str(from_minor(quote.quantity_minor, to_asset))},
        flagged=spend >= settings.large_trade_usd,
    )

    try:
        session.commit()
    except IntegrityError:
        # Lost a race with an identical request (same idempotency key or quote).
        session.rollback()
        if idempotency_key:
            existing = session.scalars(select(Trade).where(Trade.user_id == user.id, Trade.idempotency_key == idempotency_key)).first()
            if existing:
                return existing, False
        raise QuoteAlreadyUsedError("Quote has already been used")
    return trade, True


def trade_history(session: Session, user: User, limit: int = 50) -> list[Trade]:
    stmt = select(Trade).where(Trade.user_id == user.id).order_by(Trade.created_at.desc(), Trade.id.desc()).limit(limit)
    return list(session.scalars(stmt))


# MARK: Deposits + balances


def deposit(session: Session, user: User, amount: Decimal, memo: str = "Paycheck deposit") -> None:
    value = cents(amount)
    if value <= 0:
        raise InvalidAmountError("Deposit must be positive")
    minor = to_minor(value, BASE_ASSET)
    ledger.post(
        session,
        kind="deposit",
        memo=memo,
        lines=[
            ledger.Line(ledger.get_account(session, kind="external", asset=BASE_ASSET), -minor),
            ledger.Line(ledger.wallet(session, user.id, BASE_ASSET), minor),
        ],
    )
    audit(session, user, "deposit.received", {"amount": str(value)})
    session.commit()


def balances(session: Session, user: User) -> dict[Asset, Decimal]:
    return {asset: from_minor(ledger.balance_minor(session, ledger.wallet(session, user.id, asset)), asset) for asset in Asset}
