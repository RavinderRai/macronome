from typing import Optional, List, Dict, Set, Any
from pydantic import BaseModel, Field, field_validator
from macronome.backend.database.models import MacroConstraints

class FilterConstraints(BaseModel):
    """
    User meal constraints - matches UserPreferences database structure exactly
    Used for both UI filters and chat-parsed constraints
    
    Accepts both camelCase (frontend: prepTime, mealType) and snake_case (backend: prep_time, meal_type)
    """
    calories: Optional[int] = Field(None, description="Target calories")
    macros: Optional[MacroConstraints] = Field(None, description="Macro targets (carbs, protein, fat in grams)")
    diet: Optional[str] = Field(None, description="Diet type (e.g. 'vegan', 'keto', 'vegetarian')")
    allergies: List[str] = Field(
        default_factory=list,
        description="Allergies/excluded ingredients"
    )
    prep_time: Optional[int] = Field(None, alias="prepTime", description="Maximum prep time in minutes")
    meal_type: Optional[str] = Field(None, alias="mealType", description="Meal type: 'breakfast', 'lunch', 'snack', 'dinner', 'dessert'")
    custom_constraints: Dict[str, Any] = Field(
        default_factory=dict,
        description="Custom constraints parsed from chat: spicy, quick, cuisine, etc."
    )
    
    class Config:
        populate_by_name = True  # Allow both field names (prep_time and prepTime)

class PantryItem(BaseModel):
    """Pantry context (not a hard constraint)"""
    name: str
    category: Optional[str] = None
    confirmed: bool = True

class MealRecommendationRequest(BaseModel):
    """Full request to workflow"""
    user_query: str                             # Free text: "something quick and spicy"
    constraints: FilterConstraints
    pantry_items: List[PantryItem] = []
    chat_history: List[Dict[str, str]] = []     # For context

class NormalizedConstraints(BaseModel):
    """Standardized constraints after parsing"""
    calorie_range: Optional[List[int]] = Field(
        None,
        description="Calorie range as [min, max] e.g., [650, 750]"
    )
    macro_targets: Optional[MacroConstraints] = None
    diet_type: Optional[str] = None
    excluded_ingredients: Set[str] = set()
    prep_time_max: Optional[int] = None              # minutes (quick=30, medium=60, long=None)
    custom_constraints: Dict[str, Any] = {}          # Parsed from chat (cuisine, meal_type, etc.)
    semantic_query: str = ""                         # Processed search query
    
    @field_validator('calorie_range')
    @classmethod
    def validate_calorie_range(cls, v):
        """Ensure calorie_range has exactly 2 items [min, max]"""
        if v is not None and len(v) != 2:
            raise ValueError("calorie_range must have exactly 2 items [min, max]")
        return v