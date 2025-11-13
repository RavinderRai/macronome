from macronome.ai.core.workflow import Workflow
from macronome.ai.core.schema import WorkflowSchema, NodeConfig
from macronome.ai.schemas.pantry_scanner_schema import PantryScanRequest
from macronome.ai.workflows.pantry_scanner_nodes.detection_node import DetectionNode
from macronome.ai.workflows.pantry_scanner_nodes.cropping_node import CroppingNode
from macronome.ai.workflows.pantry_scanner_nodes.classification_node import ClassificationNode

"""
Pantry Scanner Workflow

Simple 3-node workflow for scanning pantry images:
1. Detection (YOLO) - detects items with bounding boxes
2. Cropping - crops detected items from image
3. Classification (Vision LLM) - classifies cropped items
"""


class PantryScannerWorkflow(Workflow):
    """
    Three-node workflow for pantry item detection and classification.
    
    Flow:
    1. Detection: YOLO model detects pantry items with bounding boxes
    2. Cropping: Crop detected items from image with padding
    3. Classification: Vision LLM classifies each cropped item
    
    Features:
    - YOLO-based object detection
    - Vision LLM for food classification
    - Simple linear pipeline (no routing needed)
    """
    
    workflow_schema = WorkflowSchema(
        description="Pantry scanner workflow with detection and classification",
        event_schema=PantryScanRequest,
        start=DetectionNode,
        nodes=[
            # Node 1: Detect items (YOLO)
            NodeConfig(
                node=DetectionNode,
                connections=[CroppingNode],
                description="Detect pantry items using YOLO model"
            ),
            
            # Node 2: Crop items
            NodeConfig(
                node=CroppingNode,
                connections=[ClassificationNode],
                description="Crop detected items from image with padding"
            ),
            
            # Node 3: Classify items (Vision LLM)
            NodeConfig(
                node=ClassificationNode,
                connections=[],  # Terminal node
                description="Classify cropped items using Vision LLM"
            ),
        ],
    )
