"""
Helper functions for managing chat sessions
Ensures only one active session per user
"""
from typing import Optional
from supabase import Client
import logging

logger = logging.getLogger(__name__)


def get_active_chat_session(db: Client, user_id: str) -> Optional[dict]:
    """
    Get the active chat session for a user
    
    Args:
        db: Supabase client
        user_id: Clerk user ID
    
    Returns:
        Active chat session dict or None
    """
    result = db.table("chat_sessions").select("*").eq("user_id", user_id).eq("is_active", True).limit(1).execute()
    
    if result.data:
        return result.data[0]
    return None


def create_new_chat_session(db: Client, user_id: str, filters: dict = None) -> dict:
    """
    Create a new active chat session for a user
    Automatically deactivates any existing active session
    
    Args:
        db: Supabase client
        user_id: Clerk user ID
        filters: Initial filters/constraints (default: {})
    
    Returns:
        New chat session dict
    """
    # Deactivate any existing active session
    db.table("chat_sessions").update({"is_active": False}).eq("user_id", user_id).eq("is_active", True).execute()
    
    # Create new active session
    new_session = {
        "user_id": user_id,
        "is_active": True,
        "filters": filters or {}
    }
    
    result = db.table("chat_sessions").insert(new_session).execute()
    logger.info(f"Created new active chat session for user {user_id}")
    
    return result.data[0]


def deactivate_chat_session(db: Client, user_id: str, session_id: str) -> None:
    """
    Deactivate a chat session (archive it)
    
    Args:
        db: Supabase client
        user_id: Clerk user ID
        session_id: Chat session ID to deactivate
    """
    db.table("chat_sessions").update({"is_active": False}).eq("id", session_id).eq("user_id", user_id).execute()
    logger.info(f"Deactivated chat session {session_id} for user {user_id}")


def update_chat_session_filters(db: Client, user_id: str, session_id: str, filters: dict) -> dict:
    """
    Update filters/constraints for a chat session
    
    Args:
        db: Supabase client
        user_id: Clerk user ID
        session_id: Chat session ID
        filters: Updated filters dict
    
    Returns:
        Updated chat session dict
    """
    result = db.table("chat_sessions").update({
        "filters": filters,
        "updated_at": "now()"
    }).eq("id", session_id).eq("user_id", user_id).execute()
    
    return result.data[0]


def get_chat_messages(db: Client, session_id: str, limit: int = 100) -> list:
    """
    Get messages for a chat session
    
    Args:
        db: Supabase client
        session_id: Chat session ID
        limit: Max number of messages to return
    
    Returns:
        List of message dicts
    """
    result = db.table("chat_messages").select("*").eq("chat_session_id", session_id).order("timestamp", desc=False).limit(limit).execute()
    return result.data


def add_chat_message(db: Client, session_id: str, text: str, message_type: str = "user") -> dict:
    """
    Add a message to a chat session
    
    Args:
        db: Supabase client
        session_id: Chat session ID
        text: Message content
        message_type: 'user', 'assistant', or 'system'
    
    Returns:
        New message dict
    """
    new_message = {
        "chat_session_id": session_id,
        "text": text,
        "type": message_type
    }
    
    result = db.table("chat_messages").insert(new_message).execute()
    return result.data[0]

