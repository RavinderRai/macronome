from typing import Any
from pydantic_core import to_jsonable_python

from macronome.ai.core.nodes.agent import AgentNode, AgentConfig, ModelProvider
from macronome.ai.core.task import TaskContext
from macronome.ai.prompts import PromptManager
from macronome.ai.workflows.meal_recommender_workflow_nodes.normalize_node import NormalizeNode
from macronome.ai.schemas.meal_recommender_constraints_schema import (
    MealRecommendationRequest,
)
from macronome.ai.schemas.workflow_schemas import SelectionOutput

"""
Selection Agent Node

An LLM-powered agent that analyzes candidate recipes and selects the best one to modify.
Considers modification effort, pantry utilization, and constraint fit.
"""


class SelectionAgent(AgentNode):
    """
    Fourth node in meal recommendation workflow.
    
    Uses LLM to select the best recipe candidate from retrieval results.
    
    Input: List[Recipe] from RetrievalNode
    Output: SelectionOutput saved to task_context.nodes["SelectionAgent"]
    
    Selection criteria:
    - Minimal modification effort (diet, swaps)
    - Natural macro fit (calorie/protein proximity)
    - Pantry utilization
    - Recipe quality and clarity
    """
    
    class OutputType(AgentNode.OutputType):
        """SelectionAgent outputs SelectionOutput + history"""
        model_output: SelectionOutput
        history: Any
    
    def get_agent_config(self) -> AgentConfig:
        """
        Configure the agent for recipe selection.
        
        Uses gpt-4o for fast reasoning with structured output.
        """
        return AgentConfig(
            model_provider=ModelProvider.OPENAI,
            model_name="gpt-4o",
            output_type=SelectionOutput,
            system_prompt="You are a recipe selection expert who picks recipes requiring minimal modification.",
            name="SelectionAgent",
            retries=2,
        )
    
    async def process(self, task_context: TaskContext) -> TaskContext:
        """
        Select best recipe candidate for modification.
        
        Args:
            task_context: Contains candidate recipes from RetrievalNode
            
        Returns:
            TaskContext with selection output saved
        """
        # Get candidates from RetrievalNode
        candidates = task_context.nodes.get("RetrievalNode")
        if not candidates:
            raise ValueError("No candidate recipes found from RetrievalNode")
        
        # Get normalized constraints
        normalize_output: NormalizeNode.OutputType = task_context.nodes.get("NormalizeNode")
        normalized = normalize_output.model_output
        
        # Get pantry items from request
        request: MealRecommendationRequest = task_context.event
        
        # Convert normalized constraints to dict, converting sets to lists for JSON serialization
        normalized_dict = normalized.model_dump()
        if 'excluded_ingredients' in normalized_dict and isinstance(normalized_dict['excluded_ingredients'], set):
            normalized_dict['excluded_ingredients'] = list(normalized_dict['excluded_ingredients'])
        
        # Render the prompt
        prompt = PromptManager.get_prompt(
            "selection",
            normalized_constraints=normalized_dict,
            pantry_items=[item.model_dump() for item in request.pantry_items],
            candidates=[recipe.model_dump() for recipe in candidates],
        )
        
        # Run the agent with validation retry logic
        max_validation_retries = 3
        for attempt in range(max_validation_retries):
            # Run the agent
            result = await self.agent.run(user_prompt=prompt)
            
            # Validate that the selected recipe ID exists in candidates
            selected_recipe = next(
                (r for r in candidates if r.id == result.output.selected_recipe_id),
                None
            )
            
            if selected_recipe:
                # Success - valid recipe ID selected
                break
            else:
                # Invalid ID - prepare retry with more explicit guidance
                available_ids = [r.id for r in candidates]
                if attempt < max_validation_retries - 1:
                    # Log warning and retry with enhanced prompt
                    import logging
                    logger = logging.getLogger(__name__)
                    logger.warning(
                        f"SelectionAgent returned invalid recipe ID '{result.output.selected_recipe_id}' "
                        f"(attempt {attempt + 1}/{max_validation_retries}). Retrying with explicit ID list."
                    )
                    
                    # Add explicit ID reminder to the prompt
                    id_list = "\n".join([f"- {rid}" for rid in available_ids])
                    prompt = prompt + f"\n\n**RETRY REMINDER:** Your previous attempt used an invalid ID. You MUST select one of these exact IDs:\n{id_list}"
                else:
                    # Final attempt failed - raise error
                    raise ValueError(
                        f"Selected recipe ID '{result.output.selected_recipe_id}' not found in candidates after {max_validation_retries} attempts. "
                        f"Available IDs: {available_ids}"
                    )
        
        # Store output with message history
        history = to_jsonable_python(result.all_messages())
        output = self.OutputType(model_output=result.output, history=history)
        self.save_output(output)
        
        # Save the validated selected recipe
        task_context.nodes["selected_recipe"] = selected_recipe
        
        return task_context

