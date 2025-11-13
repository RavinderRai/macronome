import logging
import os
from typing import Dict, Optional
import httpx

from macronome.ai.core.nodes.base import Node
from macronome.ai.core.task import TaskContext
from macronome.ai.schemas.recipe_schema import NutritionInfo, ParsedIngredient
from macronome.ai.schemas.workflow_schemas import ModifiedRecipe

logger = logging.getLogger(__name__)

"""
Nutrition Node

Regular node (not AgentNode) that calculates exact nutrition using USDA FoodData Central API.
Computes calories, protein, carbs, and fat for the modified recipe.
"""


class NutritionNode(Node):
    """
    Sixth node in meal recommendation workflow.
    
    Calculates exact nutrition for modified recipe using USDA API.
    
    Input: ModifiedRecipe from ModificationAgent
    Output: NutritionInfo saved to task_context.nodes["NutritionNode"]
    
    Uses:
    - USDA FoodData Central API for ingredient nutrition lookup
    - Caching to minimize API calls
    - Fallback heuristics when API unavailable
    """
    
    def __init__(self, task_context: TaskContext = None):
        super().__init__(task_context)
        self._api_key = os.getenv("USDA_API_KEY")
        self._cache: Dict[str, Dict] = {}  # Simple in-memory cache
        self._client = httpx.AsyncClient(timeout=10.0)
    
    class OutputType(NutritionInfo):
        """NutritionNode outputs NutritionInfo"""
        pass
    
    async def _lookup_usda(self, ingredient_name: str) -> Optional[Dict]:
        """
        Look up ingredient nutrition in USDA FoodData Central API.
        
        Args:
            ingredient_name: Name of ingredient to look up
            
        Returns:
            Nutrition data per 100g, or None if not found
        """
        # Check cache first
        if ingredient_name in self._cache:
            logger.debug(f"Cache hit for: {ingredient_name}")
            return self._cache[ingredient_name]
        
        if not self._api_key:
            logger.warning("USDA_API_KEY not set, using fallback heuristics")
            return None
        
        try:
            # Search for ingredient
            search_url = "https://api.nal.usda.gov/fdc/v1/foods/search"
            params = {
                "api_key": self._api_key,
                "query": ingredient_name,
                "pageSize": 1,
                "dataType": ["SR Legacy"],  # Standard Reference
            }
            
            response = await self._client.get(search_url, params=params)
            response.raise_for_status()
            data = response.json()
            
            if not data.get("foods"):
                logger.warning(f"No USDA data found for: {ingredient_name}")
                return None
            
            food = data["foods"][0]
            nutrients = {}
            
            # Extract key nutrients (per 100g)
            for nutrient in food.get("foodNutrients", []):
                name = nutrient.get("nutrientName", "").lower()
                value = nutrient.get("value", 0)
                
                if "energy" in name or "calorie" in name:
                    nutrients["calories"] = value
                elif "protein" in name:
                    nutrients["protein"] = value
                elif "carbohydrate" in name:
                    nutrients["carbs"] = value
                elif "total lipid" in name or "fat" in name:
                    nutrients["fat"] = value
            
            # Cache the result
            self._cache[ingredient_name] = nutrients
            logger.debug(f"Cached USDA data for: {ingredient_name}")
            
            return nutrients
            
        except Exception as e:
            logger.error(f"USDA API error for '{ingredient_name}': {e}")
            return None
    
    def _estimate_nutrition_fallback(self, ingredient_name: str, quantity_grams: float) -> Dict:
        """
        Fallback heuristic-based nutrition estimation.
        
        Args:
            ingredient_name: Ingredient name
            quantity_grams: Amount in grams
            
        Returns:
            Estimated nutrition
        """
        name_lower = ingredient_name.lower()
        
        # Simple heuristics (per 100g)
        if any(word in name_lower for word in ["chicken", "turkey"]):
            return {
                "calories": int(1.65 * quantity_grams / 100),
                "protein": int(31 * quantity_grams / 100),
                "carbs": 0,
                "fat": int(3.6 * quantity_grams / 100),
            }
        elif any(word in name_lower for word in ["beef", "pork"]):
            return {
                "calories": int(2.5 * quantity_grams / 100),
                "protein": int(26 * quantity_grams / 100),
                "carbs": 0,
                "fat": int(17 * quantity_grams / 100),
            }
        elif any(word in name_lower for word in ["rice", "pasta"]):
            return {
                "calories": int(1.3 * quantity_grams / 100),
                "protein": int(2.7 * quantity_grams / 100),
                "carbs": int(28 * quantity_grams / 100),
                "fat": int(0.3 * quantity_grams / 100),
            }
        elif any(word in name_lower for word in ["cheese", "butter"]):
            return {
                "calories": int(3.5 * quantity_grams / 100),
                "protein": int(25 * quantity_grams / 100),
                "carbs": int(1.3 * quantity_grams / 100),
                "fat": int(33 * quantity_grams / 100),
            }
        elif any(word in name_lower for word in ["vegetable", "lettuce", "spinach", "broccoli"]):
            return {
                "calories": int(0.25 * quantity_grams / 100),
                "protein": int(2 * quantity_grams / 100),
                "carbs": int(5 * quantity_grams / 100),
                "fat": int(0.3 * quantity_grams / 100),
            }
        else:
            # Generic fallback
            return {
                "calories": int(1.0 * quantity_grams / 100),
                "protein": int(3 * quantity_grams / 100),
                "carbs": int(10 * quantity_grams / 100),
                "fat": int(2 * quantity_grams / 100),
            }
    
    def _convert_to_grams(self, quantity: float, unit: str, ingredient: str) -> float:
        """
        Convert quantity to grams (rough conversion).
        
        Args:
            quantity: Amount
            unit: Unit (cup, tbsp, oz, etc.)
            ingredient: Ingredient name (for density estimates)
            
        Returns:
            Estimated grams
        """
        unit_lower = unit.lower()
        
        # Common conversions
        conversions = {
            "g": 1.0,
            "gram": 1.0,
            "kg": 1000.0,
            "oz": 28.35,
            "lb": 453.59,
            "cup": 240.0,  # Assumes liquid/granular
            "tbsp": 15.0,
            "tablespoon": 15.0,
            "tsp": 5.0,
            "teaspoon": 5.0,
            "ml": 1.0,  # Assumes water density
            "l": 1000.0,
        }
        
        for key, factor in conversions.items():
            if key in unit_lower:
                return quantity * factor
        
        # Default: assume 100g per unit
        return quantity * 100.0
    
    async def process(self, task_context: TaskContext) -> TaskContext:
        """
        Calculate exact nutrition for modified recipe.
        
        Args:
            task_context: Contains ModifiedRecipe from ModificationAgent
            
        Returns:
            TaskContext with nutrition info saved
        """
        # Get modified recipe
        modified: ModifiedRecipe = task_context.nodes.get("ModificationAgent")
        if not modified:
            raise ValueError("ModifiedRecipe not found in task context")
        
        logger.info(f"Calculating nutrition for {len(modified.ingredients)} ingredients")
        
        # Calculate nutrition for each ingredient
        total_calories = 0
        total_protein = 0
        total_carbs = 0
        total_fat = 0
        
        for ing in modified.ingredients:
            # Convert to grams
            quantity_grams = self._convert_to_grams(
                ing.quantity,
                ing.unit,
                ing.ingredient
            )
            
            # Try USDA lookup first
            usda_data = await self._lookup_usda(ing.ingredient)
            
            if usda_data:
                # Use USDA data (per 100g, scale to actual quantity)
                scale = quantity_grams / 100.0
                total_calories += usda_data.get("calories", 0) * scale
                total_protein += usda_data.get("protein", 0) * scale
                total_carbs += usda_data.get("carbs", 0) * scale
                total_fat += usda_data.get("fat", 0) * scale
            else:
                # Use fallback heuristics
                fallback = self._estimate_nutrition_fallback(ing.ingredient, quantity_grams)
                total_calories += fallback["calories"]
                total_protein += fallback["protein"]
                total_carbs += fallback["carbs"]
                total_fat += fallback["fat"]
        
        # Create nutrition info
        nutrition = NutritionInfo(
            calories=int(total_calories),
            protein=int(total_protein),
            carbs=int(total_carbs),
            fat=int(total_fat),
        )
        
        logger.info(f"Nutrition calculated: {nutrition.calories} cal, {nutrition.protein}g protein")
        
        # Save to task context
        self.save_output(nutrition)
        
        return task_context
    
    async def __aexit__(self, *args):
        """Clean up HTTP client"""
        await self._client.aclose()

