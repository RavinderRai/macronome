"""
Storage interface for image uploads
Defines the protocol that all storage implementations must follow
"""
from typing import Protocol, Optional
from supabase import Client


class StorageInterface(Protocol):
    """Protocol for storage implementations"""
    
    def upload_image(
        self,
        user_id: str,
        image_bytes: bytes,
        filename: str,
        supabase_client: Optional[Client] = None
    ) -> str:
        """
        Upload image to storage
        
        Args:
            user_id: Clerk user ID
            image_bytes: Image file bytes
            filename: Original filename (will be sanitized)
            supabase_client: Optional Supabase client (for Supabase implementation)
        
        Returns:
            Storage URL
        """
        ...
    
    def get_image_url(
        self,
        bucket: str,
        path: str,
        supabase_client: Optional[Client] = None
    ) -> str:
        """
        Get public URL for an image
        
        Args:
            bucket: Storage bucket name (may be unused for local storage)
            path: File path
            supabase_client: Optional Supabase client (for Supabase implementation)
        
        Returns:
            Public URL to the image
        """
        ...
    
    def delete_image(
        self,
        bucket: str,
        path: str,
        supabase_client: Optional[Client] = None
    ) -> bool:
        """
        Delete image from storage
        
        Args:
            bucket: Storage bucket name (may be unused for local storage)
            path: File path
            supabase_client: Optional Supabase client (for Supabase implementation)
        
        Returns:
            True if deletion succeeded, False otherwise
        """
        ...

