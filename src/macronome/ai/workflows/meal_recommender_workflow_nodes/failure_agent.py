from typing import Any
from pydantic_core import to_jsonable_python

from macronome.ai.core.nodes.agent import AgentNode, AgentConfig, ModelProvider
from macronome.ai.core.task import TaskContext
from macronome.ai.prompts import PromptManager
from macronome.ai.schemas.meal_recommender_constraints_schema import (
    MealRecommendationRequest,
)
from macronome.ai.schemas.workflow_schemas import FailureResponse
from macronome.ai.workflows.meal_recommender_workflow_nodes.normalize_node import NormalizeNode

"""
Failure Agent Node

An LLM-powered agent that generates a helpful error message when
the meal recommendation workflow cannot find a suitable meal.
Explains the issue and provides actionable suggestions.
"""


class FailureAgent(AgentNode):
    """
    Tenth node in meal recommendation workflow (failure terminal).
    
    Uses LLM to generate helpful error message and suggestions.
    
    Input: QC issues, constraints
    Output: FailureResponse (final output) - Terminal node
    
    Generates:
    - Clear error message explaining the problem
    - Specific suggestions for modifying constraints
    - Identification of conflicting constraints
    """
    
    class OutputType(AgentNode.OutputType):
        """FailureAgent outputs FailureResponse + history"""
        model_output: FailureResponse
        history: Any
    
    def get_agent_config(self) -> AgentConfig:
        """
        Configure the agent for failure message generation.
        
        Uses gpt-4o-mini for empathetic, helpful communication.
        """
        return AgentConfig(
            model_provider=ModelProvider.OPENAI,
            model_name="gpt-4o-mini",
            output_type=FailureResponse,
            system_prompt="You are a helpful assistant who explains problems empathetically and offers solutions.",
            name="FailureAgent",
            retries=2,
        )
    
    async def process(self, task_context: TaskContext) -> TaskContext:
        """
        Generate helpful failure message and suggestions.
        
        Args:
            task_context: Contains constraints and issues
            
        Returns:
            TaskContext with failure response
        """
        # Get all relevant data
        normalize_output: NormalizeNode.OutputType = task_context.nodes.get("NormalizeNode")
        request: MealRecommendationRequest = task_context.event
        qc_issues = task_context.nodes.get("qc_issues", [])
        
        if not normalize_output:
            raise ValueError("NormalizedConstraints not found in task context")
        
        normalized = normalize_output.model_output
        
        # Convert normalized constraints to dict, converting sets to lists for JSON serialization
        constraints_dict = normalized.model_dump()
        if 'excluded_ingredients' in constraints_dict and isinstance(constraints_dict['excluded_ingredients'], set):
            constraints_dict['excluded_ingredients'] = list(constraints_dict['excluded_ingredients'])
        
        # Render the prompt
        prompt = PromptManager.get_prompt(
            "failure",
            user_query=request.user_query,
            normalized_constraints=constraints_dict,
            qc_issues=qc_issues,
        )
        
        # Run the agent
        result = await self.agent.run(user_prompt=prompt)
        
        # Get failure response
        failure_response: FailureResponse = result.output
        
        # Store output with message history
        history = to_jsonable_python(result.all_messages())
        output = self.OutputType(model_output=failure_response, history=history)
        self.save_output(output)
        
        # Mark workflow as complete (terminal node)
        task_context.should_stop = True
        
        return task_context

