from __future__ import annotations
import logging
from pathlib import Path
from PIL.Image import Image
from typing import List
from ultralytics import YOLO

from macronome.ai.schemas.pantry_scanner_schema import PantryItem, BoundingBox
from macronome.ai.shared.mlflow.model_registry import get_latest_model_path

logger = logging.getLogger(__name__)


class DetectionService:
    """
    Service for detecting pantry items in images using YOLO model.
    
    Uses singleton pattern to load model once and reuse across requests.
    Forces CPU device to avoid MPS (Apple Silicon) crashes.
    """

    _model = None

    @classmethod
    def _load_model(cls) -> YOLO:
        """
        Load YOLO model from MLflow registry.
        
        Returns:
            YOLO model instance
            
        Raises:
            FileNotFoundError: If model not found
        """
        model_path = get_latest_model_path(experiment_name="pantry_detector")
        model_path_obj = Path(model_path)
        
        if not model_path_obj.exists():
            raise FileNotFoundError(
                f"Model not found at {model_path}. Please train the model first."
            )
        
        logger.info(f"📥 Loading YOLO model from: {model_path}")
        # Force CPU device to avoid MPS crashes (ultralytics has issues with MPS)
        model = YOLO(str(model_path))
        logger.info("✅ Model loaded successfully (using CPU)")
        
        return model

    @classmethod
    def get_model(cls) -> YOLO:
        """
        Get YOLO model instance (singleton pattern).
        
        Returns:
            YOLO model instance
        """
        if cls._model is None:
            cls._model = cls._load_model()
        return cls._model

    @classmethod
    async def detect(
        cls, 
        image: Image.Image, 
        conf_threshold: float = 0.25
    ) -> List[PantryItem]:
        """
        Detect pantry items in image using YOLO model.
        
        Args:
            image: PIL Image of pantry
            conf_threshold: Minimum confidence score (default 0.25)
        
        Returns:
            List[PantryItem]: Detected pantry items with bounding boxes
        """
        model = cls.get_model()
        
        # Run YOLO inference (force CPU to avoid MPS crashes)
        logger.debug(f"🔍 Running detection with conf_threshold={conf_threshold}")
        results = model.predict(image, conf=conf_threshold, device='cpu')
        
        pantry_items = []
        
        # Parse YOLO results
        for result in results:
            boxes = result.boxes
            
            if boxes is None:
                continue

            num_detections = (
                boxes.xyxy.shape[0] 
                if hasattr(boxes, 'xyxy') and boxes.xyxy is not None 
                else 0
            )

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
        
        logger.info(f"✅ Detected {len(pantry_items)} items")
        return pantry_items