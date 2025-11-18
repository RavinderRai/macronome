"""
Chat Service
Wraps ChatWorkflow for backend use with streaming support
"""
import logging
from typing import Dict, Any

from macronome.backend.database.session import get_db
from macronome.backend.database.chat_helpers import get_chat_messages
from macronome.ai.workflows.chat_workflow import ChatWorkflow
from macronome.ai.schemas.chat_schema import ChatRequest, ChatAction
from macronome.backend.services.meal_recommender import MealRecommenderService

logger = logging.getLogger(__name__)


class ChatService:
    """
    Service wrapper for ChatWorkflow
    
    Handles chat message processing, constraint updates, and meal recommendation triggering.
    Provides streaming support for real-time response generation.
    """
    
    def __init__(self):
        """Initialize the service with workflow instance"""
        self._workflow = ChatWorkflow()
    
    async def process_message(
        self,
        message: str,
        chat_session_id: str,
        user_id: str,
        user_preferences: Dict[str, Any],
        pantry_items: list = None
    ) -> Dict[str, Any]:
        """
        Process chat message and return response with action data.
        
        Args:
            message: User's chat message
            chat_session_id: Active chat session ID
            user_id: Clerk user ID
            user_preferences: Current user preferences from DB
            pantry_items: User's pantry items (for meal recommendation)
        
        Returns:
            Dict with:
            {
                "response": str,
                "action": ChatAction,
                "task_id": str (if START_RECOMMENDATION),
                "updated_constraints": FilterConstraints (if ADD_CONSTRAINT)
            }
        """
        # Load chat history from DB (last 5 messages)
        db = get_db()
        messages = get_chat_messages(db, chat_session_id, limit=5)
        
        # Convert to format: [{'role': 'user'/'assistant', 'content': '...'}]
        chat_history = [
            {
                "role": "user" if msg["type"] == "user" else "assistant",
                "content": msg["text"]
            }
            for msg in messages
        ]
        
        # Prepare request with user preferences included
        request = ChatRequest(
            message=message,
            chat_session_id=chat_session_id,
            user_id=user_id,
            chat_history=chat_history,
            user_preferences=user_preferences
        )
        
        logger.info(f"💬 Processing chat message for user {user_id}: '{message[:50]}...'")
        
        # Handle START_RECOMMENDATION action - queue meal recommendation task
        # This is done BEFORE running workflow to get task_id for response
        router_result = await self._quick_route(message)
        
        task_id = None
        if router_result["action"] == ChatAction.START_RECOMMENDATION:
            # Queue meal recommendation task
            recommender = MealRecommenderService()
            
            # Build constraints from user_preferences (flat structure)
            constraints = {
                "calories": user_preferences.get("calories"),
                "macros": user_preferences.get("macros"),
                "diet": user_preferences.get("diet"),
                "excludedIngredients": user_preferences.get("allergies", []),
                "prepTime": user_preferences.get("prep_time"),
            }
            # Remove None values
            constraints = {k: v for k, v in constraints.items() if v is not None}
            
            task_id = recommender.queue_recommendation(
                user_query=message,
                constraints=constraints,
                pantry_items=pantry_items or [],
                chat_history=chat_history  # Pass loaded chat history
            )
            
            logger.info(f"✅ Queued meal recommendation task: {task_id}")
        
        # Run workflow - convert Pydantic model to dict for workflow
        request_dict = request.model_dump() if hasattr(request, 'model_dump') else request.model_dump()
        result_context = await self._workflow.run_async(request_dict)
        
        # Store task_id in result context metadata for ResponseGenerator to access
        if task_id:
            result_context.metadata["meal_recommendation_task_id"] = task_id
        
        # Extract response from ResponseGenerator
        response_output = result_context.nodes.get("ResponseGenerator")
        
        if not response_output:
            raise ValueError("ResponseGenerator output not found")
        
        # Get router output for action
        router_output = result_context.nodes.get("ChatRouter")
        action = router_output.model_output.action if router_output else None
        
        # Build response dict
        response_dict = {
            "response": response_output.model_output.response,
            "action": action,
        }
        
        # Add action-specific data
        if action == ChatAction.ADD_CONSTRAINT:
            updated_constraints = result_context.metadata.get("updated_constraints")
            if updated_constraints:
                response_dict["updated_constraints"] = updated_constraints
        
        elif action == ChatAction.START_RECOMMENDATION:
            task_id = result_context.metadata.get("meal_recommendation_task_id")
            if task_id:
                response_dict["task_id"] = task_id
        
        logger.info(f"✅ Chat message processed successfully: {action}")
        
        return response_dict
    
    async def _quick_route(self, message: str) -> Dict[str, Any]:
        """
        Quick routing to detect START_RECOMMENDATION before full workflow.
        
        This allows us to queue the meal recommendation task and get task_id
        before generating the response.
        
        Args:
            message: User's message
            
        Returns:
            Dict with action classification
        """
        # Simple heuristic check for meal recommendation keywords
        recommendation_keywords = [
            "recommend", "suggestion", "meal", "recipe", "cook", "find me",
            "what should i", "give me", "show me"
        ]
        
        message_lower = message.lower()
        for keyword in recommendation_keywords:
            if keyword in message_lower:
                return {"action": ChatAction.START_RECOMMENDATION}
        
        return {"action": ChatAction.GENERAL_CHAT}

