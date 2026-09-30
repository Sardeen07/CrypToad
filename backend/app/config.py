from decimal import Decimal
from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime configuration, read from environment variables (prefix CRYPTOAD_)."""

    model_config = SettingsConfigDict(env_prefix="CRYPTOAD_", env_file=".env", extra="ignore")

    database_url: str = "sqlite:///./cryptoad.db"
    # Conversion fee: 1%, the middle of the 0.5–1.5% range in docs/api-spec.md.
    fee_rate: Decimal = Decimal("0.01")
    # How long a quoted rate is honored.
    quote_ttl_seconds: int = 45
    minimum_trade_usd: Decimal = Decimal("1")
    # Trades at or above this size are flagged in the audit log for compliance review.
    large_trade_usd: Decimal = Decimal("10000")
    # Enables POST /api/dev/* helpers (funding test accounts). Never enable in production.
    enable_dev_endpoints: bool = True
    # "coingecko" for live prices, "static" for fixed demo prices.
    price_source: str = "coingecko"


@lru_cache
def get_settings() -> Settings:
    return Settings()
