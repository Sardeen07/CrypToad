from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app import trading
from app.assets import display
from app.auth import create_user, current_user
from app.config import Settings
from app.deps import get_app_settings, get_session
from app.models import User
from app.schemas import BalancesOut, DepositIn, DevUserIn, DevUserOut

router = APIRouter(prefix="/api", tags=["account"])


@router.get("/balances", response_model=BalancesOut)
def get_balances(user: User = Depends(current_user), session: Session = Depends(get_session)) -> BalancesOut:
    return BalancesOut(balances={asset: display(amount, asset) for asset, amount in trading.balances(session, user).items()})


def require_dev(settings: Settings = Depends(get_app_settings)) -> None:
    if not settings.enable_dev_endpoints:
        raise HTTPException(status.HTTP_404_NOT_FOUND)


dev = APIRouter(prefix="/api/dev", tags=["dev"], dependencies=[Depends(require_dev)])


@dev.post("/users", response_model=DevUserOut, status_code=status.HTTP_201_CREATED)
def dev_create_user(body: DevUserIn, session: Session = Depends(get_session)) -> DevUserOut:
    """Creates a test user and returns its API token. Disabled when CRYPTOAD_ENABLE_DEV_ENDPOINTS=false."""
    user, token = create_user(session, body.email, kyc_status=body.kyc_status)
    return DevUserOut(user_id=user.id, email=user.email, token=token)


@dev.post("/deposit", response_model=BalancesOut)
def dev_deposit(body: DepositIn, user: User = Depends(current_user), session: Session = Depends(get_session)) -> BalancesOut:
    """Simulates a paycheck landing as USDC (in production this is the payroll / bank-transfer webhook)."""
    trading.deposit(session, user, body.amount)
    return get_balances(user, session)
