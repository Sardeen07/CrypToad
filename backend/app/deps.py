from collections.abc import Iterator

from fastapi import Request
from sqlalchemy.orm import Session

from app.config import Settings
from app.pricing import PriceProvider


def get_session(request: Request) -> Iterator[Session]:
    yield from request.app.state.database.session()


def get_prices(request: Request) -> PriceProvider:
    return request.app.state.prices


def get_app_settings(request: Request) -> Settings:
    return request.app.state.settings
