"""
Supabase Storage implementation
Used for production mode
"""
import os
import logging
from typing import Optional
from datetime import datetime
from urllib.parse import urlparse
from supabase import Client

from macronome.settings import BackendConfig

logger = logging.getLogger(__name__)


class SupabaseStorage:
    """Supabase Storage implementation"""
    
    def upload_image(
        self,
        user_id: str,
        image_bytes: bytes,
        filename: str,
        supabase_client: Optional[Client] = None
    ) -> str:
        """Upload image to Supabase Storage"""
        if not image_bytes:
            raise ValueError("image_bytes cannot be empty")
        
        if not filename:
            raise ValueError("filename cannot be empty")
        
        if supabase_client is None:
            from macronome.backend.database.session import get_supabase_client
            supabase_client = get_supabase_client(use_service_key=True)
        
        # Sanitize filename
        safe_filename = self._sanitize_filename(filename)
        timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
        file_path = f"{user_id}/{timestamp}_{safe_filename}"
        
        bucket = BackendConfig.PANTRY_IMAGES_BUCKET
        
        try:
            # Upload file
            response = supabase_client.storage.from_(bucket).upload(
                path=file_path,
                file=image_bytes,
                file_options={"content-type": "image/jpeg", "upsert": "false"}
            )
            
            # Get public URL
            public_url = supabase_client.storage.from_(bucket).get_public_url(file_path)
            
            logger.info(f"✅ Uploaded image to Supabase Storage: {bucket}/{file_path}")
            return public_url
        
        except Exception as e:
            logger.error(f"❌ Failed to upload image to Supabase: {e}")
            raise
    
    def get_image_url(
        self,
        bucket: str,
        path: str,
        supabase_client: Optional[Client] = None
    ) -> str:
        """Get public URL for an image in Supabase Storage"""
        if supabase_client is None:
            from macronome.backend.database.session import get_supabase_client
            supabase_client = get_supabase_client(use_service_key=False)
        
        try:
            # Get public URL from Supabase Storage
            response = supabase_client.storage.from_(bucket).get_public_url(path)
            return response
        except Exception as e:
            logger.error(f"Failed to get public URL for {bucket}/{path}: {e}")
            raise
    
    def delete_image(
        self,
        bucket: str,
        path: str,
        supabase_client: Optional[Client] = None
    ) -> bool:
        """Delete image from Supabase Storage"""
        if supabase_client is None:
            from macronome.backend.database.session import get_supabase_client
            supabase_client = get_supabase_client(use_service_key=True)
        
        try:
            # Extract path from full URL if needed
            if path.startswith("http"):
                parsed = urlparse(path)
                path = parsed.path.split(f"/{bucket}/", 1)[-1] if f"/{bucket}/" in parsed.path else path
            
            response = supabase_client.storage.from_(bucket).remove([path])
            
            logger.info(f"✅ Deleted image from Supabase Storage: {bucket}/{path}")
            return True
        
        except Exception as e:
            logger.error(f"❌ Failed to delete image from Supabase: {e}")
            return False
    
    @staticmethod
    def _sanitize_filename(filename: str) -> str:
        """Sanitize filename for safe storage"""
        # Remove path components
        filename = os.path.basename(filename)
        # Replace spaces and special chars
        filename = filename.replace(" ", "_")
        # Remove any remaining problematic characters
        safe_chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
        filename = "".join(c if c in safe_chars else "_" for c in filename)
        return filename

