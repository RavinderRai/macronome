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

class UserPreferences(BaseModel):
    """Global user preferences - stored separately from chat sessions"""
    id: Optional[str] = None
    user_id: str = Field(..., description="Clerk user ID (unique)")
    dietary_restrictions: List[str] = Field(
        default_factory=list,
        description="Dietary restrictions (LLM-parsed strings, e.g. 'vegetarian', 'gluten-free')"
    )
    default_constraints: Dict[str, Any] = Field(
        default_factory=dict,
        description="Default meal constraints (calories, macros, etc.)"
    )
    favorite_cuisines: List[str] = Field(default_factory=list)
    disliked_ingredients: List[str] = Field(default_factory=list)
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


# ============================================================================
# SQL Schema for Supabase
# ============================================================================

SQL_SCHEMA = """
-- ============================================================================
-- Pantry Images Table
-- ============================================================================
CREATE TABLE pantry_images (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id TEXT NOT NULL,  -- Clerk user ID
    storage_url TEXT NOT NULL,  -- Supabase Storage URL
    uploaded_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()),
    metadata JSONB DEFAULT '{}'
);

-- RLS Policies
ALTER TABLE pantry_images ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own pantry images"
    ON pantry_images FOR SELECT
    USING (auth.uid()::text = user_id);

CREATE POLICY "Users can insert their own pantry images"
    ON pantry_images FOR INSERT
    WITH CHECK (auth.uid()::text = user_id);

CREATE POLICY "Users can delete their own pantry images"
    ON pantry_images FOR DELETE
    USING (auth.uid()::text = user_id);

CREATE INDEX idx_pantry_images_user_id ON pantry_images(user_id);
CREATE INDEX idx_pantry_images_uploaded_at ON pantry_images(uploaded_at DESC);

-- ============================================================================
-- Pantry Items Table
-- ============================================================================
CREATE TABLE pantry_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id TEXT NOT NULL,  -- Clerk user ID
    image_id UUID REFERENCES pantry_images(id) ON DELETE SET NULL,  -- Nullable for manual adds
    name TEXT NOT NULL,
    category TEXT,  -- LLM-parsed string (no enum)
    confirmed BOOLEAN DEFAULT FALSE,
    confidence FLOAT,
    detected_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW())
);

-- RLS Policies
ALTER TABLE pantry_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own pantry items"
    ON pantry_items FOR SELECT
    USING (auth.uid()::text = user_id);

CREATE POLICY "Users can insert their own pantry items"
    ON pantry_items FOR INSERT
    WITH CHECK (auth.uid()::text = user_id);

CREATE POLICY "Users can update their own pantry items"
    ON pantry_items FOR UPDATE
    USING (auth.uid()::text = user_id);

CREATE POLICY "Users can delete their own pantry items"
    ON pantry_items FOR DELETE
    USING (auth.uid()::text = user_id);

CREATE INDEX idx_pantry_items_user_id ON pantry_items(user_id);
CREATE INDEX idx_pantry_items_image_id ON pantry_items(image_id);
CREATE INDEX idx_pantry_items_confirmed ON pantry_items(confirmed);

-- ============================================================================
-- User Preferences Table (Global)
-- ============================================================================
CREATE TABLE user_preferences (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id TEXT NOT NULL UNIQUE,  -- Clerk user ID
    dietary_restrictions JSONB DEFAULT '[]',  -- Array of strings (LLM-parsed)
    default_constraints JSONB DEFAULT '{}',  -- Default meal constraints
    favorite_cuisines JSONB DEFAULT '[]',
    disliked_ingredients JSONB DEFAULT '[]',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW())
);

-- RLS Policies
ALTER TABLE user_preferences ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own preferences"
    ON user_preferences FOR SELECT
    USING (auth.uid()::text = user_id);

CREATE POLICY "Users can insert their own preferences"
    ON user_preferences FOR INSERT
    WITH CHECK (auth.uid()::text = user_id);

CREATE POLICY "Users can update their own preferences"
    ON user_preferences FOR UPDATE
    USING (auth.uid()::text = user_id);

CREATE INDEX idx_user_preferences_user_id ON user_preferences(user_id);

-- ============================================================================
-- Chat Sessions Table
-- ============================================================================
CREATE TABLE chat_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id TEXT NOT NULL,  -- Clerk user ID
    is_active BOOLEAN DEFAULT TRUE,
    filters JSONB DEFAULT '{}',  -- FilterConstraints + custom constraints (LLM-parsed)
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW()),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW())
);

-- Unique constraint: only one active session per user
CREATE UNIQUE INDEX idx_chat_sessions_user_active 
    ON chat_sessions(user_id) 
    WHERE is_active = TRUE;

-- RLS Policies
ALTER TABLE chat_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own chat sessions"
    ON chat_sessions FOR SELECT
    USING (auth.uid()::text = user_id);

CREATE POLICY "Users can insert their own chat sessions"
    ON chat_sessions FOR INSERT
    WITH CHECK (auth.uid()::text = user_id);

CREATE POLICY "Users can update their own chat sessions"
    ON chat_sessions FOR UPDATE
    USING (auth.uid()::text = user_id);

CREATE POLICY "Users can delete their own chat sessions"
    ON chat_sessions FOR DELETE
    USING (auth.uid()::text = user_id);

CREATE INDEX idx_chat_sessions_user_id ON chat_sessions(user_id);
CREATE INDEX idx_chat_sessions_is_active ON chat_sessions(is_active);

-- ============================================================================
-- Chat Messages Table
-- ============================================================================
CREATE TABLE chat_messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    chat_session_id UUID NOT NULL REFERENCES chat_sessions(id) ON DELETE CASCADE,
    text TEXT NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('user', 'assistant', 'system')),
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW())
);

-- RLS Policies
ALTER TABLE chat_messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view messages from their own chat sessions"
    ON chat_messages FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM chat_sessions 
            WHERE chat_sessions.id = chat_messages.chat_session_id 
            AND chat_sessions.user_id = auth.uid()::text
        )
    );

CREATE POLICY "Users can insert messages to their own chat sessions"
    ON chat_messages FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM chat_sessions 
            WHERE chat_sessions.id = chat_messages.chat_session_id 
            AND chat_sessions.user_id = auth.uid()::text
        )
    );

CREATE INDEX idx_chat_messages_session_id ON chat_messages(chat_session_id);
CREATE INDEX idx_chat_messages_timestamp ON chat_messages(timestamp);

-- ============================================================================
-- Meal Recommendations Table
-- ============================================================================
CREATE TABLE meal_recommendations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id TEXT NOT NULL,  -- Clerk user ID
    chat_session_id UUID NOT NULL REFERENCES chat_sessions(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    image_url TEXT,
    prep_time INTEGER,  -- in minutes
    calories INTEGER,
    ingredients JSONB DEFAULT '[]',  -- Array of strings
    reasoning TEXT,  -- LLM reasoning
    meal_data JSONB NOT NULL,  -- Complete meal recommendation data (full workflow output)
    accepted BOOLEAN DEFAULT FALSE,
    rating INTEGER CHECK (rating >= 1 AND rating <= 5),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc', NOW())
);

-- RLS Policies
ALTER TABLE meal_recommendations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own meal recommendations"
    ON meal_recommendations FOR SELECT
    USING (auth.uid()::text = user_id);

CREATE POLICY "Users can insert their own meal recommendations"
    ON meal_recommendations FOR INSERT
    WITH CHECK (auth.uid()::text = user_id);

CREATE POLICY "Users can update their own meal recommendations"
    ON meal_recommendations FOR UPDATE
    USING (auth.uid()::text = user_id);

CREATE INDEX idx_meal_recommendations_user_id ON meal_recommendations(user_id);
CREATE INDEX idx_meal_recommendations_chat_session_id ON meal_recommendations(chat_session_id);
CREATE INDEX idx_meal_recommendations_created_at ON meal_recommendations(created_at DESC);
"""
