"""
Celery Tasks for Macronome

Async task processing for meal recommendations and other long-running operations.
"""
import logging
from typing import Dict, Any

from macronome.backend.worker.config import celery_app
from macronome.ai.workflows.meal_recommender_workflow import MealRecommendationWorkflow

logger = logging.getLogger(__name__)


@celery_app.task(
    name="recommend_meal_async",
    bind=True,
    max_retries=2,
    time_limit=300,  # 5 minutes max
    soft_time_limit=270  # 4.5 minutes soft limit
)
def recommend_meal_async(self, request_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Async meal recommendation task
    
    Runs the MealRecommendationWorkflow asynchronously and returns the result.
    The result is stored in Redis by Celery and can be retrieved via task_id.
    
    Args:
        self: Celery task instance (bound)
        request_data: MealRecommendationRequest as dict with keys:
            - user_query: str
            - constraints: FilterConstraints dict
            - pantry_items: List[PantryItem] dicts
            - chat_history: List[Dict] (optional)
    
    Returns:
        Dict with workflow result (matches service format):
            Success:
            {
                "success": True,
                "recommendation": {...}
            }
            Failure:
            {
                "success": False,
                "error_message": str,
                "suggestions": List[str]
            }
    
    Raises:
        Retries on failure (max 2 times with 60s delay)
    """
    try:
        logger.info(f"🔄 Starting meal recommendation task {self.request.id}")
        
        # Run meal recommendation workflow (sync version for Celery worker)
        workflow = MealRecommendationWorkflow()
        task_context = workflow.run(request_data)  # workflow.run() takes dict, not Pydantic model
        
        # Extract results - check both success and failure nodes
        explanation_output = task_context.nodes.get("ExplanationAgent")
        failure_output = task_context.nodes.get("FailureAgent")
        
        if explanation_output:
            # Success path
            recommendation = explanation_output.model_output
            result = {
                "success": True,
                "recommendation": {
                    "recipe": {
                        "id": recommendation.recipe.id,
                        "name": recommendation.recipe.name,
                        "ingredients": recommendation.recipe.ingredients,
                        "directions": recommendation.recipe.directions,
                        "nutrition": {
                            "calories": recommendation.recipe.nutrition.calories,
                            "protein": recommendation.recipe.nutrition.protein,
                            "carbs": recommendation.recipe.nutrition.carbs,
                            "fat": recommendation.recipe.nutrition.fat
                        },
                        "prep_time": getattr(recommendation.recipe, "prep_time", None),
                        "semantic_score": getattr(recommendation.recipe, "semantic_score", 0.0)
                    },
                    "why_it_fits": recommendation.why_it_fits,
                    "ingredient_swaps": recommendation.ingredient_swaps,
                    "pantry_utilization": recommendation.pantry_utilization,
                    "recipe_instructions": recommendation.recipe_instructions
                }
            }
            logger.info(f"✅ Meal recommendation task {self.request.id} succeeded: {recommendation.recipe.name}")
            return result
        
        elif failure_output:
            # Failure path
            failure_response = failure_output.model_output
            result = {
                "success": False,
                "error_message": failure_response.error_message,
                "suggestions": failure_response.suggestions
            }
            logger.warning(f"⚠️ Meal recommendation task {self.request.id} failed: {failure_response.error_message}")
            return result
        
        else:
            # Unexpected: no output from either terminal node
            logger.error(f"❌ Task {self.request.id}: Workflow completed but no output found")
            return {
                "success": False,
                "error_message": "Workflow failed to produce a result",
                "suggestions": ["Please try again or adjust your constraints"]
            }
        
    except Exception as e:
        logger.error(f"❌ Meal recommendation task {self.request.id} failed: {e}", exc_info=True)
        
        # Retry on failure with exponential backoff
        try:
            raise self.retry(exc=e, countdown=60 * (self.request.retries + 1))
        except self.MaxRetriesExceededError:
            # Max retries exceeded, return error
            return {
                "success": False,
                "error_message": f"Task failed after {self.request.retries} retries: {str(e)}",
                "suggestions": ["Please try again later or contact support"]
            }


# TODO: Add more async tasks as needed
# Example: @celery_app.task(name="batch_process_pantry_images")
