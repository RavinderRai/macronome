"""
Pantry item detector using trained YOLO model
"""
from __future__ import annotations

from PIL.Image import Image
from pathlib import Path
from typing import List, Optional
from pydantic.v1 import NoneIsAllowedError
from ultralytics import YOLO
from ml.pantry_scanner.schemas import PantryItem, BoundingBox
from ml.shared.mlflow.model_registry import get_latest_model_path


class PantryDetector:
    """YOLO-based pantry item detector"""
    
    def __init__(self, model_path: Optional[str] = None):
        """
        Initialize detector with trained YOLO model
        
        Args:
            model_path: Path to trained model weights. If None, loads from latest MLflow run.
        """
        # If no model path provided, get latest from MLflow
        if model_path is None:
            model_path = get_latest_model_path(
                experiment_name="pantry_detector",
            )
        
        model_path_obj = Path(model_path)
        if not model_path_obj.exists():
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
        results = self.model.predict(img, conf=0.01)
        
        pantry_items = []
        
        # Parse YOLO results
        for result in results:
            boxes = result.boxes
            
            if boxes is None:
                continue

            num_detections = boxes.xyxy.shape[0] if hasattr(boxes, 'xyxy') and boxes.xyxy is not None else 0

            if num_detections == 0:
                continue
            
            for i in range(len(boxes)):
                # Get bounding box coordinates (in pixels)
                x1, y1, x2, y2 = boxes.xyxy[i].cpu().numpy()
                confidence = float(boxes.conf[i].cpu().numpy())
                
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
