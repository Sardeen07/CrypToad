from decimal import Decimal

from fastapi import APIRouter, Depends, Header, Query, Response, status
from sqlalchemy.orm import Session

from app import trading
from app.assets import Asset
from app.auth import current_user
from app.config import Settings
from app.deps import get_app_settings, get_prices, get_session
from app.models import User
from app.pricing import PriceProvider
from app.schemas import QuoteOut, TradeHistoryOut, TradeIn, TradeOut

router = APIRouter(prefix="/api/trade", tags=["trade"])


@router.get("/quote", response_model=QuoteOut, summary="Get a conversion quote")
def get_quote(
    from_asset: Asset = Query(alias="from", examples=["USDC"]),
    to_asset: Asset = Query(alias="to", examples=["BTC"]),
    amount: Decimal = Query(gt=0, examples=["100"]),
    user: User = Depends(current_user),
    session: Session = Depends(get_session),
    prices: PriceProvider = Depends(get_prices),
    settings: Settings = Depends(get_app_settings),
) -> QuoteOut:
    """Prices a USDC → BTC/ETH conversion and locks the rate for a short window.
    Pass the returned `quoteId` to `POST /api/trade` to execute it."""
    quote = trading.create_quote(
        session, user, from_asset=from_asset, to_asset=to_asset, amount=amount, prices=prices, settings=settings
    )
    return QuoteOut.from_model(quote)


@router.post(
    "",
    response_model=TradeOut,
    status_code=status.HTTP_201_CREATED,
    summary="Execute a quoted trade",
)
def create_trade(
    body: TradeIn,
    response: Response,
    idempotency_key: str | None = Header(default=None, max_length=100),
    user: User = Depends(current_user),
    session: Session = Depends(get_session),
    settings: Settings = Depends(get_app_settings),
) -> TradeOut:
    """Executes a previously quoted trade at the locked rate.

    Send an `Idempotency-Key` header so a retried request (e.g. after a network
    timeout) returns the original trade instead of buying twice."""
    trade, created = trading.execute_trade(
        session, user, quote_id=body.quote_id, idempotency_key=idempotency_key, settings=settings
    )
    if not created:
        response.status_code = status.HTTP_200_OK
    return TradeOut.from_model(trade)


@router.get("/history", response_model=TradeHistoryOut, summary="Trade history for the signed-in user")
def get_history(
    limit: int = Query(default=50, ge=1, le=200),
    user: User = Depends(current_user),
    session: Session = Depends(get_session),
) -> TradeHistoryOut:
    # The user comes from the auth token, never from a userId parameter, so nobody can read someone else's trades.
    return TradeHistoryOut(trades=[TradeOut.from_model(t) for t in trading.trade_history(session, user, limit)])
