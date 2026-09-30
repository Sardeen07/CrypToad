"""Supported assets and exact conversion between decimal amounts and integer minor units.

All balances are stored as integers in each asset's smallest tracked unit
(micro-USDC, satoshis, ...). Integer math is exact in every database, so the
ledger can never drift by a fraction of a cent the way floats can.
"""

from decimal import ROUND_DOWN, ROUND_UP, Decimal
from enum import Enum


class Asset(str, Enum):
    USDC = "USDC"
    BTC = "BTC"
    ETH = "ETH"

    @property
    def scale(self) -> int:
        """Decimal places tracked. Matches the iOS app (CrypToadCore.Asset.precision)."""
        return {Asset.USDC: 6, Asset.BTC: 8, Asset.ETH: 8}[self]

    @property
    def coingecko_id(self) -> str:
        return {Asset.USDC: "usd-coin", Asset.BTC: "bitcoin", Asset.ETH: "ethereum"}[self]


BASE_ASSET = Asset.USDC
TRADEABLE = (Asset.BTC, Asset.ETH)


def to_minor(amount: Decimal, asset: Asset, rounding: str = ROUND_DOWN) -> int:
    """Decimal amount → integer minor units. Rounds down by default so we never credit more than was paid for."""
    quantum = Decimal(1).scaleb(-asset.scale)
    return int((amount.quantize(quantum, rounding=rounding)) * (10 ** asset.scale))


def from_minor(units: int, asset: Asset) -> Decimal:
    return Decimal(units).scaleb(-asset.scale)


def cents(amount: Decimal, rounding: str = ROUND_DOWN) -> Decimal:
    return amount.quantize(Decimal("0.01"), rounding=rounding)


def cents_up(amount: Decimal) -> Decimal:
    return cents(amount, ROUND_UP)


def display(amount: Decimal, asset: Asset | None = None) -> Decimal:
    """Clean decimal for API output: USD/USDC to 2 places, crypto without trailing zeros."""
    if asset is None or asset is Asset.USDC:
        return amount.quantize(Decimal("0.01"))
    return Decimal(format(amount.normalize(), "f"))
