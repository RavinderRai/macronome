"""
Response Generator Node

Always runs at the end of chat workflow to generate the final response.
Handles all three action types and mixed intents.
"""
from typing import Any, Optional
from pydantic_core import to_jsonable_python
from pydantic import BaseModel, Field

from macronome.ai.core.nodes.agent import AgentNode, AgentConfig, ModelProvider
from macronome.ai.core.task import TaskContext
from macronome.ai.prompts import PromptManager
from macronome.ai.schemas.chat_schema import ChatRequest, ChatAction
from macronome.ai.workflows.chat_workflow_nodes.chat_router import ChatRouter
from macronome.ai.workflows.chat_workflow_nodes.constraint_parser import ConstraintParser


class ChatResponseOutput(BaseModel):
    """Final chat response output"""
    response: str = Field(..., description="Final response text to user")


class ResponseGenerator(AgentNode):
    """
    Generates final chat response based on action taken.
    
    Always runs at the end to provide user-facing response.
    Handles:
    - ADD_CONSTRAINT: Confirms constraint addition
    - START_RECOMMENDATION: Confirms task queued, provides task_id
    - GENERAL_CHAT: Answers questions, provides help
    - Mixed intents: Handles both action + question
    
    Input: ChatRequest + router output + action outputs (if any)
    Output: ChatResponseOutput with final response text
    """
    
    class OutputType(AgentNode.OutputType):
        """ResponseGenerator outputs ChatResponseOutput + history"""
        model_output: ChatResponseOutput
        history: Any
    
    def get_agent_config(self) -> AgentConfig:
        """
        Configure the agent for response generation.
        
        Uses gpt-4o for natural, helpful responses.
        """
        return AgentConfig(
            model_provider=ModelProvider.OPENAI,
            model_name="gpt-4o",
            output_type=ChatResponseOutput,
            system_prompt="You are a friendly meal recommendation assistant that provides helpful, natural responses.",
            name="ResponseGenerator",
            retries=2,
        )
    
    async def process(self, task_context: TaskContext) -> TaskContext:
        """
        Generate final chat response.
        
        Args:
            task_context: Contains all previous node outputs
            
        Returns:
            TaskContext with final response saved
        """
        request: ChatRequest = task_context.event
        
        # Get router output
        router_output: Optional[ChatRouter.OutputType] = task_context.nodes.get("ChatRouter")
        if not router_output:
            raise ValueError("ChatRouter output not found")
        
        action = router_output.model_output.action
        has_question = router_output.model_output.has_question
        
        # Get action-specific outputs
        constraint_confirmation = None
        task_id = None
        
        if action == ChatAction.ADD_CONSTRAINT:
            # Get constraint parser output
            parser_output: Optional[ConstraintParser.OutputType] = task_context.nodes.get("ConstraintParser")
            if parser_output:
                constraint_confirmation = parser_output.model_output.confirmation_message
        
        elif action == ChatAction.START_RECOMMENDATION:
            # Get task_id from metadata (set by service layer)
            task_id = task_context.metadata.get("meal_recommendation_task_id")
        
        # Render the prompt with all context including chat history
        prompt = PromptManager.get_prompt(
            "response_generator",
            user_message=request.message,
            chat_history=request.chat_history,
            action=action.value,
            has_question=has_question,
            constraint_confirmation=constraint_confirmation,
            task_id=task_id,
        )
        
        # Run the agent to generate response
        result = await self.agent.run(user_prompt=prompt)
        
        # Get response text
        response_output: ChatResponseOutput = result.output
        
        # Store output with message history
        history = to_jsonable_python(result.all_messages())
        output = self.OutputType(model_output=response_output, history=history)
        self.save_output(output)
        
        # Mark workflow as complete (terminal node)
        task_context.should_stop = True
        
        return task_context

