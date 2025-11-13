from pydantic import BaseModel
from PIL.Image import Image
from typing import List


class BoundingBox(BaseModel):
    x: int
    y: int
    width: int
    height: int


class PantryItem(BaseModel):
    id: str
    bounding_box: BoundingBox
    confidence: float


class PantryScanRequest(BaseModel):
    """Request schema for pantry scanner workflow"""
    image: Image  # PIL Image
    conf_threshold: float = 0.25  # Detection confidence threshold
    crop_padding: int = 10  # Pixels to add around crops


class ClassifiedPantryItem(BaseModel):
    """Pantry item with classification"""
    item: PantryItem
    classification: str  # Food name from Vision LLM
    confidence: float  # Detection confidence


class PantryScanResult(BaseModel):
    """Final output from pantry scanner workflow"""
    items: List[ClassifiedPantryItem]
    num_items: int
