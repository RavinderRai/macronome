from pydantic import BaseModel
from typing import List, Optional

class Recipe(BaseModel):
    """Recipe from RecipeNLG"""
    id: str
    title: str
    ingredients: List[str]
    directions: str
    ner: List[str]                               # Named entities (ingredients)
    source: Optional[str] = None
    link: Optional[str] = None

class ParsedIngredient(BaseModel):
    """Structured ingredient after LLM parsing"""
    ingredient: str                              # "brown sugar"
    quantity: float                              # 1.0
    unit: str                                    # "cup"
    modifier: Optional[str] = None               # "firmly packed"

class NutritionInfo(BaseModel):
    """Calculated nutrition"""
    calories: int
    protein: int                                 # grams
    carbs: int
    fat: int

class EnrichedRecipe(Recipe):
    """Recipe with calculated nutrition"""
    parsed_ingredients: List[ParsedIngredient]
    nutrition: NutritionInfo
    prep_time_estimate: Optional[int] = None     # minutes
    pantry_match_score: float = 0.0              # 0-1
    semantic_score: float = 0.0                  # 0-1