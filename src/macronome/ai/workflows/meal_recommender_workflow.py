from macronome.ai.core.workflow import Workflow
from macronome.ai.core.schema import WorkflowSchema, NodeConfig
from macronome.ai.schemas.meal_recommender_constraints_schema import MealRecommendationRequest
from macronome.ai.workflows.meal_recommender_workflow_nodes.normalize_node import NormalizeNode
from macronome.ai.workflows.meal_recommender_workflow_nodes.planning_agent import PlanningAgent
from macronome.ai.workflows.meal_recommender_workflow_nodes.retrieval_node import RetrievalNode
from macronome.ai.workflows.meal_recommender_workflow_nodes.selection_agent import SelectionAgent
from macronome.ai.workflows.meal_recommender_workflow_nodes.nutrition_node import InitialNutritionNode
from macronome.ai.workflows.meal_recommender_workflow_nodes.modification_agent import ModificationAgent
from macronome.ai.workflows.meal_recommender_workflow_nodes.qc_router import QCRouter
from macronome.ai.workflows.meal_recommender_workflow_nodes.explanation_agent import ExplanationAgent
from macronome.ai.workflows.meal_recommender_workflow_nodes.failure_agent import FailureAgent

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
    5. Initial Nutrition (calculate baseline nutrition - optional context)
    6. Modification agent (iterative loop: modify → recalculate nutrition → check constraints, max 3 iterations)
       - Uses calculate_nutrition tool with USDA API (cached)
       - Outputs both ModifiedRecipe and final NutritionInfo
    7. QC Router (validate quality)
       → Success: Explanation agent (generate response)
       → Failure: Failure agent (explain issues and suggest constraint modifications)
    
    Features:
    - Semantic search with FAISS
    - Iterative modification agent with nutrition feedback loop
    - USDA API for accurate nutrition (with caching to minimize API calls)
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
                connections=[InitialNutritionNode],
                description="Pick recipe requiring least modification"
            ),
            
            # Node 5: Calculate baseline nutrition (optional context)
            NodeConfig(
                node=InitialNutritionNode,
                connections=[ModificationAgent],
                description="Calculate baseline nutrition for context"
            ),
            
            # Node 6: Modify recipe iteratively (with nutrition tool)
            NodeConfig(
                node=ModificationAgent,
                connections=[QCRouter],
                description="Iteratively adapt recipe to meet all constraints (max 3 iterations, outputs nutrition)"
            ),
            
            # Node 7: Quality control router
            NodeConfig(
                node=QCRouter,
                connections=[ExplanationAgent, FailureAgent],
                is_router=True,
                description="Validate quality, route to success or failure"
            ),
            
            # Node 8: Generate explanation (success terminal)
            NodeConfig(
                node=ExplanationAgent,
                connections=[],
                description="Generate user-friendly meal explanation (terminal)"
            ),
            
            # Node 9: Failure message (failure terminal)
            NodeConfig(
                node=FailureAgent,
                connections=[],
                description="Generate helpful error message with suggestions (terminal)"
            ),
        ],
    )
