"""Market prices. In production this would be the liquidity provider's executable
quote (Coinbase Prime, Fireblocks, ...); for this prototype it's CoinGecko's public price."""

import json
from decimal import Decimal
from typing import Protocol

import httpx

from app.assets import Asset


class PriceUnavailableError(RuntimeError):
    pass


class PriceProvider(Protocol):
    def price_usd(self, asset: Asset) -> Decimal: ...


class StaticPriceProvider:
    def __init__(self, prices: dict[Asset, Decimal]) -> None:
        self.prices = prices

    def price_usd(self, asset: Asset) -> Decimal:
        if asset not in self.prices:
            raise PriceUnavailableError(f"No price for {asset.value}")
        return self.prices[asset]


DEMO_PRICES = StaticPriceProvider({Asset.BTC: Decimal("92340"), Asset.ETH: Decimal("3120"), Asset.USDC: Decimal("1")})


class CoinGeckoPriceProvider:
    URL = "https://api.coingecko.com/api/v3/simple/price"

    def __init__(self, client: httpx.Client | None = None, timeout: float = 5.0) -> None:
        self.client = client or httpx.Client(timeout=timeout)

    def price_usd(self, asset: Asset) -> Decimal:
        try:
            response = self.client.get(self.URL, params={"ids": asset.coingecko_id, "vs_currencies": "usd"})
            response.raise_for_status()
            # parse_float=Decimal keeps the price exact instead of going through float.
            data = json.loads(response.text, parse_float=Decimal)
            price = Decimal(data[asset.coingecko_id]["usd"])
        except (httpx.HTTPError, KeyError, ValueError, TypeError) as exc:
            raise PriceUnavailableError(f"Price unavailable for {asset.value}: {exc}") from exc
        if price <= 0:
            raise PriceUnavailableError(f"Invalid price for {asset.value}")
        return price
