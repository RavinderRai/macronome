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
from macronome.ai.workflows.meal_recommender_workflow_nodes.nutrition_node import NutritionNode
from macronome.ai.schemas.recipe_schema import NutritionInfo, EnrichedRecipe
from macronome.ai.schemas.workflow_schemas import ModifiedRecipe, MealRecommendation

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
        
        Uses gpt-4o-mini for creative, conversational output.
        """
        return AgentConfig(
            model_provider=ModelProvider.OPENAI,
            model_name="gpt-4o-mini",
            output_type=MealRecommendation,
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
        
        # Create EnrichedRecipe (combines modified recipe with nutrition)
        enriched_recipe = EnrichedRecipe(
            id=modified.recipe_id,
            title=modified.title,
            ingredients=modified.ingredients,
            directions=modified.directions,
            ner=[ing.ingredient for ing in modified.ingredients],
            parsed_ingredients=modified.ingredients,
            nutrition=nutrition,
        )
        
        # Render the prompt
        prompt = PromptManager.get_prompt(
            "explanation",
            user_query=request.user_query,
            normalized_constraints=normalized.model_dump(),
            recipe=modified.model_dump(),
            nutrition=nutrition.model_dump(),
            pantry_items=[item.model_dump() for item in request.pantry_items if item.confirmed],
        )
        
        # Run the agent
        result = await self.agent.run(user_prompt=prompt)
        
        # Get the explanation output
        explanation_data = result.data
        
        # Create final meal recommendation
        final_recommendation = MealRecommendation(
            recipe=enriched_recipe,
            why_it_fits=explanation_data.why_it_fits,
            ingredient_swaps=explanation_data.ingredient_swaps,
            pantry_utilization=explanation_data.pantry_utilization,
        )
        
        # Store output with message history
        history = to_jsonable_python(result.all_messages())
        output = self.OutputType(model_output=final_recommendation, history=history)
        self.save_output(output)
        
        # Mark workflow as complete (terminal node)
        task_context.should_stop = True
        
        return task_context

