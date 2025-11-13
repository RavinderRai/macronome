"""
Nutrition Calculator Utility

Reusable utility for calculating recipe nutrition using USDA API.
Designed to be used as a tool by ModificationAgent and as a standalone node.
"""
import logging
import os
from typing import Dict, List, Optional
import httpx

from macronome.ai.schemas.recipe_schema import NutritionInfo, ParsedIngredient

logger = logging.getLogger(__name__)


class NutritionCalculator:
    """
    Utility class for calculating nutrition with USDA API and caching.
    
    Features:
    - USDA FoodData Central API integration
    - In-memory caching to avoid redundant API calls
    - Fallback heuristics when API unavailable
    - Unit conversion (cups, tbsp, etc. to grams)
    """
    
    def __init__(self):
        self._api_key = os.getenv("USDA_API_KEY")
        self._cache: Dict[str, Dict] = {}  # Cache: ingredient_name -> nutrition per 100g
        self._client = httpx.AsyncClient(timeout=10.0)
    
    async def _lookup_usda(self, ingredient_name: str) -> Optional[Dict]:
        """
        Look up ingredient nutrition in USDA FoodData Central API.
        
        Args:
            ingredient_name: Name of ingredient to look up
            
        Returns:
            Nutrition data per 100g: {calories, protein, carbs, fat}, or None if not found
        """
        # Check cache first
        cache_key = ingredient_name.lower().strip()
        if cache_key in self._cache:
            logger.debug(f"Cache hit for: {ingredient_name}")
            return self._cache[cache_key]
        
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
            self._cache[cache_key] = nutrients
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
            Estimated nutrition: {calories, protein, carbs, fat}
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
    
    async def calculate(self, ingredients: List[ParsedIngredient]) -> NutritionInfo:
        """
        Calculate total nutrition for a list of ingredients.
        
        Uses USDA API with caching - only makes API calls for ingredients not in cache.
        
        Args:
            ingredients: List of parsed ingredients with quantities and units
            
        Returns:
            Total nutrition info for the recipe
        """
        logger.info(f"Calculating nutrition for {len(ingredients)} ingredients")
        
        total_calories = 0
        total_protein = 0
        total_carbs = 0
        total_fat = 0
        
        for ing in ingredients:
            # Convert to grams
            quantity_grams = self._convert_to_grams(
                ing.quantity,
                ing.unit,
                ing.ingredient
            )
            
            # Try USDA lookup first (uses cache internally)
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
        
        nutrition = NutritionInfo(
            calories=int(total_calories),
            protein=int(total_protein),
            carbs=int(total_carbs),
            fat=int(total_fat),
        )
        
        logger.info(f"Nutrition calculated: {nutrition.calories} cal, {nutrition.protein}g protein")
        
        return nutrition
    
    async def close(self):
        """Clean up HTTP client"""
        await self._client.aclose()

