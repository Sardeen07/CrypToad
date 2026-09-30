import uuid
from datetime import datetime, timezone

from sqlalchemy import JSON, BigInteger, Boolean, DateTime, ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def as_utc(value: datetime) -> datetime:
    """Normalizes to UTC. SQLite returns naive datetimes (stored as UTC); Postgres returns the session time zone."""
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)


def new_id() -> str:
    return str(uuid.uuid4())


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    email: Mapped[str] = mapped_column(String(255), unique=True)
    # SHA-256 of the API token. The raw token is shown once and never stored.
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    kyc_status: Mapped[str] = mapped_column(String(20), default="verified")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class LedgerAccount(Base):
    """One balance bucket. Kinds:

    - ``user_wallet``: a customer's balance of one asset (must never go negative)
    - ``liquidity``: our counterparty at the liquidity provider (Coinbase Prime, etc.)
    - ``fees``: conversion fee revenue
    - ``external``: money entering from outside (payroll, bank transfers)
    """

    __tablename__ = "ledger_accounts"
    __table_args__ = (UniqueConstraint("owner_id", "kind", "asset"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    owner_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True)
    kind: Mapped[str] = mapped_column(String(20))
    asset: Mapped[str] = mapped_column(String(10))


class JournalEntry(Base):
    """A group of postings that must net to zero for every asset (double-entry)."""

    __tablename__ = "journal_entries"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    kind: Mapped[str] = mapped_column(String(20))
    memo: Mapped[str] = mapped_column(String(255), default="")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    postings: Mapped[list["Posting"]] = relationship(back_populates="entry", cascade="all, delete-orphan")


class Posting(Base):
    __tablename__ = "postings"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    entry_id: Mapped[int] = mapped_column(ForeignKey("journal_entries.id"), index=True)
    account_id: Mapped[int] = mapped_column(ForeignKey("ledger_accounts.id"), index=True)
    asset: Mapped[str] = mapped_column(String(10))
    # Signed integer minor units: positive = credit to the account's balance.
    amount_minor: Mapped[int] = mapped_column(BigInteger)

    entry: Mapped[JournalEntry] = relationship(back_populates="postings")


class Quote(Base):
    __tablename__ = "quotes"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    from_asset: Mapped[str] = mapped_column(String(10))
    to_asset: Mapped[str] = mapped_column(String(10))
    spend_minor: Mapped[int] = mapped_column(BigInteger)
    fee_minor: Mapped[int] = mapped_column(BigInteger)
    quantity_minor: Mapped[int] = mapped_column(BigInteger)
    # Stored as a string to keep the exact decimal price.
    price: Mapped[str] = mapped_column(String(40))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class Trade(Base):
    __tablename__ = "trades"
    __table_args__ = (UniqueConstraint("user_id", "idempotency_key"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    quote_id: Mapped[str] = mapped_column(ForeignKey("quotes.id"), unique=True)
    entry_id: Mapped[int] = mapped_column(ForeignKey("journal_entries.id"))
    from_asset: Mapped[str] = mapped_column(String(10))
    to_asset: Mapped[str] = mapped_column(String(10))
    spend_minor: Mapped[int] = mapped_column(BigInteger)
    fee_minor: Mapped[int] = mapped_column(BigInteger)
    quantity_minor: Mapped[int] = mapped_column(BigInteger)
    price: Mapped[str] = mapped_column(String(40))
    status: Mapped[str] = mapped_column(String(20), default="completed")
    idempotency_key: Mapped[str | None] = mapped_column(String(100), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, index=True)


class AuditEvent(Base):
    """Append-only compliance log (logins, trades, deposits). Rows are never updated or deleted."""

    __tablename__ = "audit_events"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True, index=True)
    action: Mapped[str] = mapped_column(String(50))
    detail: Mapped[dict] = mapped_column(JSON, default=dict)
    flagged: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
