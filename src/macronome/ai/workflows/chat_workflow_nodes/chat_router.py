"""
Chat Router Node

Routes user chat messages to appropriate actions:
- ADD_CONSTRAINT: User wants to add/modify constraints
- START_RECOMMENDATION: User requests a meal recommendation
- GENERAL_CHAT: User has questions or general conversation
"""
from typing import Any, Type
from pydantic_core import to_jsonable_python
from pydantic import BaseModel
from pydantic_ai import Agent

from macronome.ai.workflows.chat_workflow_nodes.constraint_parser import ConstraintParser
from macronome.ai.workflows.chat_workflow_nodes.response_generator import ResponseGenerator
from macronome.ai.core.nodes.base import Node
from macronome.ai.core.nodes.router import BaseRouter
from macronome.ai.core.task import TaskContext
from macronome.ai.prompts import PromptManager
from macronome.ai.schemas.chat_schema import ChatRequest, ChatRouterOutput, ChatAction


class ChatRouter(BaseRouter):
    """
    First node in chat workflow.
    
    Routes user messages to appropriate actions by analyzing intent using LLM.
    
    Input: ChatRequest from task_context.event
    Output: ChatRouterOutput with action, confidence, reasoning
    """
    
    class OutputType(BaseModel):
        """ChatRouter outputs ChatRouterOutput + history"""
        model_output: ChatRouterOutput
        history: Any
    
    def __init__(self, task_context: TaskContext = None):
        super().__init__(task_context)
        # Initialize LLM agent for intent classification
        self.agent = Agent(
            model="openai:gpt-4o",
            result_type=ChatRouterOutput,
            system_prompt="You are a chat routing assistant that analyzes user messages to determine their intent.",
            retries=2,
        )
    
    async def process(self, task_context: TaskContext) -> TaskContext:
        """
        Classify user message intent using LLM.
        
        Args:
            task_context: Contains ChatRequest
            
        Returns:
            TaskContext with routing output saved
        """
        request: ChatRequest = task_context.event
        
        # Render the prompt with user message and chat history
        prompt = PromptManager.get_prompt(
            "chat_router",
            message=request.message,
            chat_history=request.chat_history,
        )
        
        # Run the agent to get structured routing output
        result = await self.agent.run(user_prompt=prompt)
        
        # Store output with message history
        history = to_jsonable_python(result.all_messages())
        output = self.OutputType(model_output=result.data, history=history)
        self.save_output(output)
        
        return task_context
    
    def route(self, task_context: TaskContext) -> Type[Node]:
        """
        Route to next node based on classified action.
        
        Args:
            task_context: Contains ChatRouter output
            
        Returns:
            Next node class (ConstraintParser or ResponseGenerator)
        """
        # Get router output
        router_output: ChatRouter.OutputType = task_context.nodes.get("ChatRouter")
        if not router_output:
            raise ValueError("ChatRouter output not found")
        
        action = router_output.model_output.action
        
        # Route based on action
        if action == ChatAction.ADD_CONSTRAINT:
            return ConstraintParser
        else:
            # START_RECOMMENDATION or GENERAL_CHAT go straight to response
            return ResponseGenerator

