from fastapi import APIRouter, Depends, Header, HTTPException, Query, Response, status
from sqlalchemy.orm import Session

from app import activity, investing, trading
from app.assets import display
from app.auth import create_user, current_user
from app.config import Settings
from app.deps import get_app_settings, get_prices, get_session
from app.models import User
from app.pricing import PriceProvider
from app.schemas import (
    ActivityListOut,
    ActivityOut,
    AllocationIO,
    BalancesOut,
    CardPurchaseIn,
    DepositIn,
    DevUserIn,
    DevUserOut,
    InvestIn,
    RoundUpSettingsIO,
    SettingsIO,
)

router = APIRouter(prefix="/api", tags=["account"])


@router.get("/balances", response_model=BalancesOut)
def get_balances(user: User = Depends(current_user), session: Session = Depends(get_session)) -> BalancesOut:
    return BalancesOut(balances={asset: display(amount, asset) for asset, amount in trading.balances(session, user).items()})


@router.get("/activity", response_model=ActivityListOut, summary="Deposits, purchases, trades, and DCA buys, newest first")
def get_activity(
    limit: int = Query(default=100, ge=1, le=500),
    user: User = Depends(current_user),
    session: Session = Depends(get_session),
) -> ActivityListOut:
    return ActivityListOut(activity=activity.activity(session, user, limit))


# MARK: Settings


def settings_out(session: Session, user: User) -> SettingsIO:
    row = investing.user_settings(session, user)
    return SettingsIO(
        round_ups=RoundUpSettingsIO(
            enabled=row.roundups_enabled,
            multiplier=row.roundup_multiplier,
            allocation=AllocationIO(btc=row.allocation_btc, eth=row.allocation_eth, usdc=row.allocation_usdc),
        ),
        card_frozen=row.card_frozen,
    )


@router.get("/settings", response_model=SettingsIO, summary="Round-up and card settings")
def get_settings(user: User = Depends(current_user), session: Session = Depends(get_session)) -> SettingsIO:
    return settings_out(session, user)


@router.put("/settings", response_model=SettingsIO, summary="Update round-up and card settings")
def put_settings(body: SettingsIO, user: User = Depends(current_user), session: Session = Depends(get_session)) -> SettingsIO:
    allocation = body.round_ups.allocation
    investing.Allocation(allocation.btc, allocation.eth, allocation.usdc).validate()
    row = investing.user_settings(session, user)
    row.roundups_enabled = body.round_ups.enabled
    row.roundup_multiplier = body.round_ups.multiplier
    row.allocation_btc, row.allocation_eth, row.allocation_usdc = allocation.btc, allocation.eth, allocation.usdc
    if row.card_frozen != body.card_frozen:
        trading.audit(session, user, "card.frozen" if body.card_frozen else "card.unfrozen", {})
    row.card_frozen = body.card_frozen
    session.commit()
    return settings_out(session, user)


# MARK: Investing


@router.post("/invest", response_model=ActivityOut, status_code=status.HTTP_201_CREATED, summary="Run a DCA buy")
def post_invest(
    body: InvestIn,
    response: Response,
    idempotency_key: str | None = Header(default=None, max_length=100),
    user: User = Depends(current_user),
    session: Session = Depends(get_session),
    prices: PriceProvider = Depends(get_prices),
    settings: Settings = Depends(get_app_settings),
) -> ActivityOut:
    """Invests `amount` of USDC split by `allocation`. The app sends one request per scheduled buy with an
    `Idempotency-Key` derived from the schedule date, so a retry or a second device can't buy twice."""
    allocation = investing.Allocation(body.allocation.btc, body.allocation.eth, body.allocation.usdc)
    record, created = investing.invest(
        session, user, amount=body.amount, allocation=allocation, prices=prices, settings=settings, idempotency_key=idempotency_key
    )
    if not created:
        response.status_code = status.HTTP_200_OK
    return next(a for a in activity.activity(session, user, limit=500) if a.id == record.id)


# MARK: Dev helpers


def require_dev(settings: Settings = Depends(get_app_settings)) -> None:
    if not settings.enable_dev_endpoints:
        raise HTTPException(status.HTTP_404_NOT_FOUND)


dev = APIRouter(prefix="/api/dev", tags=["dev"], dependencies=[Depends(require_dev)])


@dev.post("/users", response_model=DevUserOut, status_code=status.HTTP_201_CREATED)
def dev_create_user(body: DevUserIn, session: Session = Depends(get_session)) -> DevUserOut:
    """Creates a test user and returns its API token. Disabled when CRYPTOAD_ENABLE_DEV_ENDPOINTS=false."""
    user, token = create_user(session, body.email, kyc_status=body.kyc_status)
    return DevUserOut(user_id=user.id, email=user.email, token=token)


@dev.post("/deposit", response_model=BalancesOut)
def dev_deposit(body: DepositIn, user: User = Depends(current_user), session: Session = Depends(get_session)) -> BalancesOut:
    """Simulates a paycheck landing as USDC (in production this is the payroll / bank-transfer webhook)."""
    trading.deposit(session, user, body.amount)
    return get_balances(user, session)


@dev.post("/card-purchase", response_model=ActivityOut, status_code=status.HTTP_201_CREATED)
def dev_card_purchase(
    body: CardPurchaseIn,
    user: User = Depends(current_user),
    session: Session = Depends(get_session),
    prices: PriceProvider = Depends(get_prices),
) -> ActivityOut:
    """Simulates a card swipe (in production this is the card issuer's authorization webhook).
    Pays the merchant from USDC and invests the round-up per the user's settings."""
    purchase = investing.record_card_purchase(session, user, merchant=body.merchant, amount=body.amount, prices=prices)
    return next(a for a in activity.activity(session, user, limit=500) if a.id == purchase.id)
