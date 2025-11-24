from typing import Any
from pydantic_core import to_jsonable_python

from macronome.ai.core.nodes.agent import AgentNode, AgentConfig, ModelProvider
from macronome.ai.core.task import TaskContext
from macronome.ai.prompts import PromptManager
from macronome.ai.schemas.meal_recommender_constraints_schema import (
    MealRecommendationRequest,
)
from macronome.ai.workflows.meal_recommender_workflow_nodes.modification_agent import ModificationAgent
from macronome.ai.workflows.meal_recommender_workflow_nodes.normalize_node import NormalizeNode
from macronome.ai.schemas.recipe_schema import NutritionInfo, EnrichedRecipe, ParsedIngredient
from macronome.ai.schemas.workflow_schemas import MealRecommendation, ExplanationOutput

"""
Explanation Agent Node

An LLM-powered agent that generates a user-friendly explanation of the recommended meal.
Creates the final response with reasoning, swaps, and pantry utilization.
"""


class ExplanationAgent(AgentNode):
    """
    Eighth node in meal recommendation workflow (success path).
    
    Uses LLM to generate explanation for the recommended meal.
    
    Input: ModifiedRecipe and NutritionInfo from previous nodes
    Output: MealRecommendation (final output) - Terminal node
    
    Generates:
    - Why this meal fits the user's request
    - Ingredient swaps made and their reasons
    - Which pantry items are being used
    """
    
    class OutputType(AgentNode.OutputType):
        """ExplanationAgent outputs MealRecommendation + history"""
        model_output: MealRecommendation
        history: Any
    
    def get_agent_config(self) -> AgentConfig:
        """
        Configure the agent for generating meal explanation.
        
        Uses gpt-4o for creative, conversational output.
        """
        return AgentConfig(
            model_provider=ModelProvider.OPENAI,
            model_name="gpt-4o",
            output_type=ExplanationOutput,
            system_prompt="You are a friendly meal recommendation expert who explains food choices warmly.",
            name="ExplanationAgent",
            retries=2,
        )
    
    async def process(self, task_context: TaskContext) -> TaskContext:
        """
        Generate explanation for the recommended meal.
        
        Args:
            task_context: Contains modified recipe and nutrition info
            
        Returns:
            TaskContext with final meal recommendation
        """
        # Get all required data
        
        modification_output: ModificationAgent.OutputType = task_context.nodes.get("ModificationAgent")
        nutrition: NutritionInfo = task_context.nodes.get("NutritionNode")
        normalize_output: NormalizeNode.OutputType = task_context.nodes.get("NormalizeNode")
        request: MealRecommendationRequest = task_context.event
        
        if not all([modification_output, nutrition, normalize_output]):
            raise ValueError("Missing required data for explanation generation")
        
        modified = modification_output.model_output
        normalized = normalize_output.model_output
        
        # Convert set to list for JSON serialization
        normalized_dict = normalized.model_dump()
        if 'excluded_ingredients' in normalized_dict and isinstance(normalized_dict['excluded_ingredients'], set):
            normalized_dict['excluded_ingredients'] = list(normalized_dict['excluded_ingredients'])
        
        # Create EnrichedRecipe (combines modified recipe with nutrition)
        enriched_recipe = EnrichedRecipe(
            id=modified.recipe_id,
            title=modified.title,
            ingredients=[self._format_ingredient(ing) for ing in modified.ingredients],  # Convert to strings
            directions=modified.directions,
            ner=[ing.ingredient for ing in modified.ingredients],
            parsed_ingredients=modified.ingredients,
            nutrition=nutrition,
        )
        
        # Render the prompt
        prompt = PromptManager.get_prompt(
            "explanation",
            user_query=request.user_query,
            normalized_constraints=normalized_dict,
            recipe=modified.model_dump(),
            nutrition=nutrition.model_dump(),
            pantry_items=[item.model_dump() for item in request.pantry_items if item.confirmed],
        )
        
        # Run the agent
        result = await self.agent.run(user_prompt=prompt)
        
        # Get the explanation output
        explanation_data = result.output
        
        # Create final meal recommendation
        final_recommendation = MealRecommendation(
            recipe=enriched_recipe,
            why_it_fits=explanation_data.why_it_fits,
            ingredient_swaps=explanation_data.ingredient_swaps,
            pantry_utilization=explanation_data.pantry_utilization,
            recipe_instructions=explanation_data.recipe_instructions,
        )
        
        # Store output with message history
        history = to_jsonable_python(result.all_messages())
        output = self.OutputType(model_output=final_recommendation, history=history)
        self.save_output(output)
        
        # Mark workflow as complete (terminal node)
        task_context.should_stop = True
        
        return task_context

    # Convert ParsedIngredient objects to strings for EnrichedRecipe
    def _format_ingredient(self, ing: ParsedIngredient) -> str:
        """Convert ParsedIngredient to string format like '1 cup brown sugar'"""
        parts = []
        if ing.quantity and ing.quantity != 0:
            # Format quantity (remove .0 if whole number)
            qty_str = str(int(ing.quantity)) if ing.quantity == int(ing.quantity) else str(ing.quantity)
            parts.append(qty_str)
        if ing.unit:
            parts.append(ing.unit)
        if ing.ingredient:
            parts.append(ing.ingredient)
        if ing.modifier:
            parts.append(f"({ing.modifier})")
        return " ".join(parts)