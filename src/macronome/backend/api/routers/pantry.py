"""
Pantry Router
ML scanning and CRUD operations for pantry items
"""
import logging
from typing import List
from fastapi import APIRouter, Depends, UploadFile, File, HTTPException, status
from supabase import Client

from macronome.backend.api.dependencies import get_current_user, get_supabase
from macronome.backend.database.models import PantryItem
from pydantic import BaseModel
from typing import Optional, List, Dict
from macronome.backend.services.pantry_scanner import PantryScannerService

logger = logging.getLogger(__name__)
router = APIRouter()


# API-specific schemas for pantry operations
class DetectedItem(BaseModel):
    """Detected pantry item from ML scan"""
    name: str
    category: Optional[str] = None
    confidence: float
    bounding_box: Optional[Dict[str, int]] = None


class PantryScanResponse(BaseModel):
    """Response from pantry scan endpoint"""
    items: List[DetectedItem]
    num_items: int


class PantryItemCreate(BaseModel):
    """Create pantry item"""
    name: str
    category: Optional[str] = None
    confirmed: bool = True
    confidence: Optional[float] = None


class PantryItemsResponse(BaseModel):
    """List of pantry items"""
    items: List[PantryItem]
    total: int


@router.post("/scan", tags=["ml", "pantry"], response_model=PantryScanResponse)
async def scan_pantry(
    file: UploadFile = File(...),
    user_id: str = Depends(get_current_user),
):
    """
    AI: Scan pantry image to detect food items
    
    Uses computer vision and LLM to identify pantry items from an image.
    Returns detected items with confidence scores.
    """
    logger.info(f"📸 Scanning pantry image for user {user_id}")
    
    # Validate file type
    if not file.content_type or not file.content_type.startswith("image/"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="File must be an image"
        )
    
    try:
        # Read image bytes
        image_bytes = await file.read()
        
        # Call pantry scanner service
        scanner = PantryScannerService()
        result = await scanner.scan_pantry(image_bytes)
        
        # Format response
        detected_items = [
            DetectedItem(
                name=item["name"],
                category=item.get("category"),
                confidence=item["confidence"],
                bounding_box=item.get("bounding_box")
            )
            for item in result["items"]
        ]
        
        logger.info(f"✅ Detected {len(detected_items)} items for user {user_id}")
        
        return PantryScanResponse(
            items=detected_items,
            num_items=len(detected_items)
        )
    
    except Exception as e:
        logger.error(f"❌ Pantry scan failed for user {user_id}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to scan image: {str(e)}"
        )


@router.get("/items", tags=["pantry"], response_model=PantryItemsResponse)
async def get_pantry_items(
    user_id: str = Depends(get_current_user),
    db: Client = Depends(get_supabase),
):
    """
    Get user's pantry items
    
    Returns all pantry items for the authenticated user.
    """
    logger.info(f"📦 Fetching pantry items for user {user_id}")
    
    try:
        result = db.table("pantry_items").select("*").eq("user_id", user_id).execute()
        
        items = [
            PantryItem(**item)
            for item in result.data
        ]
        
        logger.info(f"✅ Found {len(items)} pantry items for user {user_id}")
        
        return PantryItemsResponse(
            items=items,
            total=len(items)
        )
    
    except Exception as e:
        logger.error(f"❌ Failed to fetch pantry items for user {user_id}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to fetch pantry items: {str(e)}"
        )


@router.post("/items", tags=["pantry"], status_code=status.HTTP_201_CREATED)
async def add_pantry_items(
    items: List[PantryItemCreate],
    user_id: str = Depends(get_current_user),
    db: Client = Depends(get_supabase),
):
    """
    Add items to pantry
    
    Saves detected or manually added items to the user's pantry.
    """
    logger.info(f"➕ Adding {len(items)} items to pantry for user {user_id}")
    
    try:
        # Prepare items for insertion
        items_to_insert = [
            {
                "user_id": user_id,
                "name": item.name,
                "category": item.category,
                "confirmed": item.confirmed,
                "confidence": item.confidence,
            }
            for item in items
        ]
        
        result = db.table("pantry_items").insert(items_to_insert).execute()
        
        logger.info(f"✅ Added {len(result.data)} items to pantry for user {user_id}")
        
        return {
            "message": f"Added {len(result.data)} items to pantry",
            "items": result.data
        }
    
    except Exception as e:
        logger.error(f"❌ Failed to add pantry items for user {user_id}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to add pantry items: {str(e)}"
        )


@router.delete("/items/{item_id}", tags=["pantry"], status_code=status.HTTP_204_NO_CONTENT)
async def delete_pantry_item(
    item_id: str,
    user_id: str = Depends(get_current_user),
    db: Client = Depends(get_supabase),
):
    """
    Delete pantry item
    
    Removes an item from the user's pantry.
    """
    logger.info(f"🗑️  Deleting pantry item {item_id} for user {user_id}")
    
    try:
        # Verify ownership and delete
        result = db.table("pantry_items").delete().eq("id", item_id).eq("user_id", user_id).execute()
        
        if not result.data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Pantry item not found"
            )
        
        logger.info(f"✅ Deleted pantry item {item_id} for user {user_id}")
        
        return None
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Failed to delete pantry item {item_id} for user {user_id}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to delete pantry item: {str(e)}"
        )

