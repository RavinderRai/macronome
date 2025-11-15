"""
Chat workflow schemas
Defines request/response models for chat workflow and nodes
"""
from enum import Enum
from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field


class ChatAction(str, Enum):
    """Actions that chat router can decide"""
    ADD_CONSTRAINT = "add_constraint"
    START_RECOMMENDATION = "start_recommendation"
    GENERAL_CHAT = "general_chat"


class ChatRouterOutput(BaseModel):
    """Output from ChatRouter node - routes user message to appropriate action"""
    action: ChatAction = Field(..., description="Detected user intention")
    confidence: float = Field(..., ge=0.0, le=1.0, description="Confidence in action classification")
    reasoning: str = Field(..., description="Explanation of why this action was chosen")


class ConstraintUpdate(BaseModel):
    """
    Updated constraints after parsing from chat message
    Matches user_preferences database structure exactly
    """
    default_constraints: Dict[str, Any] = Field(
        default_factory=dict,
        description="FilterConstraints: calories, macros (carbs/protein/fat), diet, excludedIngredients, prepTime. "
                   "Matches frontend FilterConstraints structure."
    )
    dietary_restrictions: List[str] = Field(
        default_factory=list,
        description="Diet types: vegetarian, vegan, gluten-free, etc. (LLM-parsed strings)"
    )
    custom_constraints: Dict[str, Any] = Field(
        default_factory=dict,
        description="Custom constraints parsed from chat: spicy, quick, cuisine, meal_type, etc."
    )
    disliked_ingredients: List[str] = Field(
        default_factory=list,
        description="Ingredients user dislikes (separate from excludedIngredients in default_constraints)"
    )
    favorite_cuisines: List[str] = Field(
        default_factory=list,
        description="User's favorite cuisines (optional, rarely updated via chat)"
    )
    updated_fields: List[str] = Field(
        default_factory=list,
        description="List of field names that were updated (e.g., ['default_constraints', 'dietary_restrictions'])"
    )


class ConstraintParserOutput(BaseModel):
    """Output from ConstraintParser node"""
    updated_constraints: ConstraintUpdate = Field(..., description="Merged constraints after parsing")
    confirmation_message: str = Field(
        ...,
        description="User-friendly confirmation message (e.g., 'Added vegan diet' or 'Updated calories to 700')"
    )


class ChatRequest(BaseModel):
    """Request schema for chat workflow"""
    message: str = Field(..., description="User's chat message")
    chat_session_id: str = Field(..., description="Active chat session ID")
    user_id: str = Field(..., description="Clerk user ID")
    # Note: user_preferences are loaded from DB in ConstraintParser node
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
    updated_constraints: Optional[ConstraintUpdate] = Field(
        None,
        description="Updated constraints if action is ADD_CONSTRAINT (for frontend sync)"
    )

