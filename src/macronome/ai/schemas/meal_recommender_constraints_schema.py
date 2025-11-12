from typing import Optional, List, Dict, Tuple, Set, Any
from pydantic import BaseModel

class MacroConstraints(BaseModel):
    """Numeric macro targets"""
    carbs: Optional[int] = None      # grams
    protein: Optional[int] = None    # grams
    fat: Optional[int] = None        # grams

class FilterConstraints(BaseModel):
    """User-specified constraints"""
    calories: Optional[int] = None              # Target (becomes ±50 range)
    macros: Optional[MacroConstraints] = None
    diet: Optional[str] = None                  # e.g., "vegan", "keto"
    excluded_ingredients: List[str] = []        # Allergies/dislikes
    prep_time: Optional[str] = None             # 'quick' | 'medium' | 'long'

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
    calorie_range: Optional[Tuple[int, int]] = None  # e.g., (650, 750)
    macro_targets: Optional[MacroConstraints] = None
    diet_type: Optional[str] = None
    excluded_ingredients: Set[str] = set()
    prep_time_max: Optional[int] = None              # minutes (quick=30, medium=60, long=None)
    custom_constraints: Dict[str, Any] = {}          # Parsed from chat (cuisine, meal_type, etc.)
    semantic_query: str = ""                         # Processed search query