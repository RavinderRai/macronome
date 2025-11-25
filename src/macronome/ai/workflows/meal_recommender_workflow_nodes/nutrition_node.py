import logging
from macronome.ai.core.nodes.base import Node
from macronome.ai.core.task import TaskContext
from macronome.ai.schemas.recipe_schema import NutritionInfo
from macronome.ai.utils.nutrition_calculator import NutritionCalculator
from macronome.ai.utils.ingredient_parser import parse_ingredient
from macronome.ai.schemas.recipe_schema import Recipe

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
        selected_recipe: Recipe = task_context.nodes.get("selected_recipe")
        if not selected_recipe:
            raise ValueError("Selected recipe not found in task context")
        
        logger.info(f"Calculating baseline nutrition for: {selected_recipe.title}")
        
        # Convert recipe ingredients to ParsedIngredient format
        ingredients = []
        for ing_str in selected_recipe.ingredients:
            parsed = parse_ingredient(ing_str)
            ingredients.append(parsed)
        
        # Calculate using shared nutrition calculator
        nutrition = await self._nutrition_calculator.calculate(ingredients)
        
        logger.info(f"Baseline nutrition: {nutrition.calories} cal, {nutrition.protein}g protein")
        
        # Save to task context
        self.save_output(nutrition)
        
        return task_context
    
    async def __aexit__(self, *args):
        """Clean up nutrition calculator"""
        await self._nutrition_calculator.close()

