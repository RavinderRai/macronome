"""
Chat workflow schemas
Defines request/response models for chat workflow and nodes
"""
from enum import Enum
from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field
from macronome.ai.schemas.meal_recommender_constraints_schema import FilterConstraints


class ChatAction(str, Enum):
    """Actions that chat router can decide"""
    ADD_CONSTRAINT = "add_constraint"
    START_RECOMMENDATION = "start_recommendation"
    GENERAL_CHAT = "general_chat"


class ChatRouterOutput(BaseModel):
    """Output from ChatRouter node - routes user message to appropriate action"""
    action: ChatAction = Field(..., description="Primary user intention")
    has_question: bool = Field(
        default=False,
        description="User also asked a question or needs explanation (handled by ResponseGenerator)"
    )
    confidence: float = Field(..., ge=0.0, le=1.0, description="Confidence in action classification")
    reasoning: str = Field(..., description="Explanation of why this action was chosen")


class ConstraintParserOutput(BaseModel):
    """Output from ConstraintParser node"""
    updated_constraints: FilterConstraints = Field(..., description="Merged constraints after parsing")
    confirmation_message: str = Field(
        ...,
        description="User-friendly confirmation message (e.g., 'Added vegan diet' or 'Updated calories to 700')"
    )


class ChatRequest(BaseModel):
    """Request schema for chat workflow"""
    message: str = Field(..., description="User's chat message")
    chat_session_id: str = Field(..., description="Active chat session ID")
    user_id: str = Field(..., description="Clerk user ID")
    chat_history: List[Dict[str, str]] = Field(
        default_factory=list,
        description="Recent chat history (last 5 messages): [{'role': 'user'/'assistant', 'content': '...'}]"
    )
    user_preferences: Dict[str, Any] = Field(
        default_factory=dict,
        description="Current user preferences from database (loaded by service layer)"
    )
    # Note: pantry_items are passed separately to meal recommender workflow when needed


class ChatResponse(BaseModel):
    """Response schema for chat workflow (used by API)"""
    response: str = Field(..., description="Streamed text response to user")
    action: Optional[ChatAction] = Field(
        None,
        description="Action that was taken (if any)"
    )
    task_id: Optional[str] = Field(
        None,
        description="Celery task ID if action is START_RECOMMENDATION"
    )
    updated_constraints: Optional[FilterConstraints] = Field(
        None,
        description="Updated constraints if action is ADD_CONSTRAINT (for frontend sync)"
    )
    chat_session_id: Optional[str] = Field(
        None,
        description="Chat session ID"
    )

