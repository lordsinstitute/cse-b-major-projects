import logging

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session

from app.database import get_db
from app.security import decode_token, TokenError
from app.models import User
from app.roles import Role

bearer_scheme = HTTPBearer()

# Separate logger for access-control decisions. In production this should be
# routed to wherever the rest of the platform's audit trail lives (per the
# project guide: "audit logging of every AI decision" — this is the human
# side of that same principle, applied to permission checks).
audit_logger = logging.getLogger("rbac.audit")


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> User:
    token = credentials.credentials

    try:
        payload = decode_token(token, expected_type="access")
    except TokenError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(e),
            headers={"WWW-Authenticate": "Bearer"},
        )

    user_id = payload.get("sub")
    user = db.query(User).filter(User.id == int(user_id)).first()
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User no longer exists",
        )
    return user


def require_role(*allowed_roles: Role):
    """
    Use as a dependency to gate a route by role, e.g.:

        @router.get("/admin/users")
        def list_users(current_user: User = Depends(require_role(Role.ADMIN))):
            ...

    Every denial is logged with who tried, what route, and what role they had —
    that log is your evidence trail if anyone asks "who tried to access what."
    """

    def checker(request: Request, user: User = Depends(get_current_user)) -> User:
        if user.role not in allowed_roles:
            audit_logger.warning(
                "RBAC DENY user_id=%s email=%s role=%s path=%s required=%s",
                user.id,
                user.email,
                user.role.value,
                request.url.path,
                [r.value for r in allowed_roles],
            )
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You don't have permission to do that",
            )
        return user

    return checker