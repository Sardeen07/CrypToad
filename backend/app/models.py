import uuid
from datetime import date, datetime, timezone

from sqlalchemy import JSON, BigInteger, Boolean, Date, DateTime, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def as_utc(value: datetime) -> datetime:
    """Normalizes to UTC. SQLite returns naive datetimes (stored as UTC); Postgres returns the session time zone."""
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)


def new_id() -> str:
    return str(uuid.uuid4())


# MARK: Accounts


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    # Optional: Sign in with Apple only shares an email on the first sign-in, and may share a relay address.
    email: Mapped[str | None] = mapped_column(String(255), unique=True, nullable=True)
    display_name: Mapped[str | None] = mapped_column(String(100), nullable=True)
    # Simulated: real KYC would come from an identity-verification partner. See docs/security.md.
    kyc_status: Mapped[str] = mapped_column(String(20), default="verified")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    # Accounts are deactivated, not deleted, so the ledger history stays balanced and auditable.
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class ApiToken(Base):
    """A signed-in session (one per device). Only the SHA-256 hash of the token is stored."""

    __tablename__ = "api_tokens"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    user: Mapped[User] = relationship()


class Identity(Base):
    """A sign-in method linked to a user, e.g. ``("apple", <Apple's stable user id>)``."""

    __tablename__ = "identities"
    __table_args__ = (UniqueConstraint("provider", "subject"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    provider: Mapped[str] = mapped_column(String(20))
    subject: Mapped[str] = mapped_column(String(255))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class UserSettings(Base):
    """Round-up and card settings. Stored server-side because purchases arrive from the
    card network or the bank feed, not from the app."""

    __tablename__ = "user_settings"

    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), primary_key=True)
    roundups_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    roundup_multiplier: Mapped[int] = mapped_column(Integer, default=1)
    allocation_btc: Mapped[int] = mapped_column(Integer, default=50)
    allocation_eth: Mapped[int] = mapped_column(Integer, default=30)
    allocation_usdc: Mapped[int] = mapped_column(Integer, default=20)
    card_frozen: Mapped[bool] = mapped_column(Boolean, default=False)


# MARK: Ledger


class LedgerAccount(Base):
    """One balance bucket. Kinds:

    - ``user_wallet``: a customer's balance of one asset (must never go negative)
    - ``liquidity``: our counterparty at the liquidity provider (Coinbase Prime, etc.)
    - ``fees``: conversion fee revenue
    - ``external``: money entering from outside (payroll, bank transfers)
    - ``merchant``: card spending leaving the system (settled with the card network)
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


# MARK: Activity


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


class Deposit(Base):
    """USDC arriving from outside (a paycheck, a bank transfer)."""

    __tablename__ = "deposits"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    entry_id: Mapped[int] = mapped_column(ForeignKey("journal_entries.id"))
    amount_minor: Mapped[int] = mapped_column(BigInteger)
    title: Mapped[str] = mapped_column(String(100))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, index=True)


class Purchase(Base):
    """A purchase that may carry a round-up.

    ``source="card"``: paid with the CrypToad card, so the price *and* the round-up come out of USDC.
    ``source="bank"``: seen in a linked bank account (Plaid), so only the round-up comes out of USDC.
    """

    __tablename__ = "purchases"
    __table_args__ = (UniqueConstraint("user_id", "external_id"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    entry_id: Mapped[int | None] = mapped_column(ForeignKey("journal_entries.id"), nullable=True)
    source: Mapped[str] = mapped_column(String(10))
    # Bank transaction id, so syncing the same transaction twice never rounds it up twice.
    external_id: Mapped[str | None] = mapped_column(String(100), nullable=True)
    merchant: Mapped[str] = mapped_column(String(100))
    amount_minor: Mapped[int] = mapped_column(BigInteger)
    round_up_minor: Mapped[int] = mapped_column(BigInteger, default=0)
    # [{"asset": "BTC", "quantity": "0.00000812", "price": "92340", "cost": "0.38"}, ...] as decimal strings.
    fills: Mapped[list] = mapped_column(JSON, default=list)
    # "completed", or "skipped" when there wasn't enough USDC for the round-up.
    status: Mapped[str] = mapped_column(String(20), default="completed")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, index=True)


class Investment(Base):
    """A dollar-cost-averaging buy split across assets by an allocation."""

    __tablename__ = "investments"
    __table_args__ = (UniqueConstraint("user_id", "idempotency_key"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_id)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    # None when the whole amount stayed in USDC (a 100% USDC allocation moves nothing).
    entry_id: Mapped[int | None] = mapped_column(ForeignKey("journal_entries.id"), nullable=True)
    amount_minor: Mapped[int] = mapped_column(BigInteger)
    fills: Mapped[list] = mapped_column(JSON, default=list)
    idempotency_key: Mapped[str | None] = mapped_column(String(100), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, index=True)


class BankLink(Base):
    """A bank account linked through Plaid. The access token is encrypted at rest (see app/crypto.py)."""

    __tablename__ = "bank_links"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), unique=True)
    provider: Mapped[str] = mapped_column(String(20), default="plaid")
    item_id: Mapped[str] = mapped_column(String(100))
    access_token: Mapped[str] = mapped_column(Text)
    institution_name: Mapped[str | None] = mapped_column(String(100), nullable=True)
    # Plaid /transactions/sync cursor: where the next sync picks up.
    cursor: Mapped[str | None] = mapped_column(Text, nullable=True)
    # Only purchases on or after this date are rounded up, so linking doesn't invest years of history at once.
    round_up_from: Mapped[date] = mapped_column(Date)
    linked_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    last_synced_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class AuditEvent(Base):
    """Append-only compliance log (logins, trades, deposits). Rows are never updated or deleted."""

    __tablename__ = "audit_events"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True, index=True)
    action: Mapped[str] = mapped_column(String(50))
    detail: Mapped[dict] = mapped_column(JSON, default=dict)
    flagged: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
