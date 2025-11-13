"""
Detection Node

First node in pantry scanner workflow.
Uses YOLO model to detect pantry items in image.
"""
import logging

from macronome.ai.core.nodes.base import Node
from macronome.ai.core.task import TaskContext
from macronome.ai.pantry_scanner.pipeline.pantry_detector import PantryDetector
from macronome.ai.schemas.pantry_scanner_schema import PantryScanRequest, PantryItem

logger = logging.getLogger(__name__)

# TODO: the pantry_scanner.pipeline.pantry_detector logic should be moved to this node rather than being imported from the old pipeline

class DetectionNode(Node):
    """
    First node in pantry scanner workflow.
    
    Detects pantry items in image using YOLO model.
    
    Input: PantryScanRequest (from task_context.event)
    Output: List[PantryItem] saved to task_context.nodes["DetectionNode"]
    """
    
    def __init__(self, task_context: TaskContext = None):
        super().__init__(task_context)
        self._detector = None
    
    class OutputType(Node.OutputType):
        """DetectionNode outputs List[PantryItem]"""
        items: list[PantryItem]
    
    def _get_detector(self) -> PantryDetector:
        """Lazy load detector (expensive operation)"""
        if self._detector is None:
            self._detector = PantryDetector()
        return self._detector
    
    async def process(self, task_context: TaskContext) -> TaskContext:
        """
        Detect pantry items in image.
        
        Args:
            task_context: Contains PantryScanRequest in event
            
        Returns:
            TaskContext with detected items saved
        """
        request: PantryScanRequest = task_context.event
        
        logger.info("🔍 Detecting items in pantry image...")
        
        # Get detector and run detection
        detector = self._get_detector()
        items = detector.detect_with_confidence_threshold(
            request.image,
            conf_threshold=request.conf_threshold
        )
        
        logger.info(f"   Detected {len(items)} items")
        
        if not items:
            logger.warning("❌ No items detected")
        
        # Store output
        output = self.OutputType(items=items)
        self.save_output(output)
        
        return task_context

