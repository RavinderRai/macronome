"""
Detection Node

First node in pantry scanner workflow.
Calls FastAPI detection endpoint via HTTP for inference.
"""
from __future__ import annotations
import logging
import io
import os

import httpx

from macronome.ai.schemas.pantry_scanner_schema import PantryItem, BoundingBox
from macronome.ai.core.nodes.base import Node
from macronome.ai.core.task import TaskContext
from macronome.ai.schemas.pantry_scanner_schema import PantryScanRequest
from macronome.settings import BackendConfig

logger = logging.getLogger(__name__)


class DetectionNode(Node):
    """
    First node in pantry scanner workflow.
    
    Detects pantry items in image by calling FastAPI /api/pantry/detect endpoint.
    This allows workflows running in Celery workers (separate processes) to use
    the shared model instance in the main API process.
    
    Input: PantryScanRequest (from task_context.event)
    Output: List[PantryItem] saved to task_context.nodes["DetectionNode"]
    """
    
    class OutputType(Node.OutputType):
        """DetectionNode outputs List[PantryItem]"""
        items: list[PantryItem]
    
    async def process(self, task_context: TaskContext) -> TaskContext:
        """
        Detect pantry items in image by calling detection API endpoint.
        
        Args:
            task_context: Contains PantryScanRequest in event
            
        Returns:
            TaskContext with detected items saved
        """
        request: PantryScanRequest = task_context.event
        
        logger.info("🔍 Detecting items in pantry image via API endpoint...")
        
        try:
            # Get API base URL (defaults to localhost:8000)
            api_base_url = os.getenv("API_BASE_URL", BackendConfig.API_BASE_URL)
            detect_url = f"{api_base_url}/api/pantry/detect"
            
            # Convert PIL Image to bytes for HTTP transmission
            # Ensure RGB mode (required for JPEG)
            pil_image = request.image
            if pil_image.mode != "RGB":
                pil_image = pil_image.convert("RGB")
            
            img_bytes_io = io.BytesIO()
            pil_image.save(img_bytes_io, format="JPEG")
            img_bytes_io.seek(0)
            
            # Make HTTP request to detection endpoint
            async with httpx.AsyncClient(timeout=60.0) as client:
                files = {"file": ("image.jpg", img_bytes_io, "image/jpeg")}
                params = {"conf_threshold": request.conf_threshold}
                
                response = await client.post(
                    detect_url,
                    files=files,
                    params=params
                )
                response.raise_for_status()
                
                result = response.json()
                items_dict = result["items"]
            
            # Convert response dicts back to PantryItem objects
            items = [
                PantryItem(
                    id=item_dict["id"],
                    bounding_box=BoundingBox(
                        x=item_dict["bounding_box"]["x"],
                        y=item_dict["bounding_box"]["y"],
                        width=item_dict["bounding_box"]["width"],
                        height=item_dict["bounding_box"]["height"],
                    ),
                    confidence=item_dict["confidence"],
                )
                for item_dict in items_dict
            ]
            
            logger.info(f"   Detected {len(items)} items")
            
            if not items:
                logger.warning("❌ No items detected")
            
            # Store output
            output = self.OutputType(items=items)
            self.save_output(output)
            
            return task_context
        
        except httpx.HTTPError as e:
            logger.error(f"❌ HTTP error calling detection endpoint: {e}")
            raise RuntimeError(f"Failed to call detection API: {e}")
        except Exception as e:
            logger.error(f"❌ Detection failed: {e}")
            raise
