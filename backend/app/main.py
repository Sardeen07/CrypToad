from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from app.apple import AppleIdentityVerifier
from app.config import Settings, get_settings
from app.crypto import SecretBox
from app.db import Database
from app.errors import ApiError
from app.plaid import PlaidClient
from app.pricing import DEMO_PRICES, CoinGeckoPriceProvider, PriceProvider, PriceUnavailableError
from app.routes import account, auth, bank, trade


def create_app(
    settings: Settings | None = None,
    database: Database | None = None,
    prices: PriceProvider | None = None,
    apple_verifier: AppleIdentityVerifier | None = None,
    plaid: PlaidClient | None = None,
) -> FastAPI:
    settings = settings or get_settings()
    database = database or Database(settings.database_url, pool_pre_ping=not settings.database_url.startswith("sqlite"))
    database.create_all()
    if prices is None:
        prices = CoinGeckoPriceProvider() if settings.price_source == "coingecko" else DEMO_PRICES
    if plaid is None and settings.plaid_enabled:
        plaid = PlaidClient(settings.plaid_client_id, settings.plaid_secret, settings.plaid_env)

    app = FastAPI(
        title="CrypToad API",
        version="0.3.0",
        description=(
            "Accounts (Sign in with Apple), balances, round-ups, DCA, quotes, trades, and Plaid bank linking, "
            "on a double-entry ledger. Prototype: simulated money, no real funds."
        ),
    )
    app.state.settings = settings
    app.state.database = database
    app.state.prices = prices
    app.state.apple_verifier = apple_verifier or AppleIdentityVerifier(settings.apple_audience_list)
    app.state.plaid = plaid
    app.state.secret_box = SecretBox(settings.secret_key)

    @app.exception_handler(ApiError)
    async def api_error(_: Request, exc: ApiError) -> JSONResponse:
        return JSONResponse(status_code=exc.status_code, content={"error": exc.code, "detail": str(exc)})

    @app.exception_handler(PriceUnavailableError)
    async def price_error(_: Request, exc: PriceUnavailableError) -> JSONResponse:
        return JSONResponse(status_code=503, content={"error": "price_unavailable", "detail": str(exc)})

    @app.get("/health", tags=["meta"])
    def health() -> dict[str, str]:
        return {"status": "ok"}

    @app.get("/api/info", tags=["meta"], summary="What this server supports")
    def info() -> dict:
        return {
            "version": app.version,
            "demoAccounts": settings.enable_dev_endpoints,
            "bankLinking": plaid is not None,
            "plaidEnvironment": plaid.env if plaid else None,
        }

    app.include_router(auth.router)
    app.include_router(trade.router)
    app.include_router(account.router)
    app.include_router(bank.router)
    app.include_router(account.dev)
    return app
