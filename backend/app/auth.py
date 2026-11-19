"""Accounts and sessions.

Each signed-in device gets its own random 256-bit bearer token; only the
SHA-256 hash is stored, so a database leak doesn't expose usable credentials,
and signing out revokes just that device. Users sign in with Apple (or, on demo
deployments, with a throwaway demo account). The production design (MFA,
short-lived JWTs) is in docs/security.md.
"""

import hashlib
import secrets

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.apple import AppleIdentity
from app.deps import get_session
from app.models import ApiToken, BankLink, Identity, User, UserSettings, utcnow

bearer = HTTPBearer(auto_error=False)


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def issue_token(session: Session, user: User) -> str:
    """Starts a new session for ``user`` and returns the raw token (shown once, never stored)."""
    token = secrets.token_urlsafe(32)
    session.add(ApiToken(user_id=user.id, token_hash=hash_token(token)))
    return token


def create_user(
    session: Session, email: str | None = None, kyc_status: str = "verified", display_name: str | None = None
) -> tuple[User, str]:
    """Creates a user with default settings and returns ``(user, raw_token)``."""
    user = User(email=email, kyc_status=kyc_status, display_name=display_name)
    session.add(user)
    session.flush()
    session.add(UserSettings(user_id=user.id))
    token = issue_token(session, user)
    session.commit()
    return user, token


def sign_in_with_apple(
    session: Session, identity: AppleIdentity, display_name: str | None = None
) -> tuple[User, str, bool]:
    """Finds or creates the user for an Apple identity. Returns ``(user, token, created)``."""
    link = session.scalars(select(Identity).where(Identity.provider == "apple", Identity.subject == identity.subject)).first()
    if link is not None:
        user = session.get(User, link.user_id)
        if user is not None and user.deleted_at is None:
            token = issue_token(session, user)
            session.commit()
            return user, token, False

    # New account (or the old one was deleted). Apple only shares the email on the first sign-in.
    email = identity.email if identity.email_verified else None
    if email and session.scalars(select(User).where(User.email == email)).first():
        email = None  # Already used by another account; don't fail the sign-in over it.
    user, token = create_user(session, email=email, display_name=display_name)
    if link is not None:
        link.user_id = user.id
    else:
        session.add(Identity(user_id=user.id, provider="apple", subject=identity.subject))
    session.commit()
    return user, token, True


def revoke_token(session: Session, raw_token: str) -> None:
    token = session.scalars(select(ApiToken).where(ApiToken.token_hash == hash_token(raw_token))).first()
    if token and token.revoked_at is None:
        token.revoked_at = utcnow()
        session.commit()


def deactivate_user(session: Session, user: User) -> None:
    """Account deletion. Personal data and sign-in methods are removed and every session is revoked;
    ledger rows stay (anonymized) because financial records must remain balanced and auditable."""
    now = utcnow()
    user.deleted_at = now
    user.email = None
    user.display_name = None
    for token in session.scalars(select(ApiToken).where(ApiToken.user_id == user.id, ApiToken.revoked_at.is_(None))):
        token.revoked_at = now
    for identity in session.scalars(select(Identity).where(Identity.user_id == user.id)):
        session.delete(identity)
    for link in session.scalars(select(BankLink).where(BankLink.user_id == user.id)):
        session.delete(link)
    session.commit()


def current_token(credentials: HTTPAuthorizationCredentials | None = Depends(bearer)) -> str:
    if credentials is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Missing bearer token", headers={"WWW-Authenticate": "Bearer"})
    return credentials.credentials


def current_user(raw_token: str = Depends(current_token), session: Session = Depends(get_session)) -> User:
    stmt = (
        select(User)
        .join(ApiToken, ApiToken.user_id == User.id)
        .where(ApiToken.token_hash == hash_token(raw_token), ApiToken.revoked_at.is_(None), User.deleted_at.is_(None))
    )
    user = session.scalars(stmt).first()
    if user is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid token", headers={"WWW-Authenticate": "Bearer"})
    return user
