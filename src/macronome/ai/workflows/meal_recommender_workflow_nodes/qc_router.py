import logging

from macronome.ai.core.nodes.router import BaseRouter
from macronome.ai.core.task import TaskContext
from macronome.ai.schemas.recipe_schema import NutritionInfo
from macronome.ai.schemas.meal_recommender_constraints_schema import NormalizedConstraints
from macronome.ai.schemas.workflow_schemas import ModifiedRecipe
from macronome.ai.core.nodes.base import Node

logger = logging.getLogger(__name__)

"""
QC Router

Router node that validates the modified recipe meets quality standards.
Routes to ExplanationAgent if good, or FailureAgent if issues found.
"""

# TODO: Rename now that we aren't using refinement agent

class QCRouter(BaseRouter):
    """
    Seventh node in meal recommendation workflow.
    
    Quality control router that validates the modified recipe.
    
    Input: ModifiedRecipe and NutritionInfo from previous nodes
    Output: Routes to either ExplanationAgent or FailureAgent
    
    Checks:
    - Macro tolerances (±15% of target)
    - Calorie range fit
    - Recipe coherence
    - Minimum quality standards
    """
    
    def __init__(self, task_context: TaskContext = None):
        super().__init__(task_context)
        self.routes = []
        self.fallback = None
    
    async def process(self, task_context: TaskContext) -> TaskContext:
        """
        Router nodes don't modify task_context, just determine next node.
        """
        return task_context
    
    def route(self, task_context: TaskContext) -> Node:
        """
        Determine next node based on quality checks.
        
        Args:
            task_context: Current task context
            
        Returns:
            Next node instance (lazy-loaded from task_context metadata)
        """
        # Get required data
        # Get OutputType objects and extract model_output
        modification_output = task_context.nodes.get("ModificationAgent")
        if modification_output and hasattr(modification_output, 'model_output'):
            modified: ModifiedRecipe = modification_output.model_output
        else:
            modified = modification_output  # Fallback if already ModifiedRecipe
        
        nutrition: NutritionInfo = task_context.nodes.get("NutritionNode")
        
        normalize_output = task_context.nodes.get("NormalizeNode")
        if normalize_output and hasattr(normalize_output, 'model_output'):
            normalized: NormalizedConstraints = normalize_output.model_output
        else:
            normalized = normalize_output  # Fallback if already NormalizedConstraints
        
        # Get node classes from workflow (stored in task_context metadata by workflow)
        # The workflow stores nodes as Dict[str, Type[Node]] with class names as keys
        raw_nodes = task_context.metadata.get("nodes", {})
        
        # Build a name-to-class mapping (handle both formats: already string keys or class keys)
        if not raw_nodes:
            node_map = {}
        elif raw_nodes and isinstance(next(iter(raw_nodes.keys())), str):
            # Already in format {"NodeName": NodeClass}
            node_map = raw_nodes
        else:
            # Convert from {NodeClass: ...} to {"NodeName": NodeClass}
            node_map = {
                node_class.__name__: node_class
                for node_class in raw_nodes.keys()
            }
        
        logger.debug(f"QC Router node_map keys: {list(node_map.keys())}")
        
        if not all([modified, nutrition, normalized]):
            logger.error("Missing required data for QC routing")
            next_node_class = node_map.get("FailureAgent")
            if not next_node_class:
                raise ValueError("FailureAgent not found in workflow")
            return next_node_class(task_context)
        
        # Track issues
        issues = []
        
        # Check 1: Calorie range tolerance
        if normalized.calorie_range:
            target_min, target_max = normalized.calorie_range
            actual_calories = nutrition.calories
            
            # Allow ±15% tolerance
            tolerance = 0.15
            min_acceptable = target_min * (1 - tolerance)
            max_acceptable = target_max * (1 + tolerance)
            
            if not (min_acceptable <= actual_calories <= max_acceptable):
                diff_pct = abs(actual_calories - (target_min + target_max) / 2) / ((target_min + target_max) / 2)
                issues.append(f"Calories off by {diff_pct*100:.1f}%: {actual_calories} vs target {target_min}-{target_max}")
                logger.warning(issues[-1])
        
        # Check 2: Macro targets tolerance
        if normalized.macro_targets:
            targets = normalized.macro_targets
            
            if targets.protein:
                diff_pct = abs(nutrition.protein - targets.protein) / max(targets.protein, 1)
                if diff_pct > 0.15:  # 15% tolerance
                    issues.append(f"Protein off by {diff_pct*100:.1f}%: {nutrition.protein}g vs {targets.protein}g")
                    logger.warning(issues[-1])
            
            if targets.carbs:
                diff_pct = abs(nutrition.carbs - targets.carbs) / max(targets.carbs, 1)
                if diff_pct > 0.15:
                    issues.append(f"Carbs off by {diff_pct*100:.1f}%: {nutrition.carbs}g vs {targets.carbs}g")
                    logger.warning(issues[-1])
            
            if targets.fat:
                diff_pct = abs(nutrition.fat - targets.fat) / max(targets.fat, 1)
                if diff_pct > 0.15:
                    issues.append(f"Fat off by {diff_pct*100:.1f}%: {nutrition.fat}g vs {targets.fat}g")
                    logger.warning(issues[-1])
        
        # Check 3: Recipe coherence (basic checks)
        if len(modified.ingredients) < 2:
            issues.append("Recipe has too few ingredients")
            logger.warning(issues[-1])
        
        if len(modified.directions) < 20:
            issues.append("Recipe directions are too short")
            logger.warning(issues[-1])
        
        # Check 4: Excessive modifications (flag for user review)
        if len(modified.modifications) > 10:
            issues.append(f"Too many modifications ({len(modified.modifications)}), recipe may be unrecognizable")
            logger.warning(issues[-1])
        
        # Store issues for FailureAgent
        if issues:
            task_context.nodes["qc_issues"] = issues
        
        # Routing decision
        if not issues or len(issues) <= 1:
            # Minor or no issues - proceed to explanation
            logger.info("QC passed: Recipe meets quality standards")
            next_node_class = node_map.get("ExplanationAgent")
            if not next_node_class:
                logger.error(f"ExplanationAgent not found in node_map. Available nodes: {list(node_map.keys())}")
                raise ValueError(f"ExplanationAgent not found in workflow. Available nodes: {list(node_map.keys())}")
        else:
            # Significant issues - ModificationAgent already tried 3 iterations, fail gracefully
            logger.info(f"QC failed: {len(issues)} issues found after modification attempts, routing to failure")
            next_node_class = node_map.get("FailureAgent")
            if not next_node_class:
                logger.error(f"FailureAgent not found in node_map. Available nodes: {list(node_map.keys())}")
                raise ValueError(f"FailureAgent not found in workflow. Available nodes: {list(node_map.keys())}")
        
        return next_node_class(task_context)

