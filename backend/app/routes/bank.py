from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session

from app import bank
from app.auth import current_user
from app.config import Settings
from app.crypto import SecretBox
from app.deps import get_app_settings, get_plaid, get_prices, get_secret_box, get_session
from app.models import User, as_utc
from app.plaid import PlaidClient
from app.pricing import PriceProvider
from app.schemas import BankExchangeIn, BankStatusOut, BankSyncOut, LinkTokenOut

router = APIRouter(prefix="/api/bank", tags=["bank"])


def status_out(session: Session, user: User, plaid: PlaidClient | None) -> BankStatusOut:
    link = bank.get_link(session, user)
    return BankStatusOut(
        linked=link is not None,
        available=plaid is not None,
        sandbox=plaid is not None and plaid.env == "sandbox",
        institution_name=link.institution_name if link else None,
        linked_at=as_utc(link.linked_at) if link else None,
        last_synced_at=as_utc(link.last_synced_at) if link and link.last_synced_at else None,
        round_up_from=link.round_up_from if link else None,
    )


@router.get("", response_model=BankStatusOut, summary="Bank link status")
def get_status(
    user: User = Depends(current_user), session: Session = Depends(get_session), plaid: PlaidClient | None = Depends(get_plaid)
) -> BankStatusOut:
    return status_out(session, user, plaid)


@router.post("/link-token", response_model=LinkTokenOut, summary="Start Plaid Link")
def link_token(user: User = Depends(current_user), plaid: PlaidClient | None = Depends(get_plaid)) -> LinkTokenOut:
    """Returns a `link_token` for the Plaid Link SDK. The app opens Link, the user picks their bank,
    and the app sends the resulting `public_token` to `POST /api/bank/exchange`."""
    return LinkTokenOut(link_token=bank.require_plaid(plaid).create_link_token(user.id))


@router.post("/exchange", response_model=BankStatusOut, summary="Finish Plaid Link")
def exchange(
    body: BankExchangeIn,
    user: User = Depends(current_user),
    session: Session = Depends(get_session),
    plaid: PlaidClient | None = Depends(get_plaid),
    box: SecretBox = Depends(get_secret_box),
    settings: Settings = Depends(get_app_settings),
) -> BankStatusOut:
    bank.link_bank(
        session, user, plaid=bank.require_plaid(plaid), box=box, settings=settings,
        public_token=body.public_token, institution_name=body.institution_name,
    )
    return status_out(session, user, plaid)


@router.post("/sandbox-link", response_model=BankStatusOut, summary="Link a Plaid sandbox test bank")
def sandbox_link(
    user: User = Depends(current_user),
    session: Session = Depends(get_session),
    plaid: PlaidClient | None = Depends(get_plaid),
    box: SecretBox = Depends(get_secret_box),
    settings: Settings = Depends(get_app_settings),
) -> BankStatusOut:
    """Sandbox only: links Plaid's test bank in one call, no Link UI needed."""
    bank.link_sandbox_bank(session, user, plaid=bank.require_plaid(plaid), box=box, settings=settings)
    return status_out(session, user, plaid)


@router.post("/sync", response_model=BankSyncOut, summary="Pull new bank transactions and round them up")
def sync(
    user: User = Depends(current_user),
    session: Session = Depends(get_session),
    plaid: PlaidClient | None = Depends(get_plaid),
    box: SecretBox = Depends(get_secret_box),
    prices: PriceProvider = Depends(get_prices),
) -> BankSyncOut:
    result = bank.sync(session, user, plaid=bank.require_plaid(plaid), box=box, prices=prices)
    return BankSyncOut(
        status=result.status, added=result.added, rounded_up=result.rounded_up,
        skipped=result.skipped, total_round_up=result.total_round_up,
    )


@router.delete("", status_code=status.HTTP_204_NO_CONTENT, summary="Unlink the bank account")
def unlink(
    user: User = Depends(current_user),
    session: Session = Depends(get_session),
    plaid: PlaidClient | None = Depends(get_plaid),
    box: SecretBox = Depends(get_secret_box),
) -> None:
    bank.unlink_bank(session, user, plaid=plaid, box=box)
