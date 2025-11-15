"""
Celery Tasks for Macronome

Async task processing for meal recommendations and other long-running operations.
"""
import logging
from typing import Dict, Any

from macronome.backend.worker.config import celery_app
from macronome.ai.workflows.meal_recommender_workflow import MealRecommendationWorkflow
from macronome.ai.schemas.meal_recommender_constraints_schema import MealRecommendationRequest

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
        Dict with workflow result:
            - status: "success" or "error"
            - result: Complete workflow output (if success)
            - error: Error message (if error)
    
    Raises:
        Retries on failure (max 2 times with 60s delay)
    """
    try:
        logger.info(f"Starting meal recommendation task {self.request.id}")
        
        # Parse request data into Pydantic model
        request = MealRecommendationRequest(**request_data)
        
        # Run meal recommendation workflow
        workflow = MealRecommendationWorkflow()
        task_context = workflow.run(request)
        
        # Extract final result from workflow
        result = {
            "status": "success",
            "task_id": self.request.id,
            "result": task_context.model_dump(mode="json")
        }
        
        logger.info(f"Meal recommendation task {self.request.id} completed successfully")
        return result
        
    except Exception as e:
        logger.error(f"Meal recommendation task {self.request.id} failed: {e}", exc_info=True)
        
        # Retry on failure with exponential backoff
        try:
            raise self.retry(exc=e, countdown=60 * (self.request.retries + 1))
        except self.MaxRetriesExceededError:
            # Max retries exceeded, return error
            return {
                "status": "error",
                "task_id": self.request.id,
                "error": str(e)
            }


# TODO: Add more async tasks as needed
# Example: @celery_app.task(name="batch_process_pantry_images")
