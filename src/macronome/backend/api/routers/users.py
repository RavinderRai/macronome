"""
Users Router
User initialization and management
"""
import logging
from fastapi import APIRouter, Depends, HTTPException, status
from supabase import Client

from macronome.backend.api.dependencies import get_current_user, get_supabase, get_supabase_admin

logger = logging.getLogger(__name__)
router = APIRouter()


@router.post("/initialize", tags=["users"])
async def initialize_user(
    user_id: str = Depends(get_current_user),
    db: Client = Depends(get_supabase_admin),  # Use admin to bypass RLS
):
    """
    Initialize user records after sign-up
    
    Creates:
    - user_preferences: Global preferences and constraints
    - chat_sessions: Initial active chat session
    
    This endpoint is idempotent - safe to call multiple times.
    If user is already initialized, returns success without creating duplicates.
    
    Called by frontend after successful Clerk sign-up.
    
    Note: Uses admin client to bypass RLS since we authenticate via Clerk, not Supabase Auth.
    """
    logger.info(f"🚀 Initializing user {user_id}")
    
    try:
        # Check if already initialized
        existing_prefs = db.table("user_preferences").select("id").eq("user_id", user_id).limit(1).execute()
        
        if existing_prefs.data:
            logger.info(f"✅ User {user_id} already initialized")
            return {
                "message": "User already initialized",
                "user_id": user_id,
                "already_exists": True
            }
        
        # Create user_preferences with new structure
        prefs_result = db.table("user_preferences").insert({
            "user_id": user_id,
            "calories": None,
            "macros": None,
            "diet": None,
            "allergies": [],
            "prep_time": None,
            "meal_type": None,
            "custom_constraints": {},
        }).execute()
        
        logger.info(f"✅ Created user_preferences for {user_id}")
        
        # Create initial chat_session
        session_result = db.table("chat_sessions").insert({
            "user_id": user_id,
            "is_active": True,
            "filters": {},
        }).execute()
        
        logger.info(f"✅ Created chat_session for {user_id}")
        
        return {
            "message": "User initialized successfully",
            "user_id": user_id,
            "already_exists": False,
            "preferences_id": prefs_result.data[0]["id"] if prefs_result.data else None,
            "chat_session_id": session_result.data[0]["id"] if session_result.data else None,
        }
    
    except Exception as e:
        logger.error(f"❌ Failed to initialize user {user_id}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to initialize user: {str(e)}"
        )


@router.get("/me", tags=["users"])
async def get_current_user_info(
    user_id: str = Depends(get_current_user),
    db: Client = Depends(get_supabase),
):
    """
    Get current user's initialization status
    
    Returns whether user has been initialized in Supabase.
    Useful for checking if initialization is needed after sign-in.
    """
    logger.info(f"📋 Checking initialization status for user {user_id}")
    
    try:
        prefs_result = db.table("user_preferences").select("id").eq("user_id", user_id).limit(1).execute()
        session_result = db.table("chat_sessions").select("id").eq("user_id", user_id).eq("is_active", True).limit(1).execute()
        
        is_initialized = bool(prefs_result.data and session_result.data)
        
        return {
            "user_id": user_id,
            "is_initialized": is_initialized,
            "has_preferences": bool(prefs_result.data),
            "has_active_session": bool(session_result.data),
        }
    
    except Exception as e:
        logger.error(f"❌ Failed to check user status for {user_id}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to check user status: {str(e)}"
        )

