"""Bearer-token auth.

Tokens are random 256-bit values; only their SHA-256 hash is stored, so a
database leak doesn't expose usable credentials. The production design
(passwords with Argon2id, MFA, short-lived JWTs) is in docs/security.md.
"""

import hashlib
import secrets

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.deps import get_session
from app.models import User

bearer = HTTPBearer(auto_error=False)


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def create_user(session: Session, email: str, kyc_status: str = "verified") -> tuple[User, str]:
    """Creates a user and returns ``(user, raw_token)``. The raw token is not stored."""
    token = secrets.token_urlsafe(32)
    user = User(email=email, token_hash=hash_token(token), kyc_status=kyc_status)
    session.add(user)
    session.commit()
    return user, token


def current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
    session: Session = Depends(get_session),
) -> User:
    if credentials is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Missing bearer token", headers={"WWW-Authenticate": "Bearer"})
    user = session.scalars(select(User).where(User.token_hash == hash_token(credentials.credentials))).first()
    if user is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid token", headers={"WWW-Authenticate": "Bearer"})
    return user
