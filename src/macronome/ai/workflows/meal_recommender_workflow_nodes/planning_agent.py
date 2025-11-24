from typing import Any
from pydantic_core import to_jsonable_python

from macronome.ai.core.nodes.agent import AgentNode, AgentConfig, ModelProvider
from macronome.ai.core.task import TaskContext
from macronome.ai.prompts import PromptManager
from macronome.ai.schemas.meal_recommender_constraints_schema import MealRecommendationRequest
from macronome.ai.schemas.workflow_schemas import PlanningOutput

"""
Planning Agent Node

An LLM-powered agent that decides the search strategy for recipe retrieval.
Analyzes normalized constraints and pantry items to determine:
- Optimal semantic search query
- Hard filters to apply
- Pantry items to prioritize
- Overall search strategy
"""


class PlanningAgent(AgentNode):
    """
    Second node in meal recommendation workflow.
    
    Uses LLM to determine the optimal search strategy based on normalized constraints.
    
    Input: NormalizedConstraints from NormalizeNode
    Output: PlanningOutput saved to task_context.nodes["PlanningAgent"]
    
    Decides:
    - Search query optimization
    - Hard vs soft filters
    - Pantry prioritization strategy
    - Number of candidates to retrieve
    """
    
    class OutputType(AgentNode.OutputType):
        """PlanningAgent outputs PlanningOutput + history"""
        model_output: PlanningOutput
        history: Any
    
    def get_agent_config(self) -> AgentConfig:
        """
        Configure the agent for search strategy planning.
        
        Uses gpt-4o for fast reasoning with structured output.
        """
        return AgentConfig(
            model_provider=ModelProvider.OPENAI,
            model_name="gpt-4o",
            output_type=PlanningOutput,
            system_prompt="You are a meal planning strategist who determines optimal recipe search strategies.",
            name="PlanningAgent",
            retries=2,
        )
    
    async def process(self, task_context: TaskContext) -> TaskContext:
        """
        Generate search strategy from normalized constraints.
        
        Args:
            task_context: Contains NormalizedConstraints from NormalizeNode
            
        Returns:
            TaskContext with planning output saved
        """
        # Get normalized constraints from previous node
        from macronome.ai.workflows.meal_recommender_workflow_nodes.normalize_node import NormalizeNode
        normalize_output: NormalizeNode.OutputType = self.get_output(NormalizeNode)
        if normalize_output is None:
            normalize_output = task_context.nodes.get("NormalizeNode")
        
        normalized = normalize_output.model_output
        request: MealRecommendationRequest = task_context.event
        
        # Convert normalized constraints to dict, converting sets to lists for JSON serialization
        constraints_dict = normalized.model_dump()
        if 'excluded_ingredients' in constraints_dict and isinstance(constraints_dict['excluded_ingredients'], set):
            constraints_dict['excluded_ingredients'] = list(constraints_dict['excluded_ingredients'])
        
        # Render the prompt with normalized constraints and pantry
        prompt = PromptManager.get_prompt(
            "planning",
            normalized_constraints=constraints_dict,
            pantry_items=[item.model_dump() for item in request.pantry_items],
        )
        
        # Run the agent to get structured planning output
        result = await self.agent.run(user_prompt=prompt)
        
        # Store output with message history
        history = to_jsonable_python(result.all_messages())
        output = self.OutputType(model_output=result.output, history=history)
        self.save_output(output)
        
        return task_context

