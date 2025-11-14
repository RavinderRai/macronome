"""
Database session management
Uses Supabase for database operations
"""
from supabase import create_client, Client
from functools import lru_cache
import logging

from macronome.settings import BackendConfig

logger = logging.getLogger(__name__)


@lru_cache()
def get_supabase_client(use_service_key: bool = False) -> Client:
    """
    Get Supabase client (cached singleton)
    
    Args:
        use_service_key: If True, use service role key (admin access)
                        If False, use anon key (regular user access)
    
    Returns:
        Supabase client instance
    """
    if not BackendConfig.SUPABASE_URL or not BackendConfig.SUPABASE_KEY:
        raise ValueError("SUPABASE_URL and SUPABASE_KEY must be set in environment")
    
    key = BackendConfig.SUPABASE_SERVICE_KEY if use_service_key else BackendConfig.SUPABASE_KEY
    
    if use_service_key and not key:
        raise ValueError("SUPABASE_SERVICE_KEY must be set for admin operations")
    
    client = create_client(BackendConfig.SUPABASE_URL, key)
    logger.info(f"✅ Supabase client initialized ({'service role' if use_service_key else 'anon'})")
    
    return client


def get_db() -> Client:
    """
    FastAPI dependency for database access
    Use this in route handlers:
    
    @app.get("/items")
    async def get_items(db: Client = Depends(get_db)):
        ...
    """
    return get_supabase_client(use_service_key=False)


def get_admin_db() -> Client:
    """
    FastAPI dependency for admin database access (service role)
    Use this when you need to bypass RLS:
    
    @app.post("/admin/items")
    async def create_item(db: Client = Depends(get_admin_db)):
        ...
    """
    return get_supabase_client(use_service_key=True)

