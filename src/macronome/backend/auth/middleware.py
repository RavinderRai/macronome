"""
Authentication middleware
"""
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from typing import Optional, Dict
import logging

from macronome.backend.auth.clerk import clerk_auth

logger = logging.getLogger(__name__)

# HTTP Bearer token scheme
security = HTTPBearer()


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security)
) -> Dict:
    """
    FastAPI dependency to get current authenticated user
    
    Usage:
        @app.get("/protected")
        async def protected_route(user: Dict = Depends(get_current_user)):
            user_id = user["sub"]  # Clerk user ID
            ...
    
    Args:
        credentials: HTTP Bearer token from Authorization header
    
    Returns:
        User payload from JWT token
    
    Raises:
        HTTPException: 401 if token is invalid or missing
    """
    token = credentials.credentials
    
    # Verify token
    payload = clerk_auth.verify_token(token)
    
    if not payload:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    logger.debug(f"✅ Authenticated user: {payload.get('sub')}")
    
    return payload


async def get_optional_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(HTTPBearer(auto_error=False))
) -> Optional[Dict]:
    """
    Optional authentication - returns user if token is present and valid, None otherwise
    
    Usage:
        @app.get("/public-or-private")
        async def route(user: Optional[Dict] = Depends(get_optional_user)):
            if user:
                # User is authenticated
                ...
            else:
                # Anonymous access
                ...
    """
    if not credentials:
        return None
    
    token = credentials.credentials
    payload = clerk_auth.verify_token(token)
    
    return payload


def get_user_id(user: Dict = Depends(get_current_user)) -> str:
    """
    Extract user ID from authenticated user
    
    Usage:
        @app.get("/items")
        async def get_items(user_id: str = Depends(get_user_id)):
            ...
    """
    return user["sub"]

