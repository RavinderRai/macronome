from typing import Type, Any
from pydantic_core import to_jsonable_python

from macronome.ai.core.nodes.base import Node
from macronome.ai.core.nodes.agent import AgentNode, AgentConfig, ModelProvider
from macronome.ai.core.task import TaskContext
from macronome.ai.prompts import PromptManager
from macronome.ai.workflows.meal_recommender_workflow_nodes.modification_agent import ModificationAgent
from macronome.ai.workflows.meal_recommender_workflow_nodes.normalize_node import NormalizeNode
from macronome.ai.schemas.recipe_schema import NutritionInfo
from macronome.ai.schemas.workflow_schemas import RefinementDecision

"""
Refinement Agent Node

An LLM-powered agent that decides whether QC issues can be fixed internally
or require user input. Routes back to ModificationAgent for retry or to FailureAgent.
"""

# TODO: Remove or decide if we want to use this, previous implementation caused an invalid cycle

class RefinementAgent(AgentNode):
    """
    Ninth node in meal recommendation workflow (failure path).
    
    Uses LLM to decide whether to retry modifications or ask user for guidance.
    
    Input: QC issues, modified recipe, nutrition info
    Output: RefinementDecision - Routes to ModificationAgent or FailureAgent
    
    Decision logic:
    - Retry if issues are fixable (< 2 retries)
    - Ask user if constraints conflict or too many retries
    """
    
    class OutputType(AgentNode.OutputType):
        """RefinementAgent outputs RefinementDecision + history"""
        model_output: RefinementDecision
        history: Any
    
    def get_agent_config(self) -> AgentConfig:
        """
        Configure the agent for refinement decision making.
        
        Uses gpt-4o-mini for quick decision making.
        """
        return AgentConfig(
            model_provider=ModelProvider.OPENAI,
            model_name="gpt-4o-mini",
            output_type=RefinementDecision,
            system_prompt="You are a problem-solving expert who decides retry vs escalation strategies.",
            name="RefinementAgent",
            retries=2,
        )
    
    def route(self, task_context: TaskContext) -> Type[Node]:
        """
        Route based on refinement decision.
        
        Args:
            task_context: Current task context
            
        Returns:
            ModificationAgent if retry
            FailureAgent if ask_user
        """
        refinement_output: RefinementAgent.OutputType = task_context.nodes.get("RefinementAgent")
        decision = refinement_output.model_output if refinement_output else None
        
        if decision and decision.action == "retry":
            from macronome.ai.workflows.meal_recommender_workflow_nodes.modification_agent import ModificationAgent
            return ModificationAgent
        else:
            from macronome.ai.workflows.meal_recommender_workflow_nodes.failure_agent import FailureAgent
            return FailureAgent
    
    async def process(self, task_context: TaskContext) -> TaskContext:
        """
        Decide whether to retry or ask user.
        
        Args:
            task_context: Contains QC issues and recipe state
            
        Returns:
            TaskContext with refinement decision
        """
        # Get all required data
        qc_issues = task_context.nodes.get("qc_issues", [])
        modification_output: ModificationAgent.OutputType = task_context.nodes.get("ModificationAgent")
        nutrition: NutritionInfo = task_context.nodes.get("NutritionNode")
        normalize_output: NormalizeNode.OutputType = task_context.nodes.get("NormalizeNode")
        
        # Track retry count
        retry_count = task_context.metadata.get("refinement_retry_count", 0)
        
        if not all([modification_output, nutrition, normalize_output]):
            raise ValueError("Missing required data for refinement decision")
        
        modified = modification_output.model_output
        normalized = normalize_output.model_output
        
        # Render the prompt
        prompt = PromptManager.get_prompt(
            "refinement",
            qc_issues=qc_issues,
            normalized_constraints=normalized.model_dump(),
            recipe=modified.model_dump(),
            nutrition=nutrition.model_dump(),
            retry_count=retry_count,
        )
        
        # Run the agent
        result = await self.agent.run(user_prompt=prompt)
        
        # Get decision
        decision: RefinementDecision = result.data
        
        # Update retry count if retrying
        if decision.action == "retry":
            task_context.metadata["refinement_retry_count"] = retry_count + 1
            
            # Store guidance for ModificationAgent
            if decision.guidance:
                task_context.metadata["modification_guidance"] = decision.guidance
        
        # Store output with message history
        history = to_jsonable_python(result.all_messages())
        output = self.OutputType(model_output=decision, history=history)
        self.save_output(output)
        
        return task_context

