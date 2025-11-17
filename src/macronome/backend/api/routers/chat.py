"""
Chat Router
ML chat workflow (streaming) and chat session CRUD
"""
import logging
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import StreamingResponse
from supabase import Client
import json

from macronome.backend.api.dependencies import get_current_user, get_supabase, get_supabase_admin
from macronome.backend.api.schemas import (
    ChatMessageRequest,
    ChatMessageResponse,
    ChatSessionResponse,
    ChatSessionCreate,
    ChatMessageHistoryResponse,
)
from macronome.backend.services.chat import ChatService
from macronome.backend.database.chat_helpers import (
    get_active_chat_session,
    create_new_chat_session,
    add_chat_message,
    get_chat_messages,
)

logger = logging.getLogger(__name__)
router = APIRouter()


@router.post("/message", tags=["ml", "chat"])
async def send_chat_message(
    request: ChatMessageRequest,
    user_id: str = Depends(get_current_user),
    db: Client = Depends(get_supabase_admin),  # Use admin to bypass RLS for writes
):
    """
    AI: Send chat message (non-streaming version)
    
    Processes a chat message through the AI workflow.
    
    Actions:
    - ADD_CONSTRAINT: Parses and saves constraints to user_preferences
    - START_RECOMMENDATION: Queues meal recommendation task
    - GENERAL_CHAT: Provides helpful response
    
    Automatically saves messages to chat history.
    """
    logger.info(f"💬 Processing chat message for user {user_id}")
    
    try:
        # Get or create chat session
        chat_session_id = request.chat_session_id
        if not chat_session_id:
            # Get active session or create new one
            active_session = get_active_chat_session(db, user_id)
            if active_session:
                chat_session_id = active_session["id"]
            else:
                new_session = create_new_chat_session(db, user_id)
                chat_session_id = new_session["id"]
        
        # Save user message to history
        add_chat_message(db, chat_session_id, request.message, "user")
        
        # Get user preferences
        prefs_result = db.table("user_preferences").select("*").eq("user_id", user_id).limit(1).execute()
        user_preferences = prefs_result.data[0] if prefs_result.data else {}
        
        # Get pantry items
        pantry_result = db.table("pantry_items").select("*").eq("user_id", user_id).execute()
        pantry_items = [
            {"name": item["name"], "category": item.get("category"), "confirmed": item["confirmed"]}
            for item in pantry_result.data
        ]
        
        # Process message through chat service
        chat_service = ChatService()
        response = await chat_service.process_message(
            message=request.message,
            chat_session_id=chat_session_id,
            user_id=user_id,
            user_preferences=user_preferences,
            pantry_items=pantry_items,
        )
        
        # Save assistant response to history
        add_chat_message(db, chat_session_id, response["response"], "assistant")
        
        # If constraints were updated, save to database
        if response.get("updated_constraints"):
            updated_constraints = response["updated_constraints"]
            
            # Update or create user_preferences
            if user_preferences:
                db.table("user_preferences").update(updated_constraints).eq("user_id", user_id).execute()
            else:
                db.table("user_preferences").insert({
                    "user_id": user_id,
                    **updated_constraints
                }).execute()
            
            logger.info(f"✅ Updated user preferences for user {user_id}")
        
        logger.info(f"✅ Chat message processed for user {user_id}")
        
        return ChatMessageResponse(
            response=response["response"],
            action=response.get("action"),
            task_id=response.get("task_id"),
            updated_constraints=response.get("updated_constraints"),
            chat_session_id=chat_session_id,
        )
    
    except Exception as e:
        logger.error(f"❌ Failed to process chat message for user {user_id}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to process message: {str(e)}"
        )


# TODO: Implement streaming version
# @router.post("/message/stream", tags=["ml", "chat"])
# async def send_chat_message_stream(...):
#     """Streaming version using SSE"""
#     pass


@router.get("/sessions", tags=["chat"], response_model=List[ChatSessionResponse])
async def get_chat_sessions(
    limit: int = 50,
    user_id: str = Depends(get_current_user),
    db: Client = Depends(get_supabase),
):
    """
    Get user's chat sessions
    
    Returns recent chat sessions for the user.
    """
    logger.info(f"📋 Fetching chat sessions for user {user_id}")
    
    try:
        result = db.table("chat_sessions").select("*").eq("user_id", user_id).order("created_at", desc=True).limit(limit).execute()
        
        sessions = [
            ChatSessionResponse(**session)
            for session in result.data
        ]
        
        logger.info(f"✅ Found {len(sessions)} chat sessions for user {user_id}")
        
        return sessions
    
    except Exception as e:
        logger.error(f"❌ Failed to fetch chat sessions for user {user_id}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to fetch chat sessions: {str(e)}"
        )


@router.post("/sessions", tags=["chat"], status_code=status.HTTP_201_CREATED, response_model=ChatSessionResponse)
async def create_chat_session(
    session_data: ChatSessionCreate,
    user_id: str = Depends(get_current_user),
    db: Client = Depends(get_supabase_admin),  # Use admin to bypass RLS for writes
):
    """
    Create new chat session
    
    Creates a new active chat session and deactivates any existing active session.
    Only one active session per user allowed.
    """
    logger.info(f"➕ Creating new chat session for user {user_id}")
    
    try:
        new_session = create_new_chat_session(db, user_id, session_data.filters)
        
        logger.info(f"✅ Created chat session {new_session['id']} for user {user_id}")
        
        return ChatSessionResponse(**new_session)
    
    except Exception as e:
        logger.error(f"❌ Failed to create chat session for user {user_id}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to create chat session: {str(e)}"
        )


@router.get("/sessions/{session_id}/messages", tags=["chat"], response_model=List[ChatMessageHistoryResponse])
async def get_session_messages(
    session_id: str,
    limit: int = 100,
    user_id: str = Depends(get_current_user),
    db: Client = Depends(get_supabase),
):
    """
    Get messages for a chat session
    
    Returns chat message history for a specific session.
    """
    logger.info(f"📜 Fetching messages for session {session_id}")
    
    try:
        # Verify session belongs to user
        session_result = db.table("chat_sessions").select("id").eq("id", session_id).eq("user_id", user_id).execute()
        if not session_result.data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Chat session not found"
            )
        
        # Get messages
        messages_data = get_chat_messages(db, session_id, limit)
        
        messages = [
            ChatMessageHistoryResponse(**msg)
            for msg in messages_data
        ]
        
        logger.info(f"✅ Found {len(messages)} messages for session {session_id}")
        
        return messages
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Failed to fetch messages for session {session_id}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to fetch messages: {str(e)}"
        )

