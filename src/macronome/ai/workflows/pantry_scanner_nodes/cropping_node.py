"""
Cropping Node

Second node in pantry scanner workflow.
Crops detected items from image with padding.
"""
from __future__ import annotations
import logging
from typing import List

from pydantic import ConfigDict
from macronome.ai.core.nodes.base import Node
from macronome.ai.core.task import TaskContext
from macronome.ai.schemas.pantry_scanner_schema import PantryScanRequest, PantryItem
from macronome.ai.workflows.pantry_scanner_nodes.detection_node import DetectionNode
from PIL.Image import Image

logger = logging.getLogger(__name__)


class CroppingNode(Node):
    """
    Second node in pantry scanner workflow.
    
    Crops detected items from image with padding.
    
    Input: List[PantryItem] from DetectionNode
    Output: List[Image] (cropped images) saved to task_context.nodes["CroppingNode"]
    """
    
    class OutputType(Node.OutputType):
        """CroppingNode outputs List[Image]"""
        model_config = ConfigDict(arbitrary_types_allowed=True)
        
        cropped_images: list[Image]
    
    def _crop_item(self, img: Image, item: PantryItem) -> Image:
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
    
    def _crop_items(self, img: Image, items: List[PantryItem]) -> List[Image]:
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
            cropped = self._crop_item(img, item)
            cropped_images.append(cropped)
        
        return cropped_images
    
    def _crop_items_with_padding(
        self,
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
    
    async def process(self, task_context: TaskContext) -> TaskContext:
        """
        Crop detected items from image.
        
        Args:
            task_context: Contains DetectionNode output and PantryScanRequest
            
        Returns:
            TaskContext with cropped images saved
        """
        # Get detection results
        detection_output = self.get_output(DetectionNode)
        if not detection_output or not detection_output.items:
            logger.warning("No items to crop")
            output = self.OutputType(cropped_images=[])
            self.save_output(output)
            return task_context
        
        items = detection_output.items
        
        # Get original image from request
        request: PantryScanRequest = task_context.event
        
        logger.info(f"✂️  Cropping {len(items)} items...")
        
        # Crop items with padding
        cropped_images = self._crop_items_with_padding(
            request.image,
            items,
            padding=request.crop_padding
        )
        
        logger.info(f"   Cropped {len(cropped_images)} images")
        
        # Store output
        output = self.OutputType(cropped_images=cropped_images)
        self.save_output(output)
        
        return task_context

