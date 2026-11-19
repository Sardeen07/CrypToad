"""Market prices. In production this would be the liquidity provider's executable
quote (Coinbase Prime, Fireblocks, ...); for this prototype it's CoinGecko's public price."""

import json
import threading
import time
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
    """Fetches every asset in one request and caches the result briefly.

    CoinGecko's free tier allows only a few requests a minute, and one bank sync can
    round up dozens of purchases, so prices are shared for ``cache_seconds``."""

    URL = "https://api.coingecko.com/api/v3/simple/price"

    def __init__(self, client: httpx.Client | None = None, timeout: float = 5.0, cache_seconds: float = 30.0) -> None:
        self.client = client or httpx.Client(timeout=timeout)
        self.cache_seconds = cache_seconds
        self._cache: dict[Asset, Decimal] = {}
        self._fetched_at = float("-inf")
        self._lock = threading.Lock()

    def price_usd(self, asset: Asset) -> Decimal:
        with self._lock:
            if time.monotonic() - self._fetched_at > self.cache_seconds or asset not in self._cache:
                self._cache = self._fetch_all()
                self._fetched_at = time.monotonic()
            if asset not in self._cache:
                raise PriceUnavailableError(f"Price unavailable for {asset.value}")
            return self._cache[asset]

    def _fetch_all(self) -> dict[Asset, Decimal]:
        ids = ",".join(asset.coingecko_id for asset in Asset)
        try:
            response = self.client.get(self.URL, params={"ids": ids, "vs_currencies": "usd"})
            response.raise_for_status()
            # parse_float=Decimal keeps the price exact instead of going through float.
            data = json.loads(response.text, parse_float=Decimal)
        except (httpx.HTTPError, ValueError) as exc:
            raise PriceUnavailableError(f"Price unavailable: {exc}") from exc

        prices: dict[Asset, Decimal] = {}
        for asset in Asset:
            try:
                price = Decimal(data[asset.coingecko_id]["usd"])
            except (KeyError, TypeError, ValueError):
                continue
            if price > 0:
                prices[asset] = price
        return prices
