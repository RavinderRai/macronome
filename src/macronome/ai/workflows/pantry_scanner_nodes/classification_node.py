"""
Classification Node

Third node in pantry scanner workflow.
Uses Vision LLM to classify cropped food items.
"""
import logging
from typing import Any

from macronome.ai.core.nodes.agent import AgentNode, AgentConfig, ModelProvider
from macronome.ai.core.task import TaskContext
from macronome.ai.pantry_scanner.pipeline.food_classifier import FoodClassifier
from macronome.ai.schemas.pantry_scanner_schema import (
    ClassifiedPantryItem,
    PantryScanResult,
)
from macronome.ai.workflows.pantry_scanner_nodes.cropping_node import CroppingNode
from macronome.ai.workflows.pantry_scanner_nodes.detection_node import DetectionNode

logger = logging.getLogger(__name__)

# TODO: This is still using the old LLM calls, need to use the agent node with image inputs before can delete the old pantry scanner pipeline

class ClassificationNode(AgentNode):
    """
    Third node in pantry scanner workflow.
    
    Uses Vision LLM to classify cropped food items.
    
    Input: List[Image] from CroppingNode, List[PantryItem] from DetectionNode
    Output: PantryScanResult saved to task_context.nodes["ClassificationNode"]
    
    Note: This is an AgentNode because it uses Vision LLM for classification.
    However, the actual LLM call is handled by FoodClassifier, so we wrap it
    rather than using the agent.run() method directly.
    """
    
    def __init__(self, task_context: TaskContext = None):
        super().__init__(task_context)
        self._classifier = None
    
    class OutputType(AgentNode.OutputType):
        """ClassificationNode outputs PantryScanResult + history"""
        model_output: PantryScanResult
        history: Any
    
    def get_agent_config(self) -> AgentConfig:
        """
        Configure the agent for food classification.
        
        Uses Vision LLM via FoodClassifier wrapper.
        """
        return AgentConfig(
            model_provider=ModelProvider.OPENAI,  # FoodClassifier handles actual provider
            model_name="gpt-4o",  # Placeholder, FoodClassifier uses its own config
            output_type=PantryScanResult,
            system_prompt="You are a food classification expert.",
            name="ClassificationAgent",
            retries=2,
        )
    
    def _get_classifier(self) -> FoodClassifier:
        """Lazy load classifier"""
        if self._classifier is None:
            self._classifier = FoodClassifier()
        return self._classifier
    
    async def process(self, task_context: TaskContext) -> TaskContext:
        """
        Classify cropped food items using Vision LLM.
        
        Args:
            task_context: Contains CroppingNode output and DetectionNode output
            
        Returns:
            TaskContext with classified items saved
        """
        # Get cropped images
        cropping_output = self.get_output(CroppingNode)
        if not cropping_output or not cropping_output.cropped_images:
            logger.warning("No images to classify")
            result = PantryScanResult(items=[], num_items=0)
            output = self.OutputType(model_output=result, history=[])
            self.save_output(output)
            return task_context
        
        cropped_images = cropping_output.cropped_images
        
        # Get detected items
        detection_output = self.get_output(DetectionNode)
        if not detection_output or not detection_output.items:
            logger.warning("No items found for classification")
            result = PantryScanResult(items=[], num_items=0)
            output = self.OutputType(model_output=result, history=[])
            self.save_output(output)
            return task_context
        
        items = detection_output.items
        
        # Ensure we have matching counts
        if len(cropped_images) != len(items):
            logger.warning(
                f"Mismatch: {len(cropped_images)} cropped images vs {len(items)} items. "
                f"Using minimum count."
            )
            min_count = min(len(cropped_images), len(items))
            cropped_images = cropped_images[:min_count]
            items = items[:min_count]
        
        logger.info(f"🥘 Classifying {len(cropped_images)} items...")
        
        # Classify using FoodClassifier (Vision LLM)
        classifier = self._get_classifier()
        classifications = await classifier.food_classifier_batch(cropped_images)
        
        # Combine results
        classified_items = []
        for item, classification in zip(items, classifications):
            # Clean classification result
            classification_clean = classification.strip().lower()
            
            classified_item = ClassifiedPantryItem(
                item=item,
                classification=classification_clean,
                confidence=item.confidence
            )
            classified_items.append(classified_item)
        
        logger.info(f"   Classified {len(classified_items)} items")
        
        # Print detected items for debugging
        print(f"\n✅ Classification Results ({len(classified_items)} items):")
        for i, classified_item in enumerate(classified_items, 1):
            print(f"  {i}. {classified_item.classification} (confidence: {classified_item.confidence:.2f})")
        print()
        
        # Create final result
        result = PantryScanResult(
            items=classified_items,
            num_items=len(classified_items)
        )
        
        # Store output with empty history (FoodClassifier handles LLM internally)
        output = self.OutputType(model_output=result, history=[])
        self.save_output(output)
        
        # Mark workflow as complete
        task_context.should_stop = True
        
        return task_context

