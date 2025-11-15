"""
Pantry Scanner Service
Wraps PantryScannerWorkflow for backend use
"""
import logging
from typing import List, Dict, Any, Union
from PIL import Image
import io

from macronome.ai.workflows.pantry_scanner_workflow import PantryScannerWorkflow
from macronome.ai.schemas.pantry_scanner_schema import ClassifiedPantryItem

logger = logging.getLogger(__name__)


class PantryScannerService:
    """
    Service wrapper for PantryScannerWorkflow
    
    Handles image processing, workflow execution, and result formatting
    for the pantry scanner AI feature.
    """
    
    def __init__(self):
        """Initialize the service with workflow instance"""
        self._workflow = PantryScannerWorkflow()
    
    async def scan_pantry(
        self,
        image: Union[bytes, Image.Image],
        conf_threshold: float = 0.25,
        crop_padding: int = 10
    ) -> List[Dict[str, Any]]:
        """
        Scan pantry image and return detected items
        
        Args:
            image: Image as bytes or PIL Image
            conf_threshold: Detection confidence threshold (0.0-1.0)
            crop_padding: Padding pixels around detected items
        
        Returns:
            List of detected pantry items with classifications
            Each item contains:
            - name: str - classified food name
            - category: str - food category (from LLM)
            - confidence: float - detection confidence
            - bounding_box: dict - detection box coordinates
        
        Raises:
            ValueError: If image is invalid
            Exception: If workflow execution fails
        """
        # Convert bytes to PIL Image if needed
        pil_image = self._prepare_image(image)
        
        # Create workflow request
        request_data = {
            "image": pil_image,
            "conf_threshold": conf_threshold,
            "crop_padding": crop_padding
        }
        
        logger.info(f"🔍 Starting pantry scan (conf={conf_threshold}, padding={crop_padding})")
        
        try:
            # Execute workflow
            task_context = await self._workflow.run_async(request_data)
            
            # Extract results from ClassificationNode output
            classification_output = task_context.nodes.get("ClassificationNode")
            if not classification_output:
                logger.warning("No classification output found")
                return []
            
            scan_result = classification_output.model_output
            classified_items = scan_result.items
            
            logger.info(f"✅ Pantry scan complete: {len(classified_items)} items detected")
            
            # Format results for backend
            formatted_items = self._format_results(classified_items)
            return formatted_items
        
        except Exception as e:
            logger.error(f"❌ Pantry scan failed: {e}")
            raise
    
    def _prepare_image(self, image: Union[bytes, Image.Image]) -> Image.Image:
        """
        Convert image bytes to PIL Image
        
        Args:
            image: Image as bytes or PIL Image
        
        Returns:
            PIL Image
        
        Raises:
            ValueError: If image is invalid
        """
        if isinstance(image, Image.Image):
            return image
        
        if isinstance(image, bytes):
            try:
                pil_image = Image.open(io.BytesIO(image))
                # Ensure RGB mode
                if pil_image.mode != "RGB":
                    pil_image = pil_image.convert("RGB")
                return pil_image
            except Exception as e:
                raise ValueError(f"Invalid image data: {e}")
        
        raise ValueError(f"Unsupported image type: {type(image)}")
    
    def _format_results(self, items: List[ClassifiedPantryItem]) -> List[Dict[str, Any]]:
        """
        Format workflow results for backend API
        
        Args:
            items: Classified pantry items from workflow
        
        Returns:
            List of formatted item dicts
        """
        formatted = []
        
        for item in items:
            # Extract category from classification (e.g., "apple" -> "fruit")
            # For now, use classification as-is; could add category mapping later
            classification = item.classification
            
            formatted_item = {
                "name": classification,
                "confidence": item.confidence,
                "bounding_box": {
                    "x": item.item.bounding_box.x,
                    "y": item.item.bounding_box.y,
                    "width": item.item.bounding_box.width,
                    "height": item.item.bounding_box.height
                },
                "detected_at": None,  # Will be set when saved to DB
                "confirmed": False,  # User needs to confirm
            }
            formatted.append(formatted_item)
        
        return formatted
