"""
API Request/Response Schemas
Pydantic models for FastAPI endpoints
"""
from typing import Optional, List, Dict, Any
from datetime import datetime
from pydantic import BaseModel, Field


# ============================================================================
# Pantry Schemas
# ============================================================================

class DetectedItem(BaseModel):
    """Detected pantry item from ML scan"""
    name: str
    category: Optional[str] = None
    confidence: float
    bounding_box: Optional[Dict[str, int]] = None


class PantryScanResponse(BaseModel):
    """Response from pantry scan endpoint"""
    items: List[DetectedItem]
    num_items: int


class PantryItemCreate(BaseModel):
    """Create pantry item"""
    name: str
    category: Optional[str] = None
    confirmed: bool = True
    confidence: Optional[float] = None


class PantryItemResponse(BaseModel):
    """Pantry item response"""
    id: str
    user_id: str
    name: str
    category: Optional[str]
    confirmed: bool
    confidence: Optional[float]
    created_at: datetime
    updated_at: datetime


class PantryItemsResponse(BaseModel):
    """List of pantry items"""
    items: List[PantryItemResponse]
    total: int


# ============================================================================
# Meals Schemas
# ============================================================================

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


class RecipeResponse(BaseModel):
    """Recipe details"""
    id: str
    name: str
    ingredients: List[str]
    directions: str
    prep_time: Optional[int]
    calories: Optional[int]
    nutrition: Optional[Dict[str, Any]]


class MealRecommendationResponse(BaseModel):
    """Full meal recommendation"""
    recipe: RecipeResponse
    why_it_fits: str
    ingredient_swaps: List[str]
    pantry_utilization: List[str]
    recipe_instructions: str


class MealHistoryCreate(BaseModel):
    """Save meal to history"""
    name: str
    description: Optional[str]
    ingredients: List[str]
    reasoning: Optional[str]
    meal_data: Dict[str, Any]
    accepted: bool = False


class MealHistoryResponse(BaseModel):
    """Meal history item"""
    id: str
    user_id: str
    name: str
    description: Optional[str]
    ingredients: List[str]
    reasoning: Optional[str]
    accepted: bool
    rating: Optional[int]
    created_at: datetime


class MealRatingUpdate(BaseModel):
    """Update meal rating"""
    rating: int = Field(..., ge=1, le=5)


# ============================================================================
# Chat Schemas
# ============================================================================

class ChatMessageRequest(BaseModel):
    """Send chat message"""
    message: str
    chat_session_id: Optional[str] = None  # Create new if not provided


class ChatMessageResponse(BaseModel):
    """Chat message response"""
    response: str
    action: Optional[str] = None
    task_id: Optional[str] = None
    updated_constraints: Optional[Dict[str, Any]] = None
    chat_session_id: str


class ChatSessionResponse(BaseModel):
    """Chat session"""
    id: str
    user_id: str
    is_active: bool
    filters: Dict[str, Any]
    created_at: datetime
    updated_at: datetime


class ChatMessageHistoryResponse(BaseModel):
    """Chat message in history"""
    id: str
    chat_session_id: str
    text: str
    type: str  # user, assistant, system
    timestamp: datetime


class ChatSessionCreate(BaseModel):
    """Create new chat session"""
    filters: Optional[Dict[str, Any]] = None


# ============================================================================
# Preferences Schemas
# ============================================================================

class MacroConstraints(BaseModel):
    """Macro targets in grams"""
    carbs: Optional[int] = None
    protein: Optional[int] = None
    fat: Optional[int] = None


class UserPreferencesResponse(BaseModel):
    """User preferences - matches database model"""
    id: str
    user_id: str
    calories: Optional[int] = None
    macros: Optional[MacroConstraints] = None
    diet: Optional[str] = None
    allergies: List[str] = []
    prep_time: Optional[int] = None
    meal_type: Optional[str] = None
    custom_constraints: Dict[str, Any] = {}
    created_at: datetime
    updated_at: datetime


class UserPreferencesUpdate(BaseModel):
    """Update user preferences - only provided fields will be updated"""
    calories: Optional[int] = None
    macros: Optional[MacroConstraints] = None
    diet: Optional[str] = None
    allergies: Optional[List[str]] = None
    prep_time: Optional[int] = None
    meal_type: Optional[str] = None
    custom_constraints: Optional[Dict[str, Any]] = None

