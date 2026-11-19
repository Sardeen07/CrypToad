"""One merged, newest-first feed of everything that moved a user's money."""

from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.assets import BASE_ASSET, Asset, display, from_minor
from app.models import Deposit, Investment, Purchase, Trade, User, as_utc
from app.schemas import ActivityOut, FillOut

ZERO = Decimal("0.00")


def _fills(raw: list[dict]) -> list[FillOut]:
    out = []
    for f in raw or []:
        asset = Asset(f["asset"])
        out.append(
            FillOut(
                asset=asset,
                quantity=display(Decimal(f["quantity"]), asset),
                price=display(Decimal(f["price"])),
                cost=display(Decimal(f["cost"])),
            )
        )
    return out


def _usd(minor: int) -> Decimal:
    return display(from_minor(minor, BASE_ASSET))


def activity(session: Session, user: User, limit: int = 100) -> list[ActivityOut]:
    items: list[ActivityOut] = []

    def newest(model):
        return session.scalars(
            select(model).where(model.user_id == user.id).order_by(model.created_at.desc()).limit(limit)
        )

    for d in newest(Deposit):
        items.append(
            ActivityOut(
                id=d.id, kind="deposit", title=d.title, date=as_utc(d.created_at), amount=_usd(d.amount_minor),
                round_up=ZERO, fee=ZERO, fills=[], status="completed",
            )
        )

    for p in newest(Purchase):
        completed = p.status == "completed"
        items.append(
            ActivityOut(
                id=p.id, kind="purchase", title=p.merchant, date=as_utc(p.created_at), amount=_usd(p.amount_minor),
                round_up=_usd(p.round_up_minor) if completed else ZERO, fee=ZERO, fills=_fills(p.fills),
                source=p.source, status=p.status,
            )
        )

    for t in newest(Trade):
        target = Asset(t.to_asset)
        items.append(
            ActivityOut(
                id=t.id, kind="trade", title=f"Bought {'Bitcoin' if target is Asset.BTC else 'Ethereum'}",
                date=as_utc(t.created_at), amount=_usd(t.spend_minor), round_up=ZERO, fee=_usd(t.fee_minor),
                fills=[
                    FillOut(
                        asset=target,
                        quantity=display(from_minor(t.quantity_minor, target), target),
                        price=display(Decimal(t.price)),
                        cost=_usd(t.spend_minor - t.fee_minor),
                    )
                ],
                status=t.status,
            )
        )

    for i in newest(Investment):
        items.append(
            ActivityOut(
                id=i.id, kind="dcaBuy", title="Auto-Investment (DCA)", date=as_utc(i.created_at),
                amount=_usd(i.amount_minor), round_up=ZERO, fee=ZERO, fills=_fills(i.fills), status="completed",
            )
        )

    items.sort(key=lambda item: (item.date, item.id), reverse=True)
    return items[:limit]
