"""
Storage module - provides image storage abstraction
Usage:
    from macronome.backend.storage import storage
    url = storage.upload_image(user_id, image_bytes, filename)
"""
from macronome.backend.storage.factory import get_storage
from macronome.backend.storage.interface import StorageInterface

# Initialize storage backend on module load
storage: StorageInterface = get_storage()

__all__ = ["storage", "StorageInterface"]

