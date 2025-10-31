"""
Crop detected pantry items from images using bounding boxes
"""
from __future__ import annotations

from PIL.Image import Image
from typing import List
from ml.pantry_scanner.schemas import PantryItem


def crop_item(img: Image, item: PantryItem) -> Image:
    """
    Crop a single pantry item from image using bounding box
    
    Args:
        img: Full pantry image (PIL Image)
        item: PantryItem with bounding box coordinates
    
    Returns:
        PIL Image of the cropped item
    """
    bbox = item.bounding_box
    
    # Calculate crop coordinates
    # PIL crop expects (left, top, right, bottom)
    left = bbox.x
    top = bbox.y
    right = bbox.x + bbox.width
    bottom = bbox.y + bbox.height
    
    # Crop the image
    cropped = img.crop((left, top, right, bottom))
    
    return cropped


def crop_items(img: Image, items: List[PantryItem]) -> List[Image]:
    """
    Crop multiple pantry items from image
    
    Args:
        img: Full pantry image (PIL Image)
        items: List of PantryItems with bounding boxes
    
    Returns:
        List of PIL Images (cropped items)
    """
    cropped_images = []
    
    for item in items:
        cropped = crop_item(img, item)
        cropped_images.append(cropped)
    
    return cropped_images


def crop_items_with_padding(
    img: Image, 
    items: List[PantryItem], 
    padding: int = 10
) -> List[Image]:
    """
    Crop items with padding around bounding boxes
    
    Args:
        img: Full pantry image (PIL Image)
        items: List of PantryItems with bounding boxes
        padding: Pixels to add around each bounding box
    
    Returns:
        List of PIL Images (cropped items with padding)
    """
    cropped_images = []
    
    for item in items:
        bbox = item.bounding_box
        img_width, img_height = img.size
        
        # Calculate coordinates with padding
        left = max(0, bbox.x - padding)
        top = max(0, bbox.y - padding)
        right = min(img_width, bbox.x + bbox.width + padding)
        bottom = min(img_height, bbox.y + bbox.height + padding)
        
        # Crop the image
        cropped = img.crop((left, top, right, bottom))
        cropped_images.append(cropped)
    
    return cropped_images
