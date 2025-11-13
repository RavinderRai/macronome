from pydantic import BaseModel
from typing import List, Optional
from macronome.ai.schemas.recipe_schema import EnrichedRecipe

class MealRecommendation(BaseModel):
    """Final recommendation to return"""
    recipe: EnrichedRecipe
    why_it_fits: str                             # LLM-generated explanation
    ingredient_swaps: List[str] = []             # Suggested modifications
    pantry_utilization: List[str] = []           # Which pantry items used

class MealRecommendationResponse(BaseModel):
    """Workflow output"""
    success: bool
    recommendation: Optional[MealRecommendation] = None
    error_message: Optional[str] = None          # If constraints couldn't be met
    suggestions: List[str] = []                  # How to modify constraints