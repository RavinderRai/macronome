"""
Pantry Router
ML scanning and CRUD operations for pantry items
"""
import logging
import io
from typing import List, Optional, Dict, Any
from fastapi import APIRouter, Depends, UploadFile, File, HTTPException, status, Query
from supabase import Client
from PIL import Image

from macronome.backend.api.dependencies import get_current_user, get_supabase, get_supabase_admin
from macronome.backend.database.models import PantryItem
from macronome.backend.storage import storage
from macronome.backend.services.detection import DetectionService
from pydantic import BaseModel
from macronome.backend.services.pantry_scanner import PantryScannerService
from datetime import datetime

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
    image_id: Optional[str] = None  # ID of saved pantry image for linking items


class PantryItemCreate(BaseModel):
    """Create pantry item"""
    name: str
    category: Optional[str] = None
    confirmed: bool = True
    confidence: Optional[float] = None
    image_id: Optional[str] = None  # Link to pantry_images table


class PantryItemUpdate(BaseModel):
    """Update pantry item (partial update)"""
    name: Optional[str] = None
    category: Optional[str] = None
    confirmed: Optional[bool] = None
    confidence: Optional[float] = None
    image_id: Optional[str] = None


class PantryItemsResponse(BaseModel):
    """List of pantry items"""
    items: List[PantryItem]
    total: int


class DetectionResponse(BaseModel):
    """Response from detection endpoint"""
    items: List[Dict[str, Any]]  # List of PantryItem dicts


@router.post("/detect", tags=["ml", "pantry"], response_model=DetectionResponse)
async def detect_items(
    file: UploadFile = File(...),
    conf_threshold: float = Query(0.25, ge=0.0, le=1.0, description="Confidence threshold for detection"),
):
    """
    AI: Detect pantry items in image (inference-only endpoint)
    
    Low-level detection endpoint that uses YOLO model to detect items.
    Used by workflows and can be called independently.
    Does not save images or items to database - pure inference.
    
    Returns:
        DetectionResponse with detected items (bounding boxes, confidence scores)
    """
    logger.info(f"🔍 Detection request (conf_threshold={conf_threshold})")
    
    # Validate file type
    if not file.content_type or not file.content_type.startswith("image/"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="File must be an image"
        )
    
    try:
        # Read image bytes
        image_bytes = await file.read()
        
        # Convert to PIL Image
        pil_image = Image.open(io.BytesIO(image_bytes))
        if pil_image.mode != "RGB":
            pil_image = pil_image.convert("RGB")
        
        # Call DetectionService
        detected_items = await DetectionService.detect(pil_image, conf_threshold=conf_threshold)
        
        # Convert PantryItem objects to dicts for JSON serialization
        items_dict = [
            {
                "id": item.id,
                "bounding_box": {
                    "x": item.bounding_box.x,
                    "y": item.bounding_box.y,
                    "width": item.bounding_box.width,
                    "height": item.bounding_box.height,
                },
                "confidence": item.confidence,
            }
            for item in detected_items
        ]
        
        logger.info(f"✅ Detected {len(items_dict)} items")
        
        return DetectionResponse(items=items_dict)
    
    except Exception as e:
        logger.error(f"❌ Detection failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to detect items: {str(e)}"
        )


@router.post("/scan", tags=["ml", "pantry"], response_model=PantryScanResponse)
async def scan_pantry(
    file: UploadFile = File(...),
    user_id: str = Depends(get_current_user),
    db: Client = Depends(get_supabase_admin),  # Use admin to bypass RLS for writes
):
    """
    AI: Scan pantry image to detect food items
    
    Uses computer vision and LLM to identify pantry items from an image.
    Saves the image to storage and returns detected items with confidence scores.
    The image_id is included in the response for linking items to the image.
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
        
        # Save image to storage
        filename = file.filename or "pantry-scan.jpg"
        storage_url = storage.upload_image(user_id, image_bytes, filename)
        
        # Save image record to database
        image_record = {
            "user_id": user_id,
            "storage_url": storage_url,
            "uploaded_at": datetime.utcnow().isoformat(),
            "metadata": {
                "filename": filename,
                "content_type": file.content_type,
                "size": len(image_bytes),
            }
        }
        image_result = db.table("pantry_images").insert(image_record).execute()
        image_id = image_result.data[0]["id"] if image_result.data else None
        
        logger.info(f"💾 Saved pantry image {image_id} to storage: {storage_url}")
        
        # Call pantry scanner service
        scanner = PantryScannerService()
        result = await scanner.scan_pantry(image_bytes)
        
        # Format response - result is already a list of item dicts
        detected_items = [
            DetectedItem(
                name=item["name"],
                category=item.get("category"),
                confidence=item["confidence"],
                bounding_box=item.get("bounding_box")
            )
            for item in result  # result is List[Dict], not a dict with "items" key
        ]
        
        logger.info(f"✅ Detected {len(detected_items)} items for user {user_id}")
        
        return PantryScanResponse(
            items=detected_items,
            num_items=len(detected_items),
            image_id=image_id
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
    db: Client = Depends(get_supabase_admin),  # Use admin to bypass RLS for writes
):
    """
    Add items to pantry
    
    Saves detected or manually added items to the user's pantry.
    Can optionally link items to a pantry image via image_id.
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
                "image_id": item.image_id,  # Link to pantry_images if provided
                "detected_at": datetime.utcnow().isoformat() if item.confidence else None,
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


@router.patch("/items/{item_id}", tags=["pantry"], response_model=PantryItem)
async def update_pantry_item(
    item_id: str,
    updates: PantryItemUpdate,
    user_id: str = Depends(get_current_user),
    db: Client = Depends(get_supabase_admin),  # Use admin to bypass RLS for writes
):
    """
    Update pantry item (partial update)
    
    Updates only the provided fields in a pantry item.
    Can update name, category, confirmed status, confidence, or image_id.
    """
    logger.info(f"✏️  Updating pantry item {item_id} for user {user_id}")
    
    try:
        # Verify ownership first
        existing = db.table("pantry_items").select("id").eq("id", item_id).eq("user_id", user_id).limit(1).execute()
        
        if not existing.data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Pantry item not found"
            )
        
        # Prepare update data (exclude None values)
        update_data = updates.model_dump(exclude_none=True)
        
        if not update_data:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No fields to update"
            )
        
        # Add updated_at timestamp
        update_data["updated_at"] = datetime.utcnow().isoformat()
        
        # Update item
        result = db.table("pantry_items").update(update_data).eq("id", item_id).eq("user_id", user_id).execute()
        
        if not result.data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Pantry item not found"
            )
        
        updated_item = PantryItem(**result.data[0])
        logger.info(f"✅ Updated pantry item {item_id} for user {user_id}")
        
        return updated_item
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Failed to update pantry item {item_id} for user {user_id}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to update pantry item: {str(e)}"
        )


@router.delete("/items/{item_id}", tags=["pantry"], status_code=status.HTTP_204_NO_CONTENT)
async def delete_pantry_item(
    item_id: str,
    user_id: str = Depends(get_current_user),
    db: Client = Depends(get_supabase_admin),  # Use admin to bypass RLS for writes
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

