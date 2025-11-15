"""
Local filesystem storage implementation
Used for development mode
"""
import os
import logging
from pathlib import Path
from typing import Optional
from datetime import datetime
from supabase import Client

logger = logging.getLogger(__name__)

# Local storage directory for dev
LOCAL_UPLOADS_DIR = Path("data/uploads")
LOCAL_UPLOADS_DIR.mkdir(parents=True, exist_ok=True)


class LocalStorage:
    """Local filesystem storage implementation"""
    
    def upload_image(
        self,
        user_id: str,
        image_bytes: bytes,
        filename: str,
        supabase_client: Optional[Client] = None
    ) -> str:
        """Upload image to local filesystem"""
        if not image_bytes:
            raise ValueError("image_bytes cannot be empty")
        
        if not filename:
            raise ValueError("filename cannot be empty")
        
        # Sanitize filename
        safe_filename = self._sanitize_filename(filename)
        timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
        file_path = f"{user_id}/{timestamp}_{safe_filename}"
        
        local_path = LOCAL_UPLOADS_DIR / file_path
        local_path.parent.mkdir(parents=True, exist_ok=True)
        
        with open(local_path, "wb") as f:
            f.write(image_bytes)
        
        logger.info(f"✅ Uploaded image to local storage: {local_path}")
        return str(local_path)
    
    def get_image_url(
        self,
        bucket: str,
        path: str,
        supabase_client: Optional[Client] = None
    ) -> str:
        """Get local file path as URL"""
        # Local file path
        return f"file://{path}"
    
    def delete_image(
        self,
        bucket: str,
        path: str,
        supabase_client: Optional[Client] = None
    ) -> bool:
        """Delete image from local filesystem"""
        try:
            # Handle both absolute and relative paths
            if os.path.isabs(path):
                file_path = Path(path)
            else:
                file_path = LOCAL_UPLOADS_DIR / path
            
            if file_path.exists():
                file_path.unlink()
                logger.info(f"✅ Deleted local image: {file_path}")
                return True
            else:
                logger.warning(f"⚠️  Local image not found: {file_path}")
                return False
        except Exception as e:
            logger.error(f"❌ Failed to delete local image: {e}")
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

