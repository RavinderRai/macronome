"""
Chat Router Node

Routes user chat messages to appropriate actions:
- ADD_CONSTRAINT: User wants to add/modify constraints
- START_RECOMMENDATION: User requests a meal recommendation
- GENERAL_CHAT: User has questions or general conversation
"""
import asyncio
import nest_asyncio
import logging
from typing import Any
from pydantic_core import to_jsonable_python
from pydantic import BaseModel
from pydantic_ai import Agent

from macronome.ai.core.nodes.router import BaseRouter
from macronome.ai.core.task import TaskContext
from macronome.ai.prompts import PromptManager
from macronome.ai.schemas.chat_schema import ChatRequest, ChatRouterOutput, ChatAction
from macronome.ai.core.nodes.base import Node

logger = logging.getLogger(__name__)


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
            output_type=ChatRouterOutput,
            system_prompt="You are a chat routing assistant that analyzes user messages to determine their intent.",
            retries=2,
        )
    
    async def process(self, task_context: TaskContext) -> TaskContext:
        """
        BaseRouter.process() - returns task_context unchanged.
        Actual processing happens in route().
        """
        return task_context
    
    def route(self, task_context: TaskContext) -> Node:
        """
        Classify user message intent using LLM and route to next node.
        
        Args:
            task_context: Contains ChatRequest
            
        Returns:
            Next node instance (lazy-loaded from task_context metadata)
        """
        # Set task_context so save_output() can access it
        self.task_context = task_context
        print(f"[ChatRouter] Task context: {self.task_context}")
        
        request: ChatRequest = task_context.event
        
        # Render the prompt with user message and chat history
        prompt = PromptManager.get_prompt(
            "chat_router",
            message=request.message,
            chat_history=request.chat_history,
        )
        
        # Run the async agent synchronously
        # Since we're in a sync function but need to call async code,
        # we'll use asyncio.run() with nest_asyncio to handle nested loops
        nest_asyncio.apply()
        
        result = asyncio.run(self.agent.run(user_prompt=prompt))
        
        # AgentRunResult has 'output' attribute, not 'data'
        # See pydantic_ai/run.py line 292: output: OutputDataT
        result_data = result.output
        
        # Get message history
        history = to_jsonable_python(result.all_messages())
        
        output = self.OutputType(model_output=result_data, history=history)
        self.save_output(output)
        
        action = result_data.action
        
        # Get node classes from workflow (stored in task_context metadata by workflow)
        # The workflow stores nodes as Dict[Type[Node], NodeConfig] in metadata["nodes"]
        # We need to extract the node classes and map them by name
        raw_nodes = task_context.metadata.get("nodes", {})
        
        # Build a name-to-class mapping from the workflow's node structure
        # raw_nodes keys are the node classes themselves
        node_map = {
            node_class.__name__: node_class
            for node_class in raw_nodes.keys()
        }
        
        print(f"[ChatRouter] Available nodes: {list(node_map.keys())}")  # Use print for immediate visibility
        
        # Route based on action - return node instance
        if action == ChatAction.ADD_CONSTRAINT:
            next_node_class = node_map.get("ConstraintParser")
            print("[ChatRouter] Routing to ConstraintParser")
        elif action == ChatAction.START_RECOMMENDATION:
            next_node_class = node_map.get("MealRecommendationTrigger")
            print("[ChatRouter] Routing to MealRecommendationTrigger")
        else:
            # GENERAL_CHAT goes straight to response
            next_node_class = node_map.get("ResponseGenerator")
            print("[ChatRouter] Routing to ResponseGenerator")
        
        if not next_node_class:
            available_nodes = list(node_map.keys())
            error_msg = (
                f"Node class not found in workflow metadata. "
                f"Action: {action}, Available nodes: {available_nodes}"
            )
            print(f"[ChatRouter] ERROR: {error_msg}")
            raise ValueError(error_msg)
        
        # Return node instance with task context
        next_node = next_node_class(task_context)
        print(f"[ChatRouter] Created next node instance: {type(next_node).__name__}")
        return next_node

