"""
Pantry item detector using trained YOLO model
"""
from PIL import Image
from pathlib import Path
from typing import List
from ultralytics import YOLO
from ml.pantry_scanner.schemas import PantryItem, BoundingBox
import numpy as np


class PantryDetector:
    """YOLO-based pantry item detector"""
    
    def __init__(self, model_path: str = None):
        """
        Initialize detector with trained YOLO model
        
        Args:
            model_path: Path to trained model weights. If None, uses default trained model.
        """
        if model_path is None:
            # Use default trained model
            model_path = Path("ml/data/models/detector/pantry-detector/weights/best.pt")
        
        if not Path(model_path).exists():
            raise FileNotFoundError(f"Model not found at {model_path}. Please train the model first.")
        
        print(f"📥 Loading model from: {model_path}")
        self.model = YOLO(str(model_path))
        print("✅ Model loaded successfully")
    
    def detect(self, img: Image) -> List[PantryItem]:
        """
        Detect food items in pantry image
        
        Args:
            img: PIL Image of pantry
        
        Returns:
            List[PantryItem]: Detected pantry items with bounding boxes
        """
        # Run YOLO inference
        results = self.model(img)
        
        pantry_items = []
        
        # Parse YOLO results
        for result in results:
            boxes = result.boxes
            
            if boxes is None or len(boxes) == 0:
                # No detections
                return []
            
            for i in range(len(boxes)):
                # Get bounding box coordinates (in pixels)
                x1, y1, x2, y2 = boxes.xyxy[i].cpu().numpy()
                confidence = float(boxes.conf[i].cpu().numpy())
                class_id = int(boxes.cls[i].cpu().numpy())
                
                # Convert to our schema format
                bbox = BoundingBox(
                    x=int(x1),
                    y=int(y1),
                    width=int(x2 - x1),
                    height=int(y2 - y1)
                )
                
                pantry_item = PantryItem(
                    id=f"item_{i}",
                    bounding_box=bbox,
                    confidence=confidence
                )
                
                pantry_items.append(pantry_item)
        
        return pantry_items
    
    def detect_with_confidence_threshold(self, img: Image, conf_threshold: float = 0.25) -> List[PantryItem]:
        """
        Detect items with confidence thresholding
        
        Args:
            img: PIL Image
            conf_threshold: Minimum confidence score (default 0.25)
        
        Returns:
            List[PantryItem]: Filtered detections
        """
        all_items = self.detect(img)
        
        # Filter by confidence
        filtered_items = [
            item for item in all_items 
            if item.confidence >= conf_threshold
        ]
        
        return filtered_items


def pantry_detector(img: Image, conf_threshold: float = 0.25) -> List[PantryItem]:
    """
    Convenience function for detecting pantry items
    
    Args:
        img: PIL Image
        conf_threshold: Minimum confidence (default 0.25)
    
    Returns:
        List[PantryItem]: Detected items
    """
    detector = PantryDetector()
    return detector.detect_with_confidence_threshold(img, conf_threshold)
