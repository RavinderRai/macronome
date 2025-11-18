"""
Database models and schemas
These represent the Supabase tables structure
Aligned with frontend types in apps/mobile/src/types/
"""
from pydantic import BaseModel, Field
from typing import Optional, Dict, Any, List
from datetime import datetime


# ============================================================================
# Pantry Models
# ============================================================================

class PantryImage(BaseModel):
    """Pantry image model - stores uploaded images"""
    id: Optional[str] = None
    user_id: str = Field(..., description="Clerk user ID")
    storage_url: str = Field(..., description="Supabase Storage URL")
    uploaded_at: Optional[datetime] = None
    metadata: Dict[str, Any] = Field(
        default_factory=dict,
        description="Image metadata (filename, size, etc.)"
    )
    
    class Config:
        from_attributes = True


class PantryItem(BaseModel):
    """
    Pantry item model - aligned with apps/mobile/src/types/pantry.ts
    Items detected from images or manually added
    """
    id: Optional[str] = None
    user_id: str = Field(..., description="Clerk user ID")
    image_id: Optional[str] = Field(None, description="Foreign key to pantry_images (nullable for manual adds)")
    name: str = Field(..., description="Item name (from classification)")
    category: Optional[str] = Field(None, description="Category (LLM-parsed string, no enum)")
    confirmed: bool = Field(default=False, description="User confirmed detection")
    confidence: Optional[float] = Field(None, description="Detection confidence (0-1)")
    detected_at: Optional[datetime] = Field(None, description="When item was detected")
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
    
    class Config:
        from_attributes = True


# ============================================================================
# User Preferences (Global)
# ============================================================================

class MacroConstraints(BaseModel):
    """Macro targets in grams - matches frontend MacroConstraints"""
    carbs: Optional[int] = None
    protein: Optional[int] = None
    fat: Optional[int] = None
    
    class Config:
        from_attributes = True


class UserPreferences(BaseModel):
    """
    Global user preferences
    """
    id: Optional[str] = None
    user_id: str = Field(..., description="Clerk user ID (unique)")
    
    # Filter constraints (from UI filters)
    calories: Optional[int] = Field(None, description="Target calories")
    macros: Optional[MacroConstraints] = Field(None, description="Macro targets (carbs, protein, fat in grams)")
    diet: Optional[str] = Field(None, description="Diet type (e.g. 'vegan', 'keto', 'vegetarian')")
    allergies: List[str] = Field(
        default_factory=list,
        description="Allergies/excluded ingredients (from UI filter)"
    )
    prep_time: Optional[int] = Field(None, description="Maximum prep time in minutes")
    meal_type: Optional[str] = Field(None, description="Meal type: 'breakfast', 'lunch', 'snack', 'dinner', 'dessert'")
    
    custom_constraints: Dict[str, Any] = Field(
        default_factory=dict,
        description="Custom constraints parsed from chat (e.g. 'spicy', 'quick', cuisine preferences)"
    )
    
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
    
    class Config:
        from_attributes = True


# ============================================================================
# Chat Models
# ============================================================================

class ChatSession(BaseModel):
    """
    Chat session model - one active session per user
    Stores session-level filters and constraints
    """
    id: Optional[str] = None
    user_id: str = Field(..., description="Clerk user ID")
    is_active: bool = Field(default=True, description="Only one active session per user")
    filters: Dict[str, Any] = Field(
        default_factory=dict,
        description="Session filters - aligned with FilterConstraints from frontend. "
                   "Includes: calories, macros (carbs/protein/fat), diet, excludedIngredients, prepTime. "
                   "Custom constraints parsed by LLM are also stored here as dict."
    )
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
    
    class Config:
        from_attributes = True


class ChatMessage(BaseModel):
    """
    Chat message model - aligned with apps/mobile/src/types/chat.ts
    """
    id: Optional[str] = None
    chat_session_id: str = Field(..., description="Foreign key to chat_sessions")
    text: str = Field(..., description="Message content")
    type: str = Field(..., description="Message type: 'user', 'assistant', or 'system'")
    timestamp: Optional[datetime] = None
    
    class Config:
        from_attributes = True


# ============================================================================
# Meal Recommendation Models
# ============================================================================

class MealRecommendation(BaseModel):
    """
    Meal recommendation model - aligned with apps/mobile/src/types/chat.ts Meal interface
    """
    id: Optional[str] = None
    user_id: str = Field(..., description="Clerk user ID")
    chat_session_id: str = Field(..., description="Foreign key to chat_sessions (which session generated this)")
    name: str = Field(..., description="Meal name")
    description: Optional[str] = None
    image_url: Optional[str] = None
    prep_time: Optional[int] = Field(None, description="Prep time in minutes")
    calories: Optional[int] = None
    ingredients: List[str] = Field(default_factory=list)
    reasoning: Optional[str] = Field(None, description="LLM reasoning for why this meal was recommended")
    meal_data: Dict[str, Any] = Field(
        default_factory=dict,
        description="Complete meal recommendation data (full workflow output)"
    )
    accepted: bool = Field(default=False, description="User accepted the meal")
    rating: Optional[int] = Field(None, ge=1, le=5, description="User rating (1-5)")
    created_at: Optional[datetime] = None
    
    class Config:
        from_attributes = True
