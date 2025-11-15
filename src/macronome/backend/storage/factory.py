"""
Storage factory - selects storage implementation based on configuration
"""
import logging
from macronome.settings import BackendConfig
from macronome.backend.storage.interface import StorageInterface
from macronome.backend.storage.local import LocalStorage
from macronome.backend.storage.supabase import SupabaseStorage

logger = logging.getLogger(__name__)


def get_storage() -> StorageInterface:
    """
    Get storage implementation based on configuration
    
    Returns:
        Storage implementation (LocalStorage or SupabaseStorage)
    """
    backend = BackendConfig.IMAGE_STORAGE_BACKEND
    
    if backend == "local":
        logger.info("✅ Using local filesystem storage")
        return LocalStorage()
    elif backend == "supabase":
        logger.info("✅ Using Supabase Storage")
        return SupabaseStorage()
    else:
        raise ValueError(f"Unknown storage backend: {backend}. Must be 'local' or 'supabase'")

