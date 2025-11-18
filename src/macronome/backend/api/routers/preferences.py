"""
Preferences Router
User preferences CRUD
"""
import logging
from fastapi import APIRouter, Depends, HTTPException, status
from supabase import Client

from macronome.backend.api.dependencies import get_current_user, get_supabase
from macronome.backend.api.schemas import (
    UserPreferencesResponse,
    UserPreferencesUpdate,
)

logger = logging.getLogger(__name__)
router = APIRouter()


@router.get("/", tags=["preferences"], response_model=UserPreferencesResponse)
async def get_user_preferences(
    user_id: str = Depends(get_current_user),
    db: Client = Depends(get_supabase),
):
    """
    Get user preferences
    
    Returns the user's meal preferences including:
    - calories: Target calories (integer)
    - macros: Macro targets {carbs, protein, fat} in grams
    - diet: Diet type (e.g., "vegan", "keto", "vegetarian")
    - allergies: Allergies/excluded ingredients (list of strings)
    - prep_time: Maximum prep time in minutes (integer)
    - meal_type: Meal type ("breakfast", "lunch", "snack", "dinner", "dessert")
    - custom_constraints: LLM-parsed custom constraints (flexible dict)
    """
    logger.info(f"📋 Fetching preferences for user {user_id}")
    
    try:
        result = db.table("user_preferences").select("*").eq("user_id", user_id).limit(1).execute()
        
        if not result.data:
            # Return empty/default preferences if not found
            logger.info(f"No preferences found for user {user_id}, returning defaults")
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User preferences not found. Create preferences first."
            )
        
        preferences = UserPreferencesResponse(**result.data[0])
        
        logger.info(f"✅ Fetched preferences for user {user_id}")
        
        return preferences
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Failed to fetch preferences for user {user_id}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to fetch preferences: {str(e)}"
        )


@router.put("/", tags=["preferences"], response_model=UserPreferencesResponse)
async def update_user_preferences(
    preferences_update: UserPreferencesUpdate,
    user_id: str = Depends(get_current_user),
    db: Client = Depends(get_supabase),
):
    """
    Update user preferences
    
    Updates the user's meal preferences. Only fields provided will be updated.
    Creates new preferences record if one doesn't exist.
    """
    logger.info(f"✏️  Updating preferences for user {user_id}")
    
    try:
        # Prepare update data (exclude None values)
        update_data = preferences_update.model_dump(exclude_none=True)
        
        if not update_data:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No fields to update"
            )
        
        # Check if preferences exist
        existing = db.table("user_preferences").select("id").eq("user_id", user_id).limit(1).execute()
        
        if existing.data:
            # Update existing preferences
            result = db.table("user_preferences").update(update_data).eq("user_id", user_id).execute()
            updated_prefs = result.data[0]
            logger.info(f"✅ Updated preferences for user {user_id}")
        else:
            # Create new preferences with new structure
            insert_data = {
                "user_id": user_id,
                "calories": None,
                "macros": None,
                "diet": None,
                "allergies": [],
                "prep_time": None,
                "meal_type": None,
                "custom_constraints": {},
                **update_data
            }
            result = db.table("user_preferences").insert(insert_data).execute()
            updated_prefs = result.data[0]
            logger.info(f"✅ Created preferences for user {user_id}")
        
        return UserPreferencesResponse(**updated_prefs)
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Failed to update preferences for user {user_id}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to update preferences: {str(e)}"
        )


@router.delete("/", tags=["preferences"], status_code=status.HTTP_204_NO_CONTENT)
async def reset_user_preferences(
    user_id: str = Depends(get_current_user),
    db: Client = Depends(get_supabase),
):
    """
    Reset user preferences to defaults
    
    Deletes the user's preferences record, effectively resetting to defaults.
    """
    logger.info(f"🔄 Resetting preferences for user {user_id}")
    
    try:
        result = db.table("user_preferences").delete().eq("user_id", user_id).execute()
        
        if not result.data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User preferences not found"
            )
        
        logger.info(f"✅ Reset preferences for user {user_id}")
        
        return None
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Failed to reset preferences for user {user_id}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to reset preferences: {str(e)}"
        )

