from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from app.config import Settings, get_settings
from app.db import Database
from app.pricing import DEMO_PRICES, CoinGeckoPriceProvider, PriceProvider, PriceUnavailableError
from app.routes import account, trade
from app.trading import TradingError


def create_app(settings: Settings | None = None, database: Database | None = None, prices: PriceProvider | None = None) -> FastAPI:
    settings = settings or get_settings()
    database = database or Database(settings.database_url)
    database.create_all()
    if prices is None:
        prices = CoinGeckoPriceProvider() if settings.price_source == "coingecko" else DEMO_PRICES

    app = FastAPI(
        title="CrypToad API",
        version="0.2.0",
        description="Quote, trade, and history endpoints backed by a double-entry ledger. Prototype — no real funds.",
    )
    app.state.settings = settings
    app.state.database = database
    app.state.prices = prices

    @app.exception_handler(TradingError)
    async def trading_error(_: Request, exc: TradingError) -> JSONResponse:
        return JSONResponse(status_code=exc.status_code, content={"error": exc.code, "detail": str(exc)})

    @app.exception_handler(PriceUnavailableError)
    async def price_error(_: Request, exc: PriceUnavailableError) -> JSONResponse:
        return JSONResponse(status_code=503, content={"error": "price_unavailable", "detail": str(exc)})

    @app.get("/health", tags=["meta"])
    def health() -> dict[str, str]:
        return {"status": "ok"}

    app.include_router(trade.router)
    app.include_router(account.router)
    app.include_router(account.dev)
    return app

