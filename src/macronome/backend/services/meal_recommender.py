"""
Meal Recommender Service
Wraps MealRecommendationWorkflow for backend use via Celery
"""
import logging
from typing import Dict, Any, List
from celery.result import AsyncResult

from macronome.backend.worker.tasks import recommend_meal_async
from macronome.ai.schemas.meal_recommender_constraints_schema import (
    FilterConstraints,
    PantryItem as WorkflowPantryItem,
)

logger = logging.getLogger(__name__)


class MealRecommenderService:
    """
    Service wrapper for MealRecommendationWorkflow
    
    Queues async Celery tasks for meal recommendations and provides
    status checking functionality.
    """
    
    def queue_recommendation(
        self,
        user_query: str,
        constraints: Dict[str, Any],
        pantry_items: List[Dict[str, Any]] = None,
        chat_history: List[Dict[str, str]] = None
    ) -> str:
        """
        Queue async meal recommendation task
        
        Args:
            user_query: Free text query (e.g., "something quick and spicy")
            constraints: Meal constraints dict with keys:
                - calories: Optional[int]
                - macros: Optional[Dict] with carbs/protein/fat
                - diet: Optional[str] (e.g., "vegan", "keto")
                - excludedIngredients or allergies: List[str]
                - prepTime or prep_time: Optional[int] (minutes)
                - mealType or meal_type: Optional[str]
                - custom_constraints: Optional[Dict[str, Any]]
            pantry_items: List of pantry items (optional)
            chat_history: Previous chat messages (optional)
        
        Returns:
            task_id: Celery task ID for polling status
        
        Raises:
            ValueError: If request data is invalid
        """
        # Prepare request data
        request_data = self._prepare_request(
            user_query,
            constraints,
            pantry_items or [],
            chat_history or []
        )
        
        logger.info(f"📤 Queueing meal recommendation task: '{user_query[:50]}...'")
        
        # Queue Celery task
        task = recommend_meal_async.delay(request_data)
        
        logger.info(f"✅ Task queued with ID: {task.id}")
        return task.id
    
    def get_task_status(self, task_id: str) -> Dict[str, Any]:
        """
        Get status and result of meal recommendation task
        
        Args:
            task_id: Celery task ID
        
        Returns:
            Dict with task status:
            - status: "pending" | "started" | "success" | "failure"
            - result: Task result (if success)
            - error: Error message (if failure)
        """
        task_result = AsyncResult(task_id)
        
        logger.info(f"🔍 Task {task_id} state: {task_result.state}, ready: {task_result.ready()}")
        
        if task_result.ready():
            # Task completed
            if task_result.successful():
                logger.info(f"✅ Task {task_id} succeeded, result type: {type(task_result.result)}")
                return {
                    "status": "success",
                    "result": task_result.result
                }
            else:
                logger.warning(f"❌ Task {task_id} failed: {task_result.info}")
                return {
                    "status": "failure",
                    "error": str(task_result.info)
                }
        else:
            # Task still processing
            logger.info(f"⏳ Task {task_id} still processing, state: {task_result.state}")
            return {
                "status": task_result.state.lower(),  # "pending" or "started"
                "result": None
            }
    
    def _prepare_request(
        self,
        user_query: str,
        constraints: Dict[str, Any],
        pantry_items: List[Dict[str, Any]],
        chat_history: List[Dict[str, str]]
    ) -> Dict[str, Any]:
        """
        Prepare workflow request from service inputs
        
        Args:
            user_query: User's query string
            constraints: Constraints dict
            pantry_items: Pantry items list
            chat_history: Chat history list
        
        Returns:
            Request dict for workflow
        """
        # Convert constraints dict to FilterConstraints schema
        filter_constraints = FilterConstraints(
            calories=constraints.get("calories"),
            macros=constraints.get("macros"),
            diet=constraints.get("diet"),
            allergies=constraints.get("excludedIngredients", constraints.get("allergies", [])),
            prep_time=constraints.get("prepTime", constraints.get("prep_time")),
            meal_type=constraints.get("mealType", constraints.get("meal_type")),
            custom_constraints=constraints.get("custom_constraints", {})
        )
        
        # Convert pantry items to workflow schema
        workflow_pantry_items = [
            WorkflowPantryItem(
                name=item["name"],
                category=item.get("category"),
                confirmed=item.get("confirmed", True)
            )
            for item in pantry_items
        ]
        
        # Create workflow request
        request_data = {
            "user_query": user_query,
            "constraints": filter_constraints.model_dump(),
            "pantry_items": [item.model_dump() for item in workflow_pantry_items],
            "chat_history": chat_history
        }
        
        return request_data

