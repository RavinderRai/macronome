import logging
from macronome.ai.core.nodes.base import Node
from macronome.ai.core.task import TaskContext
from macronome.ai.schemas.recipe_schema import NutritionInfo, ParsedIngredient
from macronome.ai.workflows.meal_recommender_workflow_nodes.nutrition_calculator import NutritionCalculator

logger = logging.getLogger(__name__)

"""
Initial Nutrition Node

Calculates baseline nutrition for the selected recipe (before modification).
This provides context to the ModificationAgent about the starting point.
"""


class InitialNutritionNode(Node):
    """
    Optional node that calculates baseline nutrition for selected recipe.
    
    This gives ModificationAgent context about the starting nutrition values.
    ModificationAgent will then iteratively modify and recalculate.
    
    Input: Selected recipe from SelectionAgent
    Output: NutritionInfo saved to task_context.nodes["InitialNutritionNode"]
    """
    
    def __init__(self, task_context: TaskContext = None):
        super().__init__(task_context)
        self._nutrition_calculator = NutritionCalculator()
    
    class OutputType(NutritionInfo):
        """InitialNutritionNode outputs NutritionInfo"""
        pass
    
    async def process(self, task_context: TaskContext) -> TaskContext:
        """
        Calculate baseline nutrition for selected recipe.
        
        Args:
            task_context: Contains selected recipe from SelectionAgent
            
        Returns:
            TaskContext with baseline nutrition info saved
        """
        # Get selected recipe
        from macronome.ai.schemas.recipe_schema import Recipe
        selected_recipe: Recipe = task_context.nodes.get("selected_recipe")
        if not selected_recipe:
            raise ValueError("Selected recipe not found in task context")
        
        logger.info(f"Calculating baseline nutrition for: {selected_recipe.title}")
        
        # Convert recipe ingredients to ParsedIngredient format
        # (Simplified parsing - in production, use proper ingredient parser)
        ingredients = []
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
            
            ingredients.append(ParsedIngredient(
                ingredient=ingredient,
                quantity=quantity,
                unit=unit,
                modifier=None,
            ))
        
        # Calculate using shared nutrition calculator
        nutrition = await self._nutrition_calculator.calculate(ingredients)
        
        logger.info(f"Baseline nutrition: {nutrition.calories} cal, {nutrition.protein}g protein")
        
        # Save to task context
        self.save_output(nutrition)
        
        return task_context
    
    async def __aexit__(self, *args):
        """Clean up nutrition calculator"""
        await self._nutrition_calculator.close()

