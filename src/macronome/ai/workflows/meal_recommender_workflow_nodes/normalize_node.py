from typing import Any
from pydantic_core import to_jsonable_python

from macronome.ai.core.nodes.agent import AgentNode, AgentConfig, ModelProvider
from macronome.ai.core.task import TaskContext
from macronome.ai.prompts import PromptManager
from macronome.ai.schemas.meal_recommender_constraints_schema import (
    MealRecommendationRequest,
    NormalizedConstraints,
)

"""
Normalize Node

An LLM-powered agent that parses and normalizes user constraints.
Extracts both explicit constraints (from structured input) and implicit constraints
(from chat history and natural language query).
"""


class NormalizeNode(AgentNode):
    """
    First node in meal recommendation workflow.
    
    Uses LLM to intelligently parse and normalize user input into standardized
    constraints for downstream processing.
    
    Input: MealRecommendationRequest (from task_context.event)
    Output: NormalizedConstraints (saved to task_context.nodes["NormalizeNode"])
    
    The LLM extracts:
    - Explicit constraints (calories, macros, diet, prep time)
    - Implicit constraints from chat (cuisine, meal type, spicy, etc.)
    - Semantic search query optimized for recipe retrieval
    """
    
    class OutputType(AgentNode.OutputType):
        """NormalizeNode outputs NormalizedConstraints + history"""
        model_output: NormalizedConstraints
        history: Any
    
    def get_agent_config(self) -> AgentConfig:
        """
        Configure the agent for constraint normalization.
        
        Uses gpt-4o-mini for fast, cheap parsing with structured output.
        """
        return AgentConfig(
            model_provider=ModelProvider.OPENAI,
            model_name="gpt-4o-mini",
            output_type=NormalizedConstraints,
            system_prompt="You are an expert at parsing meal recommendation constraints.",
            name="NormalizeAgent",
            retries=2,
        )
    
    async def process(self, task_context: TaskContext) -> TaskContext:
        """
        Parse and normalize user constraints using LLM.
        
        Args:
            task_context: Contains MealRecommendationRequest in event
            
        Returns:
            TaskContext with normalized constraints saved
        """
        request: MealRecommendationRequest = task_context.event
        
        # Render the prompt with all input data
        prompt = PromptManager.get_prompt(
            "normalize",
            user_query=request.user_query,
            constraints=request.constraints.model_dump(),
            pantry_items=[item.model_dump() for item in request.pantry_items],
            chat_history=request.chat_history,
        )
        
        # Run the agent to get structured output
        result = await self.agent.run(user_prompt=prompt)
        
        # Store output with message history
        history = to_jsonable_python(result.all_messages())
        output = self.OutputType(model_output=result.data, history=history)
        self.save_output(output)
        
        return task_context
