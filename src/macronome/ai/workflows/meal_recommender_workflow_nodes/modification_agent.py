import logging
from typing import List, Dict, Any, Tuple
from pydantic_core import to_jsonable_python

from macronome.ai.core.nodes.agent import AgentNode, AgentConfig, ModelProvider
from macronome.ai.core.task import TaskContext
from macronome.ai.prompts import PromptManager
from macronome.ai.schemas.meal_recommender_constraints_schema import (
    MealRecommendationRequest,
    NormalizedConstraints,
)
from macronome.ai.workflows.meal_recommender_workflow_nodes.normalize_node import NormalizeNode
from macronome.ai.workflows.meal_recommender_workflow_nodes.nutrition_calculator import NutritionCalculator
from macronome.ai.schemas.recipe_schema import Recipe, ParsedIngredient, NutritionInfo
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
        self._constraints: NormalizedConstraints = None
        self._nutrition_calculator = NutritionCalculator()
        self._current_nutrition: NutritionInfo = None
        self._max_iterations = 3
    
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
                self.calculate_nutrition,
                self.scale_recipe,
                self.swap_ingredient,
                self.adjust_ingredient_amount,
                self.parse_ingredient,
                self.check_pantry,
                self.suggest_substitutions,
            ],
            retries=2,
        )
    
    # Tool 1: Calculate Nutrition (using USDA API with caching)
    async def calculate_nutrition(self, ingredients: List[Dict[str, Any]]) -> Dict[str, Any]:
        """
        Calculate exact nutrition using USDA API (with caching).
        
        Only makes API calls for ingredients not already in cache.
        Use this after making ingredient swaps or adjustments to get updated nutrition.
        
        Args:
            ingredients: List of ingredient dicts with:
                - ingredient: str (name)
                - quantity: float
                - unit: str (cup, tbsp, g, etc.)
        
        Returns:
            Nutrition info: {calories, protein, carbs, fat}
        """
        logger.info(f"Calculating nutrition for {len(ingredients)} ingredients")
        
        # Convert to ParsedIngredient format
        parsed_ingredients = []
        for ing in ingredients:
            parsed_ingredients.append(ParsedIngredient(
                ingredient=ing.get("ingredient", ""),
                quantity=ing.get("quantity", 1.0),
                unit=ing.get("unit", "serving"),
                modifier=None,
            ))
        
        # Calculate using nutrition calculator (uses cache internally)
        nutrition = await self._nutrition_calculator.calculate(parsed_ingredients)
        
        # Update current nutrition state
        self._current_nutrition = nutrition
        
        return {
            "calories": nutrition.calories,
            "protein": nutrition.protein,
            "carbs": nutrition.carbs,
            "fat": nutrition.fat,
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
    
    def _check_constraints_met(self, nutrition: NutritionInfo, constraints: NormalizedConstraints) -> Tuple[bool, List[str]]:
        """
        Check if current nutrition meets all constraints.
        
        Returns:
            (is_met, issues_list)
        """
        issues = []
        
        # Check calorie range
        if constraints.calorie_range:
            target_min, target_max = constraints.calorie_range
            tolerance = 0.15
            min_acceptable = target_min * (1 - tolerance)
            max_acceptable = target_max * (1 + tolerance)
            
            if not (min_acceptable <= nutrition.calories <= max_acceptable):
                issues.append(f"Calories: {nutrition.calories} (target: {target_min}-{target_max})")
        
        # Check macro targets
        if constraints.macro_targets:
            targets = constraints.macro_targets
            tolerance = 0.15
            
            if targets.protein:
                diff_pct = abs(nutrition.protein - targets.protein) / max(targets.protein, 1)
                if diff_pct > tolerance:
                    issues.append(f"Protein: {nutrition.protein}g (target: {targets.protein}g, {diff_pct*100:.1f}% off)")
            
            if targets.carbs:
                diff_pct = abs(nutrition.carbs - targets.carbs) / max(targets.carbs, 1)
                if diff_pct > tolerance:
                    issues.append(f"Carbs: {nutrition.carbs}g (target: {targets.carbs}g, {diff_pct*100:.1f}% off)")
            
            if targets.fat:
                diff_pct = abs(nutrition.fat - targets.fat) / max(targets.fat, 1)
                if diff_pct > tolerance:
                    issues.append(f"Fat: {nutrition.fat}g (target: {targets.fat}g, {diff_pct*100:.1f}% off)")
        
        return len(issues) == 0, issues
    
    async def process(self, task_context: TaskContext) -> TaskContext:
        """
        Iteratively modify recipe to meet all user constraints.
        
        Loop structure:
        1. Calculate baseline nutrition
        2. For each iteration (max 3):
           a. Check if constraints already met → break
           b. Use LLM + tools to modify recipe
           c. Recalculate nutrition (uses cache, only new ingredients hit API)
           d. Check constraints again
        3. Return final modified recipe + nutrition
        
        Args:
            task_context: Contains selected recipe and constraints
            
        Returns:
            TaskContext with modified recipe and nutrition saved
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
        
        # Convert selected recipe ingredients to ParsedIngredient format
        # (This is a simplified conversion - in production, you'd parse the raw ingredient strings)
        initial_ingredients = []
        for ing_str in selected_recipe.ingredients:
            # Simple parsing - assume format like "2 cups flour" or just "flour"
            parts = ing_str.split(maxsplit=2)
            if len(parts) >= 2 and parts[0].replace('.', '').isdigit():
                try:
                    quantity = float(parts[0])
                    unit = parts[1] if len(parts) > 2 else "serving"
                    ingredient = parts[2] if len(parts) > 2 else parts[1]
                except ValueError:
                    quantity = 1.0
                    unit = "serving"
                    ingredient = ing_str
            else:
                quantity = 1.0
                unit = "serving"
                ingredient = ing_str
            
            initial_ingredients.append(ParsedIngredient(
                ingredient=ingredient,
                quantity=quantity,
                unit=unit,
                modifier=None,
            ))
        
        # Calculate baseline nutrition
        logger.info(f"Calculating baseline nutrition for: {selected_recipe.title}")
        baseline_nutrition = await self._nutrition_calculator.calculate(initial_ingredients)
        self._current_nutrition = baseline_nutrition
        
        # Check if baseline already meets constraints
        constraints_met, issues = self._check_constraints_met(baseline_nutrition, normalized)
        if constraints_met:
            logger.info("Baseline recipe already meets constraints, minimal modification needed")
        else:
            logger.info(f"Baseline nutrition: {baseline_nutrition.calories} cal, {baseline_nutrition.protein}g protein")
            logger.info(f"Constraints not met: {', '.join(issues)}")
        
        # Initialize recipe state for modification
        self._recipe_state[selected_recipe.id] = {
            "ingredients": [
                {
                    "ingredient": ing.ingredient,
                    "quantity": ing.quantity,
                    "unit": ing.unit
                }
                for ing in initial_ingredients
            ],
            "directions": selected_recipe.directions,
            "modifications": [],
        }
        
        # Iterative modification loop
        final_modified_recipe = None
        result = None
        iteration = 0
        for iteration in range(1, self._max_iterations + 1):
            logger.info(f"Modification iteration {iteration}/{self._max_iterations}")
            
            # Check if constraints are already met
            if constraints_met:
                logger.info("Constraints met, breaking early")
                break
            
            # Build prompt with current state
            current_ingredients_str = "\n".join([
                f"- {ing['quantity']} {ing['unit']} {ing['ingredient']}"
                for ing in self._recipe_state[selected_recipe.id]["ingredients"]
            ])
            
            nutrition_feedback = (
                f"Current nutrition: {self._current_nutrition.calories} cal, "
                f"{self._current_nutrition.protein}g protein, "
                f"{self._current_nutrition.carbs}g carbs, "
                f"{self._current_nutrition.fat}g fat"
            )
            
            if issues:
                issues_feedback = f"Issues to fix: {', '.join(issues)}"
            else:
                issues_feedback = "All constraints met!"
            
            prompt = PromptManager.get_prompt(
                "modification",
                constraints=normalized.model_dump(),
                recipe={
                    "title": selected_recipe.title,
                    "ingredients": self._recipe_state[selected_recipe.id]["ingredients"],
                    "directions": self._recipe_state[selected_recipe.id]["directions"],
                },
                pantry_items=self._pantry_items,
            )
            
            # Add iteration-specific context
            iteration_prompt = f"""Iteration {iteration}/{self._max_iterations}

{nutrition_feedback}
{issues_feedback}

Current ingredients:
{current_ingredients_str}

{prompt}

IMPORTANT: After making modifications, call calculate_nutrition to get updated values.
Then check if constraints are met. If not, continue modifying."""
            
            # Run the agent with tools
            result = await self.agent.run(user_prompt=iteration_prompt)
            
            # Get modified recipe from agent output
            modified_recipe: ModifiedRecipe = result.data
            final_modified_recipe = modified_recipe
            
            # Update recipe state from modified recipe
            self._recipe_state[selected_recipe.id]["ingredients"] = [
                {
                    "ingredient": ing.ingredient,
                    "quantity": ing.quantity,
                    "unit": ing.unit
                }
                for ing in modified_recipe.ingredients
            ]
            self._recipe_state[selected_recipe.id]["modifications"] = modified_recipe.modifications
            
            # Recalculate nutrition after modification (uses cache, only new ingredients hit API)
            logger.info("Recalculating nutrition after modification...")
            updated_nutrition = await self._nutrition_calculator.calculate(modified_recipe.ingredients)
            self._current_nutrition = updated_nutrition
            
            # Check constraints again
            constraints_met, issues = self._check_constraints_met(updated_nutrition, normalized)
            
            if constraints_met:
                logger.info(f"Constraints met after iteration {iteration}!")
                break
            else:
                logger.info(f"After iteration {iteration}: {updated_nutrition.calories} cal, {updated_nutrition.protein}g protein")
                logger.info(f"Still need to fix: {', '.join(issues)}")
        
        # Use final modified recipe (or create one if we broke early)
        if final_modified_recipe is None:
            # Create ModifiedRecipe from current state
            final_modified_recipe = ModifiedRecipe(
                recipe_id=selected_recipe.id,
                title=selected_recipe.title,
                ingredients=initial_ingredients,  # Use initial if no modifications
                directions=selected_recipe.directions,
                modifications=[],
                reasoning="Baseline recipe already met constraints",
            )
        
        # Store output with message history (from last iteration)
        history = to_jsonable_python(result.all_messages()) if result else []
        output = self.OutputType(model_output=final_modified_recipe, history=history)
        self.save_output(output)
        
        # Also save nutrition to task context (for QC Router and Explanation Agent)
        task_context.nodes["NutritionNode"] = self._current_nutrition
        
        logger.info(f"Recipe modification complete after {iteration} iteration(s). "
                   f"Final: {self._current_nutrition.calories} cal, {self._current_nutrition.protein}g protein")
        
        return task_context
    
    async def __aexit__(self, *args):
        """Clean up nutrition calculator"""
        await self._nutrition_calculator.close()

