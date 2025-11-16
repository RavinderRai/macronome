"""
Cropping Node

Second node in pantry scanner workflow.
Crops detected items from image with padding.
"""
import logging

from pydantic import ConfigDict
from macronome.ai.core.nodes.base import Node
from macronome.ai.core.task import TaskContext
from macronome.ai.pantry_scanner.pipeline.cropper import crop_items_with_padding
from macronome.ai.schemas.pantry_scanner_schema import PantryScanRequest
from macronome.ai.workflows.pantry_scanner_nodes.detection_node import DetectionNode
from PIL.Image import Image

logger = logging.getLogger(__name__)

# TODO: the pantry_scanner.pipeline.cropper logic should be moved to this node rather than being imported from the old pipeline

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
        cropped_images = crop_items_with_padding(
            request.image,
            items,
            padding=request.crop_padding
        )
        
        logger.info(f"   Cropped {len(cropped_images)} images")
        
        # Store output
        output = self.OutputType(cropped_images=cropped_images)
        self.save_output(output)
        
        return task_context

