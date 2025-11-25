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
from macronome.ai.utils.nutrition_calculator import NutritionCalculator
from macronome.ai.utils.ingredient_parser import parse_ingredient
from macronome.ai.schemas.recipe_schema import Recipe, ParsedIngredient, NutritionInfo
from macronome.ai.schemas.workflow_schemas import ModifiedRecipe

logger = logging.getLogger(__name__)

"""
Modification Agent Node

Agent with only ONE tool (calculate_nutrition).
LLM does all recipe modification directly in output, then we verify with nutrition calculation.
"""

MAX_ITERATIONS = 5

class ModificationAgent(AgentNode):
    """
    Fifth node in meal recommendation workflow.
    
    Simplified agent that outputs complete modified recipes directly.
    Uses only calculate_nutrition tool to verify results.
    
    Input: Selected recipe from SelectionAgent
    Output: ModifiedRecipe saved to task_context.nodes["ModificationAgent"]
    
    Tool:
    - calculate_nutrition: Verify nutrition meets constraints (USDA API)
    """
    
    class OutputType(AgentNode.OutputType):
        """ModificationAgent outputs ModifiedRecipe + history"""
        model_output: ModifiedRecipe
        history: Any
    
    def __init__(self, task_context: TaskContext = None):
        super().__init__(task_context)
        self._pantry_items = []
        self._constraints: NormalizedConstraints = None
        self._nutrition_calculator = NutritionCalculator()
        self._current_nutrition: NutritionInfo = None
        self._max_iterations = MAX_ITERATIONS
    
    def get_agent_config(self) -> AgentConfig:
        """
        Configure the agent with ONLY calculate_nutrition tool.
        
        Uses gpt-4o for complex reasoning and structured output.
        """
        return AgentConfig(
            model_provider=ModelProvider.OPENAI,
            model_name="gpt-4o",
            output_type=ModifiedRecipe,
            system_prompt="You are a recipe modification expert. Modify recipes to meet user constraints.",
            name="ModificationAgent",
            tools=[self.calculate_nutrition],  # ONLY ONE TOOL
            retries=2,
        )
    
    # Tool 1: Calculate Nutrition (using USDA API with caching)
    async def calculate_nutrition(self, ingredients: List[Dict[str, Any]]) -> Dict[str, Any]:
        """
        Calculate exact nutrition using USDA API (with caching).
        
        Call this AFTER you've output your modified recipe to verify nutrition.
        Only makes API calls for ingredients not already in cache.
        
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
    
    def _check_constraints_met(self, nutrition: NutritionInfo, constraints: NormalizedConstraints) -> Tuple[bool, List[str]]:
        """Check if current nutrition meets all constraints."""
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
    
    def _format_ingredients_for_prompt(self, ingredients: List[ParsedIngredient]) -> str:
        """Format ingredients list for prompt display."""
        return "\n".join([
            f"- {ing.quantity} {ing.unit} {ing.ingredient}"
            for ing in ingredients
        ])
    
    def _build_specific_suggestions(self, nutrition: NutritionInfo, constraints: NormalizedConstraints) -> str:
        """
        Build specific suggestions for what to adjust based on gaps.
        Handles flexible constraints - user may have only calories, only macros, or any combination.
        """
        suggestions = []
        
        # Check calorie range if specified
        if constraints.calorie_range:
            target_min, target_max = constraints.calorie_range
            tolerance = 0.15
            min_acceptable = target_min * (1 - tolerance)
            max_acceptable = target_max * (1 + tolerance)
            
            if nutrition.calories < min_acceptable:
                diff = target_min - nutrition.calories
                scale_factor = target_min / nutrition.calories if nutrition.calories > 0 else 1.2
                suggestions.append(f"• Add ~{diff:.0f} calories (e.g., increase portion sizes, add healthy fats)")
                suggestions.append(f"  → SCALING: Multiply all ingredients by {scale_factor:.2f}x to reach target")
            elif nutrition.calories > max_acceptable:
                diff = nutrition.calories - target_max
                target_avg = (target_min + target_max) / 2
                scale_factor = target_avg / nutrition.calories if nutrition.calories > 0 else 0.7
                suggestions.append(f"• Reduce ~{diff:.0f} calories (e.g., scale down portions, reduce high-calorie ingredients)")
                suggestions.append(f"  → SCALING: Multiply all ingredients by {scale_factor:.2f}x to reach target (reduce by {100*(1-scale_factor):.0f}%)")
        
        # Check macro targets if specified
        if constraints.macro_targets:
            targets = constraints.macro_targets
            
            # Protein (if target exists)
            if targets.protein is not None:
                if nutrition.protein < targets.protein * 0.85:
                    diff = targets.protein - nutrition.protein
                    suggestions.append(f"• Add {diff:.0f}g more protein (e.g., increase chicken/fish, add beans/tofu)")
                elif nutrition.protein > targets.protein * 1.15:
                    diff = nutrition.protein - targets.protein
                    scale_factor = targets.protein / nutrition.protein if nutrition.protein > 0 else 0.8
                    suggestions.append(f"• Reduce protein by {diff:.0f}g (e.g., decrease meat portions)")
                    suggestions.append(f"  → SCALING: Reduce protein sources by {100*(1-scale_factor):.0f}% (multiply by {scale_factor:.2f}x)")
            
            # Carbs (if target exists)
            if targets.carbs is not None:
                if nutrition.carbs < targets.carbs * 0.85:
                    diff = targets.carbs - nutrition.carbs
                    suggestions.append(f"• Add {diff:.0f}g more carbs (e.g., add rice, pasta, or bread)")
                elif nutrition.carbs > targets.carbs * 1.15:
                    diff = nutrition.carbs - targets.carbs
                    scale_factor = targets.carbs / nutrition.carbs if nutrition.carbs > 0 else 0.7
                    suggestions.append(f"• Reduce carbs by {diff:.0f}g (e.g., use cauliflower rice, reduce pasta/rice)")
                    suggestions.append(f"  → SCALING: Reduce carb sources by {100*(1-scale_factor):.0f}% (multiply by {scale_factor:.2f}x)")
            
            # Fat (if target exists)
            if targets.fat is not None:
                if nutrition.fat < targets.fat * 0.85:
                    diff = targets.fat - nutrition.fat
                    suggestions.append(f"• Add {diff:.0f}g more fat (e.g., increase olive oil, add avocado/nuts)")
                elif nutrition.fat > targets.fat * 1.15:
                    diff = nutrition.fat - targets.fat
                    scale_factor = targets.fat / nutrition.fat if nutrition.fat > 0 else 0.6
                    suggestions.append(f"• Reduce fat by {diff:.0f}g (e.g., decrease oil, remove cheese)")
                    suggestions.append(f"  → SCALING: Reduce fat sources by {100*(1-scale_factor):.0f}% (multiply by {scale_factor:.2f}x)")
        
        # Return suggestions or a generic message
        if suggestions:
            return "\n".join(suggestions)
        else:
            # If no specific targets or all are close, provide generic guidance
            if not constraints.calorie_range and not constraints.macro_targets:
                return "• No specific calorie or macro targets - focus on maintaining recipe quality"
            else:
                return "• All specified targets are close to goals"
    
    async def process(self, task_context: TaskContext) -> TaskContext:
        """
        Iterative modification:
        1. Calculate baseline nutrition
        2. For each iteration:
           a. Show LLM: recipe + nutrition + constraints + pantry items
           b. LLM outputs complete ModifiedRecipe directly
           c. Call calculate_nutrition ONCE to verify
           d. Check constraints → repeat if needed
        """
        # Get selected recipe
        selected_recipe: Recipe = task_context.nodes.get("selected_recipe")
        if not selected_recipe:
            raise ValueError("No selected recipe found")
        
        # Get constraints
        normalize_output: NormalizeNode.OutputType = task_context.nodes.get("NormalizeNode")
        normalized = normalize_output.model_output
        request: MealRecommendationRequest = task_context.event
        
        # Store pantry items and constraints
        self._pantry_items = [item.name for item in request.pantry_items if item.confirmed]
        self._constraints = normalized
        
        # Convert selected recipe ingredients to ParsedIngredient format
        initial_ingredients = []
        for ing_str in selected_recipe.ingredients:
            parsed = parse_ingredient(ing_str)
            initial_ingredients.append(parsed)
        
        # Calculate baseline nutrition
        logger.info(f"Calculating baseline nutrition for: {selected_recipe.title}")
        baseline_nutrition = await self._nutrition_calculator.calculate(initial_ingredients)
        self._current_nutrition = baseline_nutrition
        
        # Check if baseline already meets constraints
        constraints_met, issues = self._check_constraints_met(baseline_nutrition, normalized)
        if constraints_met:
            logger.info("Baseline recipe already meets constraints")
        else:
            logger.info(f"Baseline nutrition: {baseline_nutrition.calories} cal, {baseline_nutrition.protein}g protein")
            logger.info(f"Constraints not met: {', '.join(issues)}")
        
        # Start with initial recipe
        current_ingredients = initial_ingredients
        final_modified_recipe = None
        result = None
        
        # Iterative modification loop
        for iteration in range(1, self._max_iterations + 1):
            logger.info(f"Modification iteration {iteration}/{self._max_iterations}")
            
            # Check if constraints are already met
            if constraints_met:
                logger.info("Constraints met, breaking early")
                # Create ModifiedRecipe from current state
                final_modified_recipe = ModifiedRecipe(
                    recipe_id=selected_recipe.id,
                    title=selected_recipe.title,
                    ingredients=current_ingredients,
                    directions=selected_recipe.directions,
                    modifications=[] if iteration == 1 else ["Recipe already met constraints"],
                    reasoning="Recipe meets all constraints" if iteration == 1 else "Constraints met after modifications",
                )
                break
            
            # Build comprehensive prompt with ALL context
            current_ingredients_str = self._format_ingredients_for_prompt(current_ingredients)
            
            nutrition_feedback = (
                f"{self._current_nutrition.calories} cal, "
                f"{self._current_nutrition.protein}g protein, "
                f"{self._current_nutrition.carbs}g carbs, "
                f"{self._current_nutrition.fat}g fat"
            )
            
            issues_feedback = f"Issues to fix:\n{chr(10).join(f'• {issue}' for issue in issues)}" if issues else "✓ All constraints met!"
            
            # Build constraints summary
            constraints_summary = []
            if normalized.calorie_range:
                constraints_summary.append(f"Calories: {normalized.calorie_range[0]}-{normalized.calorie_range[1]}")
            if normalized.macro_targets:
                if normalized.macro_targets.protein:
                    constraints_summary.append(f"Protein: {normalized.macro_targets.protein}g")
                if normalized.macro_targets.carbs:
                    constraints_summary.append(f"Carbs: {normalized.macro_targets.carbs}g")
                if normalized.macro_targets.fat:
                    constraints_summary.append(f"Fat: {normalized.macro_targets.fat}g")
            if normalized.diet_type:
                constraints_summary.append(f"Diet: {normalized.diet_type}")
            if normalized.excluded_ingredients:
                constraints_summary.append(f"Exclude: {', '.join(normalized.excluded_ingredients)}")
            
            # Get specific suggestions for this iteration
            specific_suggestions = self._build_specific_suggestions(self._current_nutrition, normalized) if iteration > 1 else ""
            
            # Truncate directions if too long
            directions = selected_recipe.directions[:500] + ("..." if len(selected_recipe.directions) > 500 else "")
            
            # Build excluded ingredients string
            excluded_ingredients_str = ', '.join(normalized.excluded_ingredients) if normalized.excluded_ingredients else "none"
            
            # Load prompt from template
            prompt = PromptManager.get_prompt(
                "modification",
                recipe_title=selected_recipe.title,
                current_ingredients_str=current_ingredients_str,
                directions=directions,
                nutrition_feedback=nutrition_feedback,
                constraints_summary=constraints_summary,
                pantry_items=self._pantry_items,
                issues_feedback=issues_feedback,
                specific_suggestions=specific_suggestions,
                iteration=iteration,
                max_iterations=self._max_iterations,
                diet_type=normalized.diet_type or "none",
                excluded_ingredients_str=excluded_ingredients_str,
            )
            
            # Run the agent (LLM outputs ModifiedRecipe directly)
            result = await self.agent.run(user_prompt=prompt)
            
            # Get modified recipe from agent output
            modified_recipe: ModifiedRecipe = result.output
            final_modified_recipe = modified_recipe
            current_ingredients = modified_recipe.ingredients
            
            # Verify nutrition matches (automatically called by agent via calculate_nutrition tool if needed)
            # But we'll call it explicitly to ensure we have the final values
            logger.info("Verifying nutrition after modification...")
            updated_nutrition = await self._nutrition_calculator.calculate(modified_recipe.ingredients)
            self._current_nutrition = updated_nutrition
            
            # Check constraints again
            constraints_met, issues = self._check_constraints_met(updated_nutrition, normalized)
            
            if constraints_met:
                logger.info(f"✓ Constraints met after iteration {iteration}!")
                break
            else:
                logger.info(f"After iteration {iteration}: {updated_nutrition.calories} cal, {updated_nutrition.protein}g protein")
                logger.info(f"Still need to fix: {', '.join(issues)}")
        
        # Use final modified recipe (or create one if max iterations reached)
        if final_modified_recipe is None:
            final_modified_recipe = ModifiedRecipe(
                recipe_id=selected_recipe.id,
                title=selected_recipe.title,
                ingredients=current_ingredients,
                directions=selected_recipe.directions,
                modifications=["Max iterations reached, using best attempt"],
                reasoning="Unable to meet all constraints within iteration limit",
            )
        
        # Store output
        history = to_jsonable_python(result.all_messages()) if result else []
        output = self.OutputType(model_output=final_modified_recipe, history=history)
        self.save_output(output)
        
        # Also save nutrition to task context
        task_context.nodes["NutritionNode"] = self._current_nutrition
        
        logger.info(f"Recipe modification complete after {iteration} iteration(s). "
                   f"Final: {self._current_nutrition.calories} cal, {self._current_nutrition.protein}g protein")
        
        return task_context
    
    async def __aexit__(self, *args):
        """Clean up nutrition calculator"""
        await self._nutrition_calculator.close()

