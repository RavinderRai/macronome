"""
FastAPI Dependencies
Shared dependencies for authentication, database access, etc.
"""
from typing import Optional
from fastapi import Depends, HTTPException, status, Header
from supabase import Client

from macronome.backend.auth.clerk import clerk_auth
from macronome.backend.database.session import get_db


async def get_current_user(authorization: Optional[str] = Header(None)) -> str:
    """
    Verify Clerk JWT and return user_id
    
    Args:
        authorization: Bearer token from Authorization header
        
    Returns:
        user_id: Clerk user ID
        
    Raises:
        HTTPException: 401 if token is invalid or missing
    """
    if not authorization:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing authorization header",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    # Extract token from "Bearer <token>"
    try:
        scheme, token = authorization.split()
        if scheme.lower() != "bearer":
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid authentication scheme",
                headers={"WWW-Authenticate": "Bearer"},
            )
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authorization header format",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    # Verify token
    user_data = clerk_auth.verify_token(token)
    if not user_data:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    return user_data["sub"]  # Clerk user ID


def get_supabase() -> Client:
    """
    Get Supabase client for database operations
    
    Returns:
        Supabase client instance
    """
    return get_db()


async def get_user_id(user_id: str = Depends(get_current_user)) -> str:
    """
    Convenience dependency that just returns user_id
    Useful for endpoints that only need the user_id
    """
    return user_id

