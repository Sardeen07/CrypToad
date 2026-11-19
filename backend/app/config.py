from decimal import Decimal
from functools import lru_cache

from pydantic import field_validator
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
    # Enables POST /api/dev/* helpers (demo accounts, simulated paychecks and card swipes).
    # Fine for a demo deployment with simulated money; never enable once real money is involved.
    enable_dev_endpoints: bool = True
    # "coingecko" for live prices, "static" for fixed demo prices.
    price_source: str = "coingecko"

    # Sign in with Apple: the app's bundle ID(s) that identity tokens must be issued for.
    apple_audiences: str = "com.sardeen07.cryptoad"

    # Encrypts secrets at rest (Plaid access tokens). Any long random string; required in production.
    secret_key: str | None = None

    # Plaid (bank linking). Leave unset to disable bank linking.
    plaid_client_id: str | None = None
    plaid_secret: str | None = None
    plaid_env: str = "sandbox"
    # When a bank is first linked, round up purchases from this many days back.
    plaid_roundup_lookback_days: int = 7

    @field_validator("database_url")
    @classmethod
    def use_psycopg_driver(cls, url: str) -> str:
        """Hosts like Render and Railway hand out ``postgres://`` URLs; SQLAlchemy needs the driver named."""
        for prefix in ("postgres://", "postgresql://"):
            if url.startswith(prefix):
                return "postgresql+psycopg://" + url[len(prefix) :]
        return url

    @property
    def apple_audience_list(self) -> list[str]:
        return [a.strip() for a in self.apple_audiences.split(",") if a.strip()]

    @property
    def plaid_enabled(self) -> bool:
        return bool(self.plaid_client_id and self.plaid_secret)


@lru_cache
def get_settings() -> Settings:
    return Settings()
