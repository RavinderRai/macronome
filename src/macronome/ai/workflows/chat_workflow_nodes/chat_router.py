"""
Chat Router Node

Routes user chat messages to appropriate actions:
- ADD_CONSTRAINT: User wants to add/modify constraints
- START_RECOMMENDATION: User requests a meal recommendation
- GENERAL_CHAT: User has questions or general conversation
"""
from typing import Any
from pydantic_core import to_jsonable_python

from macronome.ai.core.nodes.agent import AgentNode, AgentConfig, ModelProvider
from macronome.ai.core.task import TaskContext
from macronome.ai.prompts import PromptManager
from macronome.ai.schemas.chat_schema import ChatRequest, ChatRouterOutput


class ChatRouter(AgentNode):
    """
    First node in chat workflow.
    
    Routes user messages to appropriate actions by analyzing intent.
    
    Input: ChatRequest from task_context.event
    Output: ChatRouterOutput with action, confidence, reasoning
    """
    
    class OutputType(AgentNode.OutputType):
        """ChatRouter outputs ChatRouterOutput + history"""
        model_output: ChatRouterOutput
        history: Any
    
    def get_agent_config(self) -> AgentConfig:
        """
        Configure the agent for chat routing.
        
        Uses gpt-4o-mini for fast intent classification with structured output.
        """
        return AgentConfig(
            model_provider=ModelProvider.OPENAI,
            model_name="gpt-4o",
            output_type=ChatRouterOutput,
            system_prompt="You are a chat routing assistant that analyzes user messages to determine their intent.",
            name="ChatRouter",
            retries=2,
        )
    
    async def process(self, task_context: TaskContext) -> TaskContext:
        """
        Route user message to appropriate action.
        
        Args:
            task_context: Contains ChatRequest
            
        Returns:
            TaskContext with routing output saved
        """
        request: ChatRequest = task_context.event
        
        # Render the prompt with user message
        prompt = PromptManager.get_prompt(
            "chat_router",
            message=request.message,
        )
        
        # Run the agent to get structured routing output
        result = await self.agent.run(user_prompt=prompt)
        
        # Store output with message history
        history = to_jsonable_python(result.all_messages())
        output = self.OutputType(model_output=result.data, history=history)
        self.save_output(output)
        
        return task_context

