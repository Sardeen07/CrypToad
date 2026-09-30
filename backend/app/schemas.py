"""API request/response shapes. Money is serialized as decimal strings (e.g. "0.00198")
so clients never parse amounts through floating point."""

from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field
from pydantic.alias_generators import to_camel

from app.assets import Asset, display, from_minor
from app.models import Quote, Trade, as_utc


class CamelModel(BaseModel):
    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)


class QuoteOut(CamelModel):
    quote_id: str
    from_asset: Asset
    to_asset: Asset
    amount: Decimal = Field(description="USDC spent, including the fee")
    fee: Decimal
    net_amount: Decimal = Field(description="USDC converted after the fee")
    rate: Decimal = Field(description="USD price of one unit of to_asset")
    estimated_amount: Decimal = Field(description="Crypto received")
    expires_at: datetime

    @classmethod
    def from_model(cls, quote: Quote) -> "QuoteOut":
        base, target = Asset(quote.from_asset), Asset(quote.to_asset)
        return cls(
            quote_id=quote.id,
            from_asset=base,
            to_asset=target,
            amount=display(from_minor(quote.spend_minor, base)),
            fee=display(from_minor(quote.fee_minor, base)),
            net_amount=display(from_minor(quote.spend_minor - quote.fee_minor, base)),
            rate=display(Decimal(quote.price)),
            estimated_amount=display(from_minor(quote.quantity_minor, target), target),
            expires_at=as_utc(quote.expires_at),
        )


class TradeIn(CamelModel):
    quote_id: str


class TradeOut(CamelModel):
    trade_id: str
    from_asset: Asset
    to_asset: Asset
    amount: Decimal
    fee: Decimal
    crypto_received: Decimal
    rate: Decimal
    status: str
    timestamp: datetime

    @classmethod
    def from_model(cls, trade: Trade) -> "TradeOut":
        base, target = Asset(trade.from_asset), Asset(trade.to_asset)
        return cls(
            trade_id=trade.id,
            from_asset=base,
            to_asset=target,
            amount=display(from_minor(trade.spend_minor, base)),
            fee=display(from_minor(trade.fee_minor, base)),
            crypto_received=display(from_minor(trade.quantity_minor, target), target),
            rate=display(Decimal(trade.price)),
            status=trade.status,
            timestamp=as_utc(trade.created_at),
        )


class TradeHistoryOut(CamelModel):
    trades: list[TradeOut]


class BalancesOut(CamelModel):
    balances: dict[Asset, Decimal]


class DepositIn(CamelModel):
    amount: Decimal = Field(gt=0)


class DevUserIn(CamelModel):
    email: str
    kyc_status: str = "verified"


class DevUserOut(CamelModel):
    user_id: int
    email: str
    token: str = Field(description="Shown once. Send as 'Authorization: Bearer <token>'.")


class ErrorOut(CamelModel):
    error: str
    detail: str
