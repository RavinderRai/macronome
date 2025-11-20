"""
Meal Recommendation Trigger Node

Queues meal recommendation task when user requests a recommendation.
Stores task_id in metadata for ResponseGenerator to use.
"""
import logging

from macronome.ai.core.nodes.base import Node
from macronome.ai.core.task import TaskContext
from macronome.ai.schemas.chat_schema import ChatRequest
from macronome.backend.services.meal_recommender import MealRecommenderService
from macronome.backend.database.session import get_supabase_client

logger = logging.getLogger(__name__)


class MealRecommendationTrigger(Node):
    """
    Queues meal recommendation task and stores task_id in metadata.
    
    Input: ChatRequest with user_preferences and pantry_items
    Output: task_id stored in task_context.metadata
    
    This node runs when ChatRouter detects START_RECOMMENDATION intent.
    It queues the meal recommendation as a Celery task and stores the
    task_id for ResponseGenerator to include in the response.
    """
    
    async def process(self, task_context: TaskContext) -> TaskContext:
        """
        Queue meal recommendation task.
        
        Args:
            task_context: Contains ChatRequest
            
        Returns:
            TaskContext with task_id in metadata
        """
        request: ChatRequest = task_context.event
        
        # Get user preferences from request
        user_prefs = request.user_preferences or {}
        
        # Build constraints from user_preferences
        constraints = {
            "calories": user_prefs.get("calories"),
            "macros": user_prefs.get("macros"),
            "diet": user_prefs.get("diet"),
            "excludedIngredients": user_prefs.get("allergies", []),
            "prepTime": user_prefs.get("prep_time"),
            "mealType": user_prefs.get("meal_type"),
        }
        # Remove None values
        constraints = {k: v for k, v in constraints.items() if v is not None}
        
        # Load pantry items from database (lazy loading - only when needed)
        db = get_supabase_client(use_service_key=False)
        pantry_result = db.table("pantry_items").select("*").eq("user_id", request.user_id).execute()
        pantry_items = [
            {"name": item["name"], "category": item.get("category"), "confirmed": item["confirmed"]}
            for item in pantry_result.data
        ]
        
        logger.info(f"📦 Loaded {len(pantry_items)} pantry items for user {request.user_id}")
        
        # Queue meal recommendation task
        recommender = MealRecommenderService()
        task_id = recommender.queue_recommendation(
            user_query=request.message,
            constraints=constraints,
            pantry_items=pantry_items,
            chat_history=request.chat_history
        )
        
        logger.info(f"✅ Queued meal recommendation task: {task_id}")
        
        # Store task_id in metadata for ResponseGenerator
        task_context.metadata["meal_recommendation_task_id"] = task_id
        
        return task_context

