from fastapi import APIRouter, Depends, Response, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app import auth, trading
from app.apple import AppleIdentityVerifier
from app.auth import current_token, current_user
from app.deps import get_apple_verifier, get_session
from app.models import Identity, User
from app.routes.account import require_dev
from app.schemas import AppleSignInIn, DemoAccountIn, SessionOut, UserOut

router = APIRouter(prefix="/api", tags=["auth"])


def user_out(session: Session, user: User) -> UserOut:
    provider = session.scalars(select(Identity.provider).where(Identity.user_id == user.id)).first()
    return UserOut(
        user_id=user.id, email=user.email, display_name=user.display_name, kyc_status=user.kyc_status,
        sign_in_method=provider or "demo",
    )


@router.post("/auth/apple", response_model=SessionOut, summary="Sign in with Apple")
def sign_in_with_apple(
    body: AppleSignInIn,
    response: Response,
    session: Session = Depends(get_session),
    verifier: AppleIdentityVerifier = Depends(get_apple_verifier),
) -> SessionOut:
    """Verifies the Apple identity token and returns a session token. Creates the account on first sign-in."""
    identity = verifier.verify(body.identity_token, raw_nonce=body.nonce)
    user, token, created = auth.sign_in_with_apple(session, identity, display_name=body.full_name)
    trading.audit(session, user, "auth.sign_in", {"provider": "apple", "created": created})
    session.commit()
    if created:
        response.status_code = status.HTTP_201_CREATED
    return SessionOut(token=token, user=user_out(session, user), created=created)


@router.post(
    "/auth/demo",
    response_model=SessionOut,
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(require_dev)],
    summary="Create a demo account (demo servers only)",
)
def demo_account(body: DemoAccountIn | None = None, session: Session = Depends(get_session)) -> SessionOut:
    """A throwaway account with simulated USDC, for trying the app without Sign in with Apple."""
    body = body or DemoAccountIn()
    user, token = auth.create_user(session, display_name="Demo Toad")
    if body.starting_balance > 0:
        trading.deposit(session, user, body.starting_balance, title="Welcome Bonus (Demo)")
    return SessionOut(token=token, user=user_out(session, user), created=True)


@router.post("/auth/logout", status_code=status.HTTP_204_NO_CONTENT, summary="Sign out this device")
def logout(token: str = Depends(current_token), _: User = Depends(current_user), session: Session = Depends(get_session)) -> None:
    auth.revoke_token(session, token)


@router.get("/me", response_model=UserOut, summary="The signed-in user")
def me(user: User = Depends(current_user), session: Session = Depends(get_session)) -> UserOut:
    return user_out(session, user)


@router.delete("/me", status_code=status.HTTP_204_NO_CONTENT, summary="Delete my account")
def delete_me(user: User = Depends(current_user), session: Session = Depends(get_session)) -> None:
    """Removes personal data, sign-in methods, and bank links, and signs out every device.
    Required by App Store guideline 5.1.1(v) for apps that let users create accounts."""
    trading.audit(session, user, "account.deleted", {})
    auth.deactivate_user(session, user)
