"""
Meal Recommender Service
Wraps MealRecommendationWorkflow for backend use
"""
import logging
from typing import Dict, Any, List

from macronome.ai.workflows.meal_recommender_workflow import MealRecommendationWorkflow
from macronome.ai.schemas.meal_recommender_constraints_schema import (
    FilterConstraints,
    PantryItem as WorkflowPantryItem,
)

logger = logging.getLogger(__name__)


class MealRecommenderService:
    """
    Service wrapper for MealRecommendationWorkflow
    
    Handles request formatting, workflow execution, and result formatting
    for the meal recommendation AI feature.
    """
    
    def __init__(self):
        """Initialize the service with workflow instance"""
        self._workflow = MealRecommendationWorkflow()
    
    async def recommend_meal(
        self,
        user_query: str,
        constraints: Dict[str, Any],
        pantry_items: List[Dict[str, Any]] = None,
        chat_history: List[Dict[str, str]] = None
    ) -> Dict[str, Any]:
        """
        Generate meal recommendation based on user constraints
        
        Args:
            user_query: Free text query (e.g., "something quick and spicy")
            constraints: Meal constraints dict with keys:
                - calories: Optional[int]
                - macros: Optional[Dict] with carbs/protein/fat
                - diet: Optional[str] (e.g., "vegan", "keto")
                - excluded_ingredients: List[str]
                - prep_time: Optional[str] ('quick' | 'medium' | 'long')
            pantry_items: List of pantry items (optional)
            chat_history: Previous chat messages (optional)
        
        Returns:
            Dict with meal recommendation or error:
            Success:
            {
                "success": True,
                "recommendation": {
                    "recipe": {...},
                    "why_it_fits": str,
                    "ingredient_swaps": List[str],
                    "pantry_utilization": List[str],
                    "recipe_instructions": str
                }
            }
            Failure:
            {
                "success": False,
                "error_message": str,
                "suggestions": List[str]
            }
        
        Raises:
            ValueError: If request data is invalid
            Exception: If workflow execution fails
        """
        # Prepare request data
        request_data = self._prepare_request(
            user_query,
            constraints,
            pantry_items or [],
            chat_history or []
        )
        
        logger.info(f"🍽️ Starting meal recommendation: '{user_query[:50]}...'")
        
        try:
            # Execute workflow
            task_context = await self._workflow.run_async(request_data)
            
            # Extract results - check both success and failure nodes
            explanation_output = task_context.nodes.get("ExplanationAgent")
            failure_output = task_context.nodes.get("FailureAgent")
            
            if explanation_output:
                # Success path
                recommendation = explanation_output.model_output
                result = self._format_success_result(recommendation)
                logger.info(f"✅ Meal recommendation succeeded: {result['recommendation']['recipe'].name}")
                return result
            
            elif failure_output:
                # Failure path
                failure_response = failure_output.model_output
                result = self._format_failure_result(failure_response)
                logger.warning(f"⚠️ Meal recommendation failed: {result['error_message']}")
                return result
            
            else:
                # Unexpected: no output from either terminal node
                logger.error("❌ Workflow completed but no output found from terminal nodes")
                return {
                    "success": False,
                    "error_message": "Workflow failed to produce a result",
                    "suggestions": ["Please try again or adjust your constraints"]
                }
        
        except Exception as e:
            logger.error(f"❌ Meal recommendation failed: {e}")
            raise
    
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
            excluded_ingredients=constraints.get("excluded_ingredients", []),
            prep_time=constraints.get("prep_time")
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
    
    def _format_success_result(self, recommendation: Any) -> Dict[str, Any]:
        """
        Format successful recommendation for API response
        
        Args:
            recommendation: MealRecommendation from ExplanationAgent
        
        Returns:
            Formatted success dict
        """
        return {
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
    
    def _format_failure_result(self, failure_response: Any) -> Dict[str, Any]:
        """
        Format failure response for API response
        
        Args:
            failure_response: FailureResponse from FailureAgent
        
        Returns:
            Formatted failure dict
        """
        return {
            "success": False,
            "error_message": failure_response.error_message,
            "suggestions": failure_response.suggestions
        }

