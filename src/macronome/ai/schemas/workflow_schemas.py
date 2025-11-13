"""
Workflow-specific schemas for meal recommendation pipeline
"""
from typing import List, Optional, Dict, Any
from pydantic import BaseModel, Field
from macronome.ai.schemas.recipe_schema import ParsedIngredient, EnrichedRecipe


class PlanningOutput(BaseModel):
    """Output from Planning Agent"""
    search_query: str = Field(..., description="Optimized semantic query for recipe search")
    hard_filters: Dict[str, Any] = Field(default_factory=dict, description="meal_type, cuisine, max_prep_time")
    must_include: List[str] = Field(default_factory=list, description="From pantry (high priority)")
    must_exclude: List[str] = Field(default_factory=list, description="Allergies (hard constraint)")
    search_strategy: str = Field(..., description="pantry_first | semantic_first | balanced")
    top_k: int = Field(default=5, description="Number of candidates to retrieve")


class SelectionOutput(BaseModel):
    """Output from Selection Agent"""
    selected_recipe_id: str
    reasoning: str
    estimated_modification_effort: str  # "low" | "medium" | "high"


class ModifiedRecipe(BaseModel):
    """Output from Modification Agent"""
    recipe_id: str
    title: str
    ingredients: List[ParsedIngredient]
    directions: str
    modifications: List[str] = Field(default_factory=list, description="Description of changes made")
    reasoning: str


class RefinementDecision(BaseModel):
    """Output from Refinement Agent"""
    action: str  # "retry" | "ask_user"
    reasoning: str
    guidance: Optional[str] = None  # If retry, what to change
    user_question: Optional[str] = None  # If ask_user, what to ask


class MealRecommendation(BaseModel):
    """Final meal recommendation output"""
    recipe: EnrichedRecipe
    why_it_fits: str
    ingredient_swaps: List[str] = Field(default_factory=list)
    pantry_utilization: List[str] = Field(default_factory=list)


class FailureResponse(BaseModel):
    """Output when meal recommendation fails"""
    error_message: str
    suggestions: List[str] = Field(default_factory=list, description="How to modify constraints")
    which_constraints_conflict: List[str] = Field(default_factory=list)

