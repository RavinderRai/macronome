from macronome.ai.core.workflow import Workflow
from macronome.ai.core.schema import WorkflowSchema, NodeConfig
from macronome.ai.schemas.meal_recommender_constraints_schema import MealRecommendationRequest
from macronome.ai.workflows.meal_recommender_workflow_nodes import (
    NormalizeNode,
    PlanningAgent,
    RetrievalNode,
    SelectionAgent,
    ModificationAgent,
    NutritionNode,
    QCRouter,
    ExplanationAgent,
    RefinementAgent,
    FailureAgent,
)

"""
Meal Recommendation Workflow

Agentic workflow that recommends meals based on user constraints using RecipeNLG dataset.
Combines semantic search, LLM-powered modification, and nutrition calculation.
"""


class MealRecommendationWorkflow(Workflow):
    """
    Multi-node LLM workflow for intelligent meal recommendations.
    
    Flow:
    1. Normalize constraints (parse chat, standardize formats)
    2. Planning agent (decide search strategy)
    3. Retrieval (semantic search for top 3-5 candidates)
    4. Selection (pick best candidate to modify)
    5. Modification agent (adjust recipe to meet ALL constraints)
    6. Nutrition validation (calculate exact macros)
    7. QC Router (validate quality)
       → Success: Explanation agent (generate response)
       → Issues: Refinement agent (decide retry or ask user)
           → Retry: Back to Modification (max 2 retries)
           → Ask user: Failure agent (explain and suggest)
    
    Features:
    - Semantic search with FAISS
    - 7-tool modification agent for recipe adaptation
    - USDA API for accurate nutrition
    - Retry logic with smart refinement
    - Helpful failure messages
    """
    
    workflow_schema = WorkflowSchema(
        description="Meal recommendation workflow with constraint satisfaction",
        event_schema=MealRecommendationRequest,
        start=NormalizeNode,
        nodes=[
            # Node 1: Normalize constraints
            NodeConfig(
                node=NormalizeNode,
                connections=[PlanningAgent],
                description="Parse and normalize user constraints using LLM"
            ),
            
            # Node 2: Planning strategy
            NodeConfig(
                node=PlanningAgent,
                connections=[RetrievalNode],
                description="Decide search strategy based on constraints"
            ),
            
            # Node 3: Semantic retrieval
            NodeConfig(
                node=RetrievalNode,
                connections=[SelectionAgent],
                description="FAISS semantic search for top candidates"
            ),
            
            # Node 4: Select best candidate
            NodeConfig(
                node=SelectionAgent,
                connections=[ModificationAgent],
                description="Pick recipe requiring least modification"
            ),
            
            # Node 5: Modify recipe (with 7 tools)
            NodeConfig(
                node=ModificationAgent,
                connections=[NutritionNode],
                description="Adapt recipe to meet all constraints"
            ),
            
            # Node 6: Calculate nutrition
            NodeConfig(
                node=NutritionNode,
                connections=[QCRouter],
                description="Calculate exact macros with USDA API"
            ),
            
            # Node 7: Quality control router
            NodeConfig(
                node=QCRouter,
                connections=[ExplanationAgent, RefinementAgent],
                is_router=True,
                description="Validate quality, route to success or refinement"
            ),
            
            # Node 8: Generate explanation (success terminal)
            NodeConfig(
                node=ExplanationAgent,
                connections=[],
                description="Generate user-friendly meal explanation (terminal)"
            ),
            
            # Node 9: Refinement decision (retry or escalate)
            NodeConfig(
                node=RefinementAgent,
                connections=[ModificationAgent, FailureAgent],
                is_router=True,
                description="Decide retry with guidance or ask user"
            ),
            
            # Node 10: Failure message (failure terminal)
            NodeConfig(
                node=FailureAgent,
                connections=[],
                description="Generate helpful error message with suggestions (terminal)"
            ),
        ],
    )
