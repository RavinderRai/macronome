"""
Pantry Scanner Service - Orchestrates the full pipeline
"""
from __future__ import annotations

from PIL import Image
from typing import List, Dict
import asyncio
import logging
from macronome.ai.pantry_scanner.pipeline.pantry_detector import PantryDetector
from macronome.ai.pantry_scanner.pipeline.cropper import crop_items_with_padding
from macronome.ai.pantry_scanner.pipeline.food_classifier import FoodClassifier
from macronome.ai.pantry_scanner.schemas import PantryItem

logger = logging.getLogger(__name__)

class PantryScannerService:
    """
    Service that orchestrates the full pantry scanning pipeline:
    1. Detect items in image (YOLO)
    2. Crop detected items
    3. Classify cropped items (Vision LLM)
    """
    
    def __init__(self):
        """Initialize the service with all components"""
        self.detector = PantryDetector()
        self.classifier = FoodClassifier()
    
    async def scan_pantry(self, img: Image, conf_threshold: float = 0.01, crop_padding: int = 10) -> List[Dict]:
        """
        Full pipeline: Detect → Crop → Classify
        
        Args:
            img: PIL Image of pantry
            conf_threshold: Minimum confidence for detection (default 0.25)
            crop_padding: Pixels to add around crops (default 10)
        
        Returns:
            List of detected items with classifications:
            [
                {
                    "item": PantryItem,
                    "classification": "chicken breast",
                    "confidence": 0.85
                },
                ...
            ]
        """
        # Step 1: Detect items
        logger.info("🔍 Detecting items in pantry image...")
        items = self.detector.detect_with_confidence_threshold(img, conf_threshold)
        logger.info(f"   Detected {len(items)} items")
        
        if not items:
            logger.error("❌ No items detected")
            return []
        
        # Step 2: Crop detected items
        logger.info(f"✂️  Cropping {len(items)} items...")
        cropped_images = crop_items_with_padding(img, items, padding=crop_padding)
        
        # Step 3: Classify cropped items
        logger.info("🥘 Classifying items...")
        logger.warning("For testing purposes, only classifying the first 5 items, make sure to remove this before production")
        classifications = await self.classifier.food_classifier_batch(cropped_images[0:5])
        
        # Combine results
        results = []
        for i, (item, classification) in enumerate(zip(items, classifications)):
            # Clean classification result
            classification = classification.strip().lower()
            
            results.append({
                "item": item,
                "classification": classification,
                "confidence": item.confidence,
                "index": i
            })
        
        return results
    
    async def get_detections_only(self, img: Image, conf_threshold: float = 0.25) -> List[PantryItem]:
        """
        Only detect items, no classification
        
        Args:
            img: PIL Image
            conf_threshold: Minimum confidence
        
        Returns:
            List[PantryItem]: Detected items with bounding boxes
        """
        return self.detector.detect_with_confidence_threshold(img, conf_threshold)
    
    async def classify_items(self, cropped_images: List[Image]) -> List[str]:
        """
        Classify already-cropped images
        
        Args:
            cropped_images: List of PIL Images (cropped items)
        
        Returns:
            List[str]: Classifications
        """
        return await self.classifier.food_classifier_batch(cropped_images)


if __name__ == "__main__":
    # Example usage
    async def main():
        service = PantryScannerService()
        
        # Load an image
        img = Image.open("data/processed/yolo_format/valid/images/img_0000.jpg")
        
        # Run full pipeline
        results = await service.scan_pantry(img)
        
        # Print results
        for result in results:
            print(f"{result['classification']} (conf: {result['confidence']:.2f})")
    
    asyncio.run(main())

