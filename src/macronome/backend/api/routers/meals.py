"""
Meals Router
ML meal recommendations and meal history CRUD
"""
import logging
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, status
from supabase import Client

from macronome.backend.api.dependencies import get_current_user, get_supabase
from macronome.backend.database.models import MealRecommendation
from pydantic import BaseModel, Field
from typing import Optional, Dict, Any, List
from macronome.backend.services.meal_recommender import MealRecommenderService

logger = logging.getLogger(__name__)
router = APIRouter()


# API-specific schemas for meal operations
class MealRecommendRequest(BaseModel):
    """Request meal recommendation"""
    user_query: Optional[str] = "Recommend me a meal"
    constraints: Optional[Dict[str, Any]] = None


class MealRecommendResponse(BaseModel):
    """Response with task_id for polling"""
    task_id: str
    message: str = "Meal recommendation in progress. Use task_id to check status."


class MealRecommendStatusResponse(BaseModel):
    """Status of meal recommendation task"""
    status: str  # pending, started, success, failure
    result: Optional[Dict[str, Any]] = None
    error: Optional[str] = None


class MealHistoryCreate(BaseModel):
    """Save meal to history"""
    name: str
    description: Optional[str] = None
    ingredients: List[str] = []
    reasoning: Optional[str] = None
    meal_data: Dict[str, Any] = {}
    accepted: bool = False


class MealRatingUpdate(BaseModel):
    """Update meal rating"""
    rating: int = Field(..., ge=1, le=5)


@router.post("/recommend", tags=["ml", "meals"], response_model=MealRecommendResponse)
async def recommend_meal(
    request: MealRecommendRequest,
    user_id: str = Depends(get_current_user),
    db: Client = Depends(get_supabase),
):
    """
    AI: Request meal recommendation (async)
    
    Queues a meal recommendation task using Celery.
    Returns a task_id for polling status.
    
    The recommendation workflow:
    1. Normalizes constraints
    2. Plans search strategy
    3. Retrieves candidate recipes
    4. Modifies recipe to fit constraints
    5. Generates personalized explanation
    """
    logger.info(f"🍽️ Queuing meal recommendation for user {user_id}")
    
    try:
        # Get user preferences
        prefs_result = db.table("user_preferences").select("*").eq("user_id", user_id).limit(1).execute()
        user_preferences = prefs_result.data[0] if prefs_result.data else {}
        
        # Get pantry items
        pantry_result = db.table("pantry_items").select("*").eq("user_id", user_id).execute()
        pantry_items = [
            {"name": item["name"], "category": item.get("category"), "confirmed": item["confirmed"]}
            for item in pantry_result.data
        ]
        
        # Build constraints from user_preferences (flat structure)
        constraints = {
            "calories": user_preferences.get("calories"),
            "macros": user_preferences.get("macros"),
            "diet": user_preferences.get("diet"),
            "excludedIngredients": user_preferences.get("allergies", []),
            "prepTime": user_preferences.get("prep_time"),
        }
        # Merge with request constraints if provided
        if request.constraints:
            constraints.update(request.constraints)
        # Remove None values
        constraints = {k: v for k, v in constraints.items() if v is not None}
        
        # Queue recommendation task
        recommender = MealRecommenderService()
        task_id = recommender.queue_recommendation(
            user_query=request.user_query,
            constraints=constraints,
            pantry_items=pantry_items,
            chat_history=[]  # Empty for direct API call
        )
        
        logger.info(f"✅ Queued meal recommendation task {task_id} for user {user_id}")
        
        return MealRecommendResponse(
            task_id=task_id,
            message="Meal recommendation in progress. Use task_id to check status."
        )
    
    except Exception as e:
        logger.error(f"❌ Failed to queue meal recommendation for user {user_id}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to queue meal recommendation: {str(e)}"
        )


@router.get("/recommend/{task_id}", tags=["ml", "meals"], response_model=MealRecommendStatusResponse)
async def get_recommendation_status(
    task_id: str,
    user_id: str = Depends(get_current_user),
):
    """
    AI: Poll meal recommendation status
    
    Check the status of a meal recommendation task.
    
    Status values:
    - pending: Task is queued
    - started: Task is processing
    - success: Recommendation ready (result included)
    - failure: Task failed (error included)
    """
    logger.info(f"📊 Checking status of task {task_id} for user {user_id}")
    
    try:
        recommender = MealRecommenderService()
        status_result = recommender.get_task_status(task_id)
        
        return MealRecommendStatusResponse(**status_result)
    
    except Exception as e:
        logger.error(f"❌ Failed to get task status for {task_id}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to get task status: {str(e)}"
        )


@router.get("/history", tags=["meals"], response_model=List[MealRecommendation])
async def get_meal_history(
    limit: int = 50,
    user_id: str = Depends(get_current_user),
    db: Client = Depends(get_supabase),
):
    """
    Get meal recommendation history
    
    Returns recent meal recommendations for the user.
    """
    logger.info(f"📜 Fetching meal history for user {user_id}")
    
    try:
        result = db.table("meal_recommendations").select("*").eq("user_id", user_id).order("created_at", desc=True).limit(limit).execute()
        
        meals = [
            MealRecommendation(**meal)
            for meal in result.data
        ]
        
        logger.info(f"✅ Found {len(meals)} meals in history for user {user_id}")
        
        return meals
    
    except Exception as e:
        logger.error(f"❌ Failed to fetch meal history for user {user_id}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to fetch meal history: {str(e)}"
        )


@router.post("/history", tags=["meals"], status_code=status.HTTP_201_CREATED)
async def save_meal_to_history(
    meal: MealHistoryCreate,
    chat_session_id: Optional[str] = None,
    user_id: str = Depends(get_current_user),
    db: Client = Depends(get_supabase),
):
    """
    Save meal to history
    
    Saves a meal recommendation to the user's history.
    Typically called after user accepts a recommendation.
    """
    logger.info(f"💾 Saving meal to history for user {user_id}")
    
    try:
        meal_data = {
            "user_id": user_id,
            "chat_session_id": chat_session_id,
            "name": meal.name,
            "description": meal.description,
            "ingredients": meal.ingredients,
            "reasoning": meal.reasoning,
            "meal_data": meal.meal_data,
            "accepted": meal.accepted,
        }
        
        result = db.table("meal_recommendations").insert(meal_data).execute()
        
        logger.info(f"✅ Saved meal to history for user {user_id}")
        
        return {
            "message": "Meal saved to history",
            "meal": result.data[0]
        }
    
    except Exception as e:
        logger.error(f"❌ Failed to save meal to history for user {user_id}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to save meal to history: {str(e)}"
        )


@router.put("/history/{meal_id}/rating", tags=["meals"])
async def update_meal_rating(
    meal_id: str,
    rating_update: MealRatingUpdate,
    user_id: str = Depends(get_current_user),
    db: Client = Depends(get_supabase),
):
    """
    Update meal rating
    
    Allows user to rate a meal they've tried (1-5 stars).
    """
    logger.info(f"⭐ Updating rating for meal {meal_id} to {rating_update.rating} stars")
    
    try:
        # Verify ownership and update
        result = db.table("meal_recommendations").update({
            "rating": rating_update.rating
        }).eq("id", meal_id).eq("user_id", user_id).execute()
        
        if not result.data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Meal not found"
            )
        
        logger.info(f"✅ Updated rating for meal {meal_id}")
        
        return {
            "message": "Rating updated",
            "meal": result.data[0]
        }
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Failed to update rating for meal {meal_id}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to update rating: {str(e)}"
        )

