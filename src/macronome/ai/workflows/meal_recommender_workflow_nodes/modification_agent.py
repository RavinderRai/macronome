import logging
from typing import List, Dict, Any
from pydantic_core import to_jsonable_python

from macronome.ai.core.nodes.agent import AgentNode, AgentConfig, ModelProvider
from macronome.ai.core.task import TaskContext
from macronome.ai.prompts import PromptManager
from macronome.ai.schemas.meal_recommender_constraints_schema import (
    MealRecommendationRequest,
)
from macronome.ai.workflows.meal_recommender_workflow_nodes.normalize_node import NormalizeNode
from macronome.ai.schemas.recipe_schema import Recipe
from macronome.ai.schemas.workflow_schemas import ModifiedRecipe

logger = logging.getLogger(__name__)

"""
Modification Agent Node

The workhorse of the workflow. Uses 7 tools to modify recipes to meet ALL constraints.
Handles both qualitative (diet, swaps) and quantitative (macros, calories) modifications.
"""


class ModificationAgent(AgentNode):
    """
    Fifth node in meal recommendation workflow.
    
    Uses LLM with 7 tools to modify recipe to meet ALL user constraints.
    
    Input: Selected recipe from SelectionAgent
    Output: ModifiedRecipe saved to task_context.nodes["ModificationAgent"]
    
    Tools:
    1. estimate_macros - Quick macro estimation
    2. scale_recipe - Scale all ingredients
    3. swap_ingredient - Substitute ingredients
    4. adjust_ingredient_amount - Fine-tune quantities
    5. parse_ingredient - Parse ingredient strings
    6. check_pantry - Check availability
    7. suggest_substitutions - Get substitution ideas
    """
    
    class OutputType(AgentNode.OutputType):
        """ModificationAgent outputs ModifiedRecipe + history"""
        model_output: ModifiedRecipe
        history: Any
    
    def __init__(self, task_context: TaskContext = None):
        super().__init__(task_context)
        self._recipe_state = {}  # Track current state during modifications
        self._pantry_items = []
        self._constraints = None
    
    def get_agent_config(self) -> AgentConfig:
        """
        Configure the agent for recipe modification with all 7 tools.
        
        Uses gpt-4o for complex reasoning with tool use.
        """
        return AgentConfig(
            model_provider=ModelProvider.OPENAI,
            model_name="gpt-4o",
            output_type=ModifiedRecipe,
            system_prompt="You are a recipe modification expert who adapts recipes to meet constraints.",
            name="ModificationAgent",
            tools=[
                self.estimate_macros,
                self.scale_recipe,
                self.swap_ingredient,
                self.adjust_ingredient_amount,
                self.parse_ingredient,
                self.check_pantry,
                self.suggest_substitutions,
            ],
            retries=2,
        )
    
    # Tool 1: Estimate Macros
    # TODO: Rewrite to use USDA API
    async def estimate_macros(self, ingredients: List[Dict[str, Any]]) -> Dict[str, float]:
        """
        Quick macro estimation using heuristics.
        
        Args:
            ingredients: List of ingredient dicts with name, quantity, unit
            
        Returns:
            Estimated macros: {calories, protein, carbs, fat}
        """
        logger.info(f"Estimating macros for {len(ingredients)} ingredients")
        
        # Simple heuristic-based estimation
        # In production, this would use ML model or database lookups
        total_calories = 0
        total_protein = 0
        total_carbs = 0
        total_fat = 0
        
        # Basic estimates (very rough)
        for ing in ingredients:
            name = ing.get("ingredient", "").lower()
            quantity = ing.get("quantity", 1.0)
            
            # Protein sources
            if any(word in name for word in ["chicken", "beef", "fish", "tofu"]):
                total_protein += 25 * quantity
                total_calories += 150 * quantity
                total_fat += 5 * quantity
            
            # Carb sources
            elif any(word in name for word in ["rice", "pasta", "bread", "potato"]):
                total_carbs += 40 * quantity
                total_calories += 180 * quantity
                total_protein += 4 * quantity
            
            # Fats
            elif any(word in name for word in ["oil", "butter", "cheese", "avocado"]):
                total_fat += 15 * quantity
                total_calories += 135 * quantity
            
            # Vegetables (low calorie)
            elif any(word in name for word in ["lettuce", "spinach", "broccoli", "tomato"]):
                total_calories += 25 * quantity
                total_carbs += 5 * quantity
                total_protein += 2 * quantity
        
        return {
            "calories": int(total_calories),
            "protein": int(total_protein),
            "carbs": int(total_carbs),
            "fat": int(total_fat),
        }
    
    # Tool 2: Scale Recipe
    async def scale_recipe(self, recipe_id: str, scale_factor: float) -> Dict[str, Any]:
        """
        Scale all ingredients proportionally.
        
        Args:
            recipe_id: ID of recipe to scale
            scale_factor: Factor to scale by (e.g., 0.5 for half, 2.0 for double)
            
        Returns:
            Updated ingredient list
        """
        logger.info(f"Scaling recipe {recipe_id} by {scale_factor}x")
        
        if recipe_id not in self._recipe_state:
            return {"error": "Recipe not found in state"}
        
        recipe = self._recipe_state[recipe_id]
        scaled_ingredients = []
        
        for ing in recipe["ingredients"]:
            scaled_ing = ing.copy()
            if "quantity" in scaled_ing:
                scaled_ing["quantity"] = scaled_ing["quantity"] * scale_factor
            scaled_ingredients.append(scaled_ing)
        
        recipe["ingredients"] = scaled_ingredients
        return {"success": True, "new_ingredient_count": len(scaled_ingredients)}
    
    # Tool 3: Swap Ingredient
    async def swap_ingredient(
        self, recipe_id: str, old_ingredient: str, new_ingredient: str, reason: str
    ) -> Dict[str, Any]:
        """
        Substitute one ingredient for another.
        
        Args:
            recipe_id: ID of recipe
            old_ingredient: Ingredient to replace
            new_ingredient: Replacement ingredient
            reason: Why this swap is being made
            
        Returns:
            Swap confirmation
        """
        logger.info(f"Swapping '{old_ingredient}' -> '{new_ingredient}' ({reason})")
        
        if recipe_id not in self._recipe_state:
            return {"error": "Recipe not found"}
        
        recipe = self._recipe_state[recipe_id]
        swapped = False
        
        for ing in recipe["ingredients"]:
            if old_ingredient.lower() in ing.get("ingredient", "").lower():
                ing["ingredient"] = new_ingredient
                swapped = True
                break
        
        if swapped:
            recipe["modifications"].append(f"Swapped {old_ingredient} for {new_ingredient}: {reason}")
        
        return {"success": swapped, "reason": reason}
    
    # Tool 4: Adjust Ingredient Amount
    async def adjust_ingredient_amount(
        self, recipe_id: str, ingredient: str, new_amount: str, reason: str
    ) -> Dict[str, Any]:
        """
        Change the amount of a specific ingredient.
        
        Args:
            recipe_id: ID of recipe
            ingredient: Ingredient to adjust
            new_amount: New amount (e.g., "2 cups", "150g")
            reason: Why this adjustment is needed
            
        Returns:
            Adjustment confirmation
        """
        logger.info(f"Adjusting {ingredient} to {new_amount} ({reason})")
        
        if recipe_id not in self._recipe_state:
            return {"error": "Recipe not found"}
        
        recipe = self._recipe_state[recipe_id]
        adjusted = False
        
        for ing in recipe["ingredients"]:
            if ingredient.lower() in ing.get("ingredient", "").lower():
                # Parse new amount (simplified)
                parts = new_amount.split()
                if len(parts) >= 2:
                    ing["quantity"] = float(parts[0])
                    ing["unit"] = " ".join(parts[1:])
                adjusted = True
                break
        
        if adjusted:
            recipe["modifications"].append(f"Adjusted {ingredient} to {new_amount}: {reason}")
        
        return {"success": adjusted, "reason": reason}
    
    # Tool 5: Parse Ingredient
    async def parse_ingredient(self, ingredient_str: str) -> Dict[str, Any]:
        """
        Parse ingredient string to structured format.
        
        Args:
            ingredient_str: Raw ingredient string (e.g., "2 cups chopped onion")
            
        Returns:
            Parsed ingredient with quantity, unit, name, modifier
        """
        logger.info(f"Parsing ingredient: '{ingredient_str}'")
        
        # Simple parsing (in production, use more sophisticated NLP)
        parts = ingredient_str.split()
        
        result = {
            "ingredient": "",
            "quantity": 1.0,
            "unit": "",
            "modifier": None,
        }
        
        # Try to extract quantity (first number)
        for i, part in enumerate(parts):
            try:
                # Handle fractions like "1/2"
                if "/" in part:
                    num, den = part.split("/")
                    result["quantity"] = float(num) / float(den)
                else:
                    result["quantity"] = float(part)
                # Rest is likely unit + ingredient
                remaining = parts[i+1:]
                if remaining:
                    # First word might be unit
                    possible_units = ["cup", "cups", "tbsp", "tsp", "oz", "lb", "g", "kg", "ml", "l"]
                    if remaining[0].lower() in possible_units:
                        result["unit"] = remaining[0]
                        result["ingredient"] = " ".join(remaining[1:])
                    else:
                        result["ingredient"] = " ".join(remaining)
                break
            except ValueError:
                continue
        
        # If no quantity found, treat whole string as ingredient
        if not result["ingredient"]:
            result["ingredient"] = ingredient_str
        
        return result
    
    # Tool 6: Check Pantry
    async def check_pantry(self, ingredient_names: List[str]) -> Dict[str, List[str]]:
        """
        Check which ingredients are available in user's pantry.
        
        Args:
            ingredient_names: List of ingredient names to check
            
        Returns:
            Dict with 'has' and 'missing' lists
        """
        logger.info(f"Checking pantry for {len(ingredient_names)} ingredients")
        
        pantry_names = set(item.lower() for item in self._pantry_items)
        
        has = []
        missing = []
        
        for ing in ingredient_names:
            ing_lower = ing.lower()
            # Check if any pantry item matches
            if any(pantry_item in ing_lower or ing_lower in pantry_item for pantry_item in pantry_names):
                has.append(ing)
            else:
                missing.append(ing)
        
        return {"has": has, "missing": missing}
    
    # Tool 7: Suggest Substitutions
    async def suggest_substitutions(
        self, ingredient: str, constraints: Dict[str, Any]
    ) -> List[Dict[str, Any]]:
        """
        Get valid substitution suggestions for an ingredient.
        
        Args:
            ingredient: Ingredient to substitute
            constraints: Diet/allergy constraints
            
        Returns:
            List of substitution options with ratios and macro impacts
        """
        logger.info(f"Finding substitutions for '{ingredient}' with constraints: {constraints}")
        
        # Common substitutions database (simplified)
        substitutions_db = {
            "butter": [
                {"substitute": "coconut oil", "ratio": "1:1", "macro_impact": "similar fat, no dairy"},
                {"substitute": "olive oil", "ratio": "3:4", "macro_impact": "healthier fats"},
            ],
            "chicken": [
                {"substitute": "tofu", "ratio": "1:1", "macro_impact": "lower protein, vegan"},
                {"substitute": "turkey", "ratio": "1:1", "macro_impact": "similar protein, leaner"},
            ],
            "milk": [
                {"substitute": "almond milk", "ratio": "1:1", "macro_impact": "lower calories, vegan"},
                {"substitute": "oat milk", "ratio": "1:1", "macro_impact": "similar texture, vegan"},
            ],
            "rice": [
                {"substitute": "cauliflower rice", "ratio": "1:1", "macro_impact": "much lower carbs"},
                {"substitute": "quinoa", "ratio": "1:1", "macro_impact": "higher protein"},
            ],
        }
        
        ing_lower = ingredient.lower()
        
        # Find matching substitutions
        suggestions = []
        for key, subs in substitutions_db.items():
            if key in ing_lower:
                # Filter by constraints
                diet = constraints.get("diet_type", "").lower()
                if diet == "vegan":
                    suggestions.extend([s for s in subs if "vegan" in s["macro_impact"]])
                else:
                    suggestions.extend(subs)
        
        if not suggestions:
            # Generic fallback
            suggestions = [
                {"substitute": f"similar ingredient to {ingredient}", "ratio": "1:1", "macro_impact": "adjust as needed"}
            ]
        
        return suggestions[:3]  # Return top 3
    
    async def process(self, task_context: TaskContext) -> TaskContext:
        """
        Modify recipe to meet all user constraints.
        
        Args:
            task_context: Contains selected recipe and constraints
            
        Returns:
            TaskContext with modified recipe saved
        """
        # Get selected recipe
        selected_recipe: Recipe = task_context.nodes.get("selected_recipe")
        if not selected_recipe:
            raise ValueError("No selected recipe found")
        
        # Get constraints
        normalize_output: NormalizeNode.OutputType = task_context.nodes.get("NormalizeNode")
        normalized = normalize_output.model_output
        request: MealRecommendationRequest = task_context.event
        
        # Store for tool access
        self._pantry_items = [item.name for item in request.pantry_items if item.confirmed]
        self._constraints = normalized
        
        # Initialize recipe state
        self._recipe_state[selected_recipe.id] = {
            "ingredients": [
                {"ingredient": ing, "quantity": 1.0, "unit": "serving"}
                for ing in selected_recipe.ingredients
            ],
            "directions": selected_recipe.directions,
            "modifications": [],
        }
        
        # Render modification prompt
        prompt = PromptManager.get_prompt(
            "modification",
            constraints=normalized.model_dump(),
            recipe=selected_recipe.model_dump(),
            pantry_items=self._pantry_items,
        )
        
        logger.info(f"Starting modification of recipe: {selected_recipe.title}")
        
        # Run the agent with tools
        result = await self.agent.run(
            user_prompt=f"Modify this recipe to meet constraints:\n\n{prompt}"
        )
        
        # Store output with message history
        history = to_jsonable_python(result.all_messages())
        output = self.OutputType(model_output=result.data, history=history)
        self.save_output(output)
        
        logger.info(f"Recipe modification complete. Changes: {len(result.data.modifications)}")
        
        return task_context

