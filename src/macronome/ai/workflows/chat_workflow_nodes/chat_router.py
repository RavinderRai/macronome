"""
Chat Router Node

Routes user chat messages to appropriate actions:
- ADD_CONSTRAINT: User wants to add/modify constraints
- START_RECOMMENDATION: User requests a meal recommendation
- GENERAL_CHAT: User has questions or general conversation
"""
from typing import Any
from pydantic_core import to_jsonable_python
from pydantic import BaseModel
from pydantic_ai import Agent

from macronome.ai.core.nodes.router import BaseRouter
from macronome.ai.core.task import TaskContext
from macronome.ai.prompts import PromptManager
from macronome.ai.schemas.chat_schema import ChatRequest, ChatRouterOutput, ChatAction
from macronome.ai.core.nodes.base import Node


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
    
    def route(self, task_context: TaskContext) -> Node:
        """
        Route to next node based on classified action.
        
        Args:
            task_context: Contains ChatRouter output
            
        Returns:
            Next node instance (lazy-loaded from task_context metadata)
        """
        # Get router output
        router_output: ChatRouter.OutputType = task_context.nodes.get("ChatRouter")
        if not router_output:
            raise ValueError("ChatRouter output not found")
        
        action = router_output.model_output.action
        
        # Get node classes from workflow (stored in task_context metadata by workflow)
        node_map = task_context.metadata.get("nodes", {})
        
        # Route based on action - return node instance
        if action == ChatAction.ADD_CONSTRAINT:
            next_node_class = node_map.get("ConstraintParser")
        else:
            # START_RECOMMENDATION or GENERAL_CHAT go straight to response
            next_node_class = node_map.get("ResponseGenerator")
        
        if not next_node_class:
            raise ValueError("Node class not found in workflow metadata")
        
        # Return node instance with task context
        return next_node_class(task_context)

