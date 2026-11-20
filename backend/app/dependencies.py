from fastapi import Depends, Header
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_db
from app.shared.security import decode_access_token
from app.shared.exceptions import UnauthorizedException

security_scheme = HTTPBearer(auto_error=False)

async def get_current_user_id(credentials: HTTPAuthorizationCredentials = Depends(security_scheme)) -> str:
    if not credentials:
        raise UnauthorizedException("Authentication token required")
    payload = decode_access_token(credentials.credentials)
    if not payload or "sub" not in payload:
        raise UnauthorizedException("Invalid or expired session token")
    return payload["sub"]
