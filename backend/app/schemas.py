"""API request/response shapes. Money is serialized as decimal strings (e.g. "0.00198")
so clients never parse amounts through floating point."""

from datetime import date, datetime
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


# MARK: Accounts


class AppleSignInIn(CamelModel):
    identity_token: str = Field(description="The JWT from ASAuthorizationAppleIDCredential.identityToken")
    nonce: str | None = Field(default=None, description="The raw nonce the app generated; its SHA-256 must match the token")
    full_name: str | None = Field(default=None, max_length=100, description="Only sent by Apple on the first sign-in")


class UserOut(CamelModel):
    user_id: int
    email: str | None
    display_name: str | None
    kyc_status: str
    sign_in_method: str


class SessionOut(CamelModel):
    token: str = Field(description="Shown once. Send as 'Authorization: Bearer <token>'.")
    user: UserOut
    created: bool = Field(description="True if this sign-in created the account")


class DemoAccountIn(CamelModel):
    starting_balance: Decimal = Field(default=Decimal("1000"), ge=0, le=100000)


# MARK: Settings


class AllocationIO(CamelModel):
    btc: int = Field(ge=0, le=100)
    eth: int = Field(ge=0, le=100)
    usdc: int = Field(ge=0, le=100)


class RoundUpSettingsIO(CamelModel):
    enabled: bool
    multiplier: int = Field(ge=1, le=10)
    allocation: AllocationIO


class SettingsIO(CamelModel):
    round_ups: RoundUpSettingsIO
    card_frozen: bool


# MARK: Activity


class FillOut(CamelModel):
    asset: Asset
    quantity: Decimal
    price: Decimal
    cost: Decimal


class ActivityOut(CamelModel):
    id: str
    kind: str = Field(description="deposit | purchase | trade | dcaBuy (matches the app's TransactionRecord.Kind)")
    title: str
    date: datetime
    amount: Decimal
    round_up: Decimal
    fee: Decimal
    fills: list[FillOut]
    source: str | None = Field(default=None, description="card | bank, for purchases")
    status: str


class ActivityListOut(CamelModel):
    activity: list[ActivityOut]


class CardPurchaseIn(CamelModel):
    merchant: str = Field(min_length=1, max_length=100)
    amount: Decimal = Field(gt=0, le=100000)


class InvestIn(CamelModel):
    amount: Decimal = Field(gt=0)
    allocation: AllocationIO


# MARK: Bank


class BankStatusOut(CamelModel):
    linked: bool
    available: bool = Field(description="Whether this server has bank linking configured")
    sandbox: bool
    institution_name: str | None = None
    linked_at: datetime | None = None
    last_synced_at: datetime | None = None
    round_up_from: date | None = None


class LinkTokenOut(CamelModel):
    link_token: str


class BankExchangeIn(CamelModel):
    public_token: str
    institution_name: str | None = Field(default=None, max_length=100)


class BankSyncOut(CamelModel):
    status: str = Field(description="Plaid's transactions_update_status; NOT_READY means try again shortly")
    added: int
    rounded_up: int
    skipped: int
    total_round_up: Decimal
