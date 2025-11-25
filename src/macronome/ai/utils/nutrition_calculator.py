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
    
    def _convert_to_grams(self, quantity: float, unit: str, ingredient_name: str = "") -> float:
        """
        Convert ingredient quantity to grams based on unit.
        
        Uses standard conversions and density estimates for different ingredient types.
        
        Args:
            quantity: Amount of ingredient
            unit: Unit of measurement
            ingredient_name: Name of ingredient (for density estimation)
            
        Returns:
            Approximate weight in grams
        """
        unit_lower = unit.lower() if unit else ""
        
        # Weight units - direct conversion
        if "g" in unit_lower or "gram" in unit_lower:
            return quantity
        elif "kg" in unit_lower or "kilogram" in unit_lower:
            return quantity * 1000
        elif "oz" in unit_lower or "ounce" in unit_lower:
            return quantity * 28.35
        elif "lb" in unit_lower or "pound" in unit_lower:
            return quantity * 453.6
        
        # Volume units - convert based on typical ingredient density
        # Average densities used (varies by ingredient)
        
        # Cup conversions (240ml = 1 cup)
        if "cup" in unit_lower:
            # Different ingredients have different cup weights
            ing_lower = ingredient_name.lower()
            if any(x in ing_lower for x in ["flour", "sugar", "powder"]):
                # Flour, sugar: ~120-200g per cup
                return quantity * 120
            elif any(x in ing_lower for x in ["butter", "oil", "shortening"]):
                # Fats: ~225g per cup
                return quantity * 225
            elif any(x in ing_lower for x in ["water", "milk", "liquid", "juice"]):
                # Liquids: ~240g per cup
                return quantity * 240
            elif any(x in ing_lower for x in ["rice", "grain"]):
                # Grains: ~185g per cup
                return quantity * 185
            else:
                # Default: average density
                return quantity * 150
        
        # Tablespoon (15ml)
        if "tablespoon" in unit_lower or "tbsp" in unit_lower:
            return quantity * 15
        
        # Teaspoon (5ml)
        if "teaspoon" in unit_lower or "tsp" in unit_lower:
            return quantity * 5
        
        # Quart (946ml)
        if "quart" in unit_lower or "qt" in unit_lower:
            return quantity * 946
        
        # Pint (473ml)
        if "pint" in unit_lower or "pt" in unit_lower:
            return quantity * 473
        
        # Container units - rough estimates
        if "can" in unit_lower:
            # Standard can: ~400g
            return quantity * 400
        elif "jar" in unit_lower:
            # Standard jar: ~350g
            return quantity * 350
        elif "box" in unit_lower or "pkg" in unit_lower or "package" in unit_lower:
            # Standard box/package: ~300g
            return quantity * 300
        elif "carton" in unit_lower:
            # Standard carton: ~500g
            return quantity * 500
        elif "bottle" in unit_lower:
            # Standard bottle: ~500ml = 500g
            return quantity * 500
        
        # Size descriptors
        if "small" in unit_lower:
            return quantity * 150
        elif "medium" in unit_lower:
            return quantity * 250
        elif "large" in unit_lower:
            return quantity * 350
        
        # Bread/loaf units
        if "loaf" in unit_lower:
            # Average Italian/French bread loaf: ~600g
            return quantity * 600
        
        # Piece-based units (estimate)
        if any(x in unit_lower for x in ["slice", "piece", "clove", "serving"]):
            return quantity * 50  # Conservative estimate
        
        # Fallback: treat as ~100g per unit
        logger.debug(f"Unknown unit '{unit}', using default conversion: {quantity} * 100g")
        return quantity * 100
    
    async def calculate(self, ingredients: List[ParsedIngredient]) -> NutritionInfo:
        """
        Calculate total nutrition for a list of ingredients.
        
        Uses USDA API with caching and improved unit conversions.
        Converts all quantities to grams before scaling nutrition data.
        
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
            
            # USDA returns nutrition per 100g
            # All quantities should be in grams for accurate calculation
            # Formula: N = (V × W) / 100, where V = value per 100g, W = weight in grams
            unit_lower = ing.unit.lower() if ing.unit else ""
            
            # Only accept grams for accurate nutrition calculation
            if unit_lower in ["g", "gram", "grams"]:
                # Quantity is in grams, scale using formula: W / 100
                grams = ing.quantity
                scale = ing.quantity / 100.0
            else:
                # Warn about non-gram units
                # For baseline nutrition from original recipes, this is expected
                # For modified recipes, ModificationAgent should output grams only
                logger.warning(
                    f"Non-gram unit '{ing.unit}' for {ing.ingredient}. "
                    f"Attempting unit conversion for baseline calculation."
                )
                # For non-gram units, attempt conversion
                grams = self._convert_to_grams(ing.quantity, ing.unit, ing.ingredient)
                scale = grams / 100.0
            
            # Add to totals
            total_calories += usda_data.get("calories", 0) * scale
            total_protein += usda_data.get("protein", 0) * scale
            total_carbs += usda_data.get("carbs", 0) * scale
            total_fat += usda_data.get("fat", 0) * scale
            
            logger.debug(f"  {ing.quantity} {ing.unit} {ing.ingredient} = {grams:.1f}g "
                        f"(+{usda_data.get('calories', 0) * scale:.0f} cal)")
        
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

