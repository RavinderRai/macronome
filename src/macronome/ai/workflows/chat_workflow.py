"""
Chat Workflow

Routes user chat messages to appropriate actions and generates responses.
Always ends with ResponseGenerator to provide user-facing output.
"""
from macronome.ai.core.workflow import Workflow
from macronome.ai.core.schema import WorkflowSchema, NodeConfig
from macronome.ai.schemas.chat_schema import ChatRequest
from macronome.ai.workflows.chat_workflow_nodes.chat_router import ChatRouter
from macronome.ai.workflows.chat_workflow_nodes.constraint_parser import ConstraintParser
from macronome.ai.workflows.chat_workflow_nodes.meal_recommendation_trigger import MealRecommendationTrigger
from macronome.ai.workflows.chat_workflow_nodes.response_generator import ResponseGenerator

# TODO: Need to be able to handle adding constraints and starting recommendations in the same message, a planning step might be needed in this chat workflow.

class ChatWorkflow(Workflow):
    """
    Chat workflow for meal recommendation app.
    
    Flow:
    1. ChatRouter (BaseRouter) - Classifies user intent and routes to next node
    2. ConstraintParser - If ADD_CONSTRAINT, parses and updates user preferences
    3. ResponseGenerator - Always runs, generates final response to user
    
    Features:
    - Intent detection with mixed intent support (action + question)
    - Constraint parsing and merging with existing preferences
    - Natural language responses for all scenarios
    - Handles general questions and help requests
    """
    
    workflow_schema = WorkflowSchema(
        description="Chat workflow with routing and response generation",
        event_schema=ChatRequest,
        start=ChatRouter,
        nodes=[
            # Node 1: Route user message (router node with LLM classification)
            NodeConfig(
                node=ChatRouter,
                connections=[MealRecommendationTrigger, ConstraintParser, ResponseGenerator],
                description="Classify user intent and route to appropriate action",
                is_router=True  # Enables automatic routing via node's route() method
            ),
            
            # Node 2: Trigger meal recommendation (conditional - only if START_RECOMMENDATION)
            NodeConfig(
                node=MealRecommendationTrigger,
                connections=[ResponseGenerator],
                description="Queue meal recommendation task and store task_id"
            ),
            
            # Node 3: Parse constraints (conditional - only if ADD_CONSTRAINT)
            NodeConfig(
                node=ConstraintParser,
                connections=[ResponseGenerator],
                description="Parse and update user constraints from message"
            ),
            
            # Node 4: Generate response (always runs - terminal node)
            NodeConfig(
                node=ResponseGenerator,
                connections=[],
                description="Generate final user-facing response"
            ),
        ]
    )

