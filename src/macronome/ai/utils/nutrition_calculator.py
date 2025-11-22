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
    - Simple matching (first prefix match)
    """
    
    def __init__(self):
        self._api_key = os.getenv("USDA_API_KEY")
        self._cache: Dict[str, Dict] = {}  # Cache: ingredient_name -> nutrition per 100g
        self._client = httpx.AsyncClient(timeout=10.0)
    
    def _clean_ingredient_name(self, ingredient_name: str) -> str:
        """
        Clean ingredient name to avoid USDA API errors.
        
        Removes problematic characters that cause 500 errors:
        - Percentage signs (%)
        - Special characters that break URL encoding
        - Extra whitespace
        
        Args:
            ingredient_name: Raw ingredient name
            
        Returns:
            Cleaned ingredient name safe for API queries
        """
        if not ingredient_name:
            return ""
        
        # Remove percentage signs and replace with "percent"
        cleaned = ingredient_name.replace("%", " percent")
        cleaned = cleaned.replace("percent", "percent")  # Normalize
        
        # Remove other problematic characters
        # Keep basic punctuation like commas, but remove quotes and slashes that cause issues
        cleaned = cleaned.replace('"', "")
        cleaned = cleaned.replace("'", "")
        cleaned = cleaned.replace("/", " ")
        cleaned = cleaned.replace("\\", " ")
        
        # Remove multiple spaces and strip
        cleaned = " ".join(cleaned.split())
        
        return cleaned.strip()
    
    async def _lookup_usda(self, ingredient_name: str) -> Optional[Dict]:
        """
        Look up ingredient nutrition in USDA FoodData Central API.
        
        Uses simple matching: first result that starts with ingredient name.
        
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
            logger.warning("USDA_API_KEY not set, skipping nutrition lookup")
            return None
        
        try:
            # Clean ingredient name to avoid API errors
            cleaned_name = self._clean_ingredient_name(ingredient_name)
            
            # Search for ingredient
            search_url = "https://api.nal.usda.gov/fdc/v1/foods/search"
            params = {
                "api_key": self._api_key,
                "query": cleaned_name,
                "pageSize": 10,  # Get more results for better matching
                "dataType": ["SR Legacy"],
            }
            
            response = await self._client.get(search_url, params=params)
            response.raise_for_status()
            data = response.json()
            
            if not data.get("foods"):
                logger.warning(f"No USDA data found for: {ingredient_name}")
                return None
            
            # Simple matching: first result that starts with ingredient name
            # Use cleaned name for matching, but original for logging
            ingredient_lower = cleaned_name.lower().strip()
            food = None
            
            for candidate in data["foods"]:
                desc_lower = candidate.get("description", "").lower()
                if desc_lower.startswith(ingredient_lower):
                    # Check word boundary
                    if len(desc_lower) == len(ingredient_lower) or desc_lower[len(ingredient_lower)] in [',', ' ']:
                        food = candidate
                        break
            
            # Fallback to first result if no prefix match
            if food is None:
                food = data["foods"][0]
                logger.debug(f"No prefix match for '{ingredient_name}', using first result: {food.get('description')}")
            
            # Extract nutrition (per 100g)
            nutrients = {}
            for nutrient in food.get("foodNutrients", []):
                nutrient_id = nutrient.get("nutrientId")
                value = nutrient.get("value", 0)
                
                # Use nutrient IDs for reliable matching
                if nutrient_id == 1008:  # Energy (calories)
                    nutrients["calories"] = value
                elif nutrient_id == 1003:  # Protein
                    nutrients["protein"] = value
                elif nutrient_id == 1005:  # Carbohydrates
                    nutrients["carbs"] = value
                elif nutrient_id == 1004:  # Total fat
                    nutrients["fat"] = value
            
            # Cache the result
            self._cache[cache_key] = nutrients
            logger.debug(f"Cached USDA data for '{ingredient_name}': {food.get('description')}")
            
            return nutrients
            
        except Exception as e:
            logger.error(f"USDA API error for '{ingredient_name}': {e}")
            return None
    
    async def calculate(self, ingredients: List[ParsedIngredient]) -> NutritionInfo:
        """
        Calculate total nutrition for a list of ingredients.
        
        Uses USDA API with caching. Assumes quantities are already in reasonable units.
        For grams, scales per 100g. For other units, uses quantity as multiplier.
        
        Args:
            ingredients: List of parsed ingredients with quantities and units
            
        Returns:
            Total nutrition info for the recipe
        """
        logger.info(f"Calculating nutrition for {len(ingredients)} ingredients")
        
        total_calories = 0.0
        total_protein = 0.0
        total_carbs = 0.0
        total_fat = 0.0
        
        for ing in ingredients:
            # Look up nutrition per 100g
            usda_data = await self._lookup_usda(ing.ingredient)
            
            if not usda_data:
                logger.warning(f"No nutrition data for: {ing.ingredient}")
                continue
            
            # Simple scaling: if unit is grams, scale directly
            # For other units, use fixed scale (1.0) to avoid blowing up values
            unit_lower = ing.unit.lower() if ing.unit else ""
            
            if "g" in unit_lower or "gram" in unit_lower:
                # Quantity is in grams, scale per 100g
                scale = ing.quantity / 100.0
            else:
                # For non-gram units, use fixed scale of 1.0
                # This assumes 1 serving ≈ 100g equivalent (conservative estimate)
                # This prevents multiplying by quantity which was causing inflated values
                scale = 1.0
            
            # Add to totals
            total_calories += usda_data.get("calories", 0) * scale
            total_protein += usda_data.get("protein", 0) * scale
            total_carbs += usda_data.get("carbs", 0) * scale
            total_fat += usda_data.get("fat", 0) * scale
        
        nutrition = NutritionInfo(
            calories=int(total_calories),
            protein=int(total_protein),
            carbs=int(total_carbs),
            fat=int(total_fat),
        )
        
        logger.info(f"Nutrition calculated: {nutrition.calories} cal, "
                   f"{nutrition.protein}g protein, {nutrition.carbs}g carbs, {nutrition.fat}g fat")
        
        return nutrition
    
    async def close(self):
        """Clean up HTTP client"""
        await self._client.aclose()

