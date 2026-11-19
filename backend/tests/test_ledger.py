from decimal import Decimal

import httpx
import pytest

from app import ledger
from app.assets import Asset, display, from_minor, to_minor
from app.db import Database
from app.models import User
from app.pricing import CoinGeckoPriceProvider, PriceUnavailableError


@pytest.fixture
def session(database: Database):
    with database.session_factory() as session:
        session.add(User(email="a@example.com"))
        session.commit()
        yield session


def test_minor_units_are_exact() -> None:
    assert to_minor(Decimal("0.00198"), Asset.BTC) == 198_000
    assert to_minor(Decimal("1234.56"), Asset.USDC) == 1_234_560_000
    assert to_minor(Decimal("0.000000019"), Asset.BTC) == 1  # rounds down, never up
    assert from_minor(198_000, Asset.BTC) == Decimal("0.00198")
    assert display(from_minor(100_000_000, Asset.USDC)) == Decimal("100.00")


def test_unbalanced_entries_are_rejected(session) -> None:
    wallet = ledger.wallet(session, 1, Asset.USDC)
    external = ledger.get_account(session, kind="external", asset=Asset.USDC)
    with pytest.raises(ledger.UnbalancedEntryError):
        ledger.post(session, kind="deposit", memo="bad", lines=[ledger.Line(external, -100), ledger.Line(wallet, 99)])


def test_user_wallets_cannot_go_negative(session) -> None:
    wallet = ledger.wallet(session, 1, Asset.USDC)
    liquidity = ledger.get_account(session, kind="liquidity", asset=Asset.USDC)
    with pytest.raises(ledger.InsufficientFundsError):
        ledger.post(session, kind="trade", memo="overdraft", lines=[ledger.Line(wallet, -1), ledger.Line(liquidity, 1)])


def test_balances_are_sums_of_postings(session) -> None:
    wallet = ledger.wallet(session, 1, Asset.USDC)
    external = ledger.get_account(session, kind="external", asset=Asset.USDC)
    ledger.post(session, kind="deposit", memo="pay", lines=[ledger.Line(external, -500), ledger.Line(wallet, 500)])
    ledger.post(session, kind="deposit", memo="pay", lines=[ledger.Line(external, -250), ledger.Line(wallet, 250)])
    assert ledger.balance_minor(session, wallet) == 750
    assert ledger.balance_minor(session, external) == -750
    assert ledger.trial_balance(session) == {"USDC": 0}


def test_wallet_debits_are_netted_before_the_funds_check(session) -> None:
    """A purchase plus its round-up debits one wallet twice; each debit fits alone, the total doesn't."""
    wallet = ledger.wallet(session, 1, Asset.USDC)
    external = ledger.get_account(session, kind="external", asset=Asset.USDC)
    merchant = ledger.get_account(session, kind="merchant", asset=Asset.USDC)
    ledger.post(session, kind="deposit", memo="pay", lines=[ledger.Line(external, -430), ledger.Line(wallet, 430)])
    with pytest.raises(ledger.InsufficientFundsError):
        ledger.post(
            session, kind="purchase", memo="coffee + round-up",
            lines=[ledger.Line(wallet, -425), ledger.Line(wallet, -75), ledger.Line(merchant, 500)],
        )
    assert ledger.balance_minor(session, wallet) == 430


def test_coingecko_provider_parses_exact_decimal_and_caches() -> None:
    calls = []

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(request)
        assert set(request.url.params["ids"].split(",")) == {"bitcoin", "ethereum", "usd-coin"}
        return httpx.Response(200, text='{"bitcoin": {"usd": 92340.12}, "ethereum": {"usd": 3120.5}, "usd-coin": {"usd": 1}}')

    provider = CoinGeckoPriceProvider(client=httpx.Client(transport=httpx.MockTransport(handler)))
    assert provider.price_usd(Asset.BTC) == Decimal("92340.12")
    assert provider.price_usd(Asset.ETH) == Decimal("3120.5")
    assert len(calls) == 1  # one request for every asset, then served from cache


def test_coingecko_provider_errors_become_price_unavailable() -> None:
    provider = CoinGeckoPriceProvider(client=httpx.Client(transport=httpx.MockTransport(lambda r: httpx.Response(429))))
    with pytest.raises(PriceUnavailableError):
        provider.price_usd(Asset.ETH)
