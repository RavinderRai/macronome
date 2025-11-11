<!-- 17a28e7c-1c7b-477f-9898-f0ecde17185b 9e4048ef-0dea-449a-a5a6-8d6f6d8d7a66 -->
# Meal Recommendation Pipeline

## Overview

Build a multi-node LLM workflow that recommends 1 meal based on user constraints (calories, macros, diet, allergies, prep time, pantry items) using RecipeNLG dataset with semantic search and on-demand nutrition calculation.

---

## Step 0: Data Ingestion & Setup

### Download RecipeNLG Dataset

- Source: HuggingFace `mbien/recipe_nlg` (~2M recipes, 2GB)
- Columns: `title`, `ingredients`, `directions`, `link`, `source`, `NER`
- Store as Parquet in `data/recipes/recipe_nlg.parquet`

### Generate Embeddings

- Create embedding text: `title + " " + " ".join(ingredients) + " " + directions[:200]`
- Use `sentence-transformers/all-MiniLM-L6-v2` (384-dim, fast)
- Store embeddings with FAISS index
- Save to `data/recipes/recipe_embeddings.faiss` + metadata JSON

### Implementation

Create ingestion script: `scripts/ingest_recipe_data.py`

- Downloads dataset
- Generates embeddings in batches (to avoid memory issues)
- Builds FAISS index
- Saves index + recipe metadata

---

## File Structure

```
src/macronome/ai/meal_recommender/
├── __init__.py
├── config.py                    # Config (embedding model, FAISS paths)
├── schemas.py                   # Pydantic models for constraints, recipes, responses
├── workflow.py                  # Main MealRecommendationWorkflow class
├── pipeline/
│   ├── __init__.py
│   ├── normalize_node.py        # Node 1: Normalize constraints
│   ├── planning_agent.py        # Node 2: Planning agent
│   ├── retrieval_node.py        # Node 3: Execute plan (semantic search)
│   ├── nutrition_node.py        # Node 4: Parse ingredients + calculate nutrition
│   ├── qc_router.py             # Node 5: Quality control router
│   ├── explanation_node.py      # Node 6: Generate meal explanation
│   ├── relax_agent.py           # Node 7: Relax constraints agent
│   └── failure_node.py          # Node 8: Explain constraint issue
├── utils/
│   ├── __init__.py
│   ├── recipe_search.py         # FAISS search, keyword filtering
│   ├── ingredient_parser.py     # LLM-based ingredient parsing
│   ├── nutrition_calculator.py  # USDA API integration + macro calculation
│   └── constraint_parser.py     # Parse custom constraints from chat
└── tools/
    ├── __init__.py
    └── agent_tools.py           # Tool functions for planning agent
```

---

## Constraint Schema

### Input Constraints (from frontend + chat)

```python
# schemas.py

class MacroConstraints(BaseModel):
    """Numeric macro targets"""
    carbs: Optional[int] = None      # grams
    protein: Optional[int] = None    # grams
    fat: Optional[int] = None        # grams

class FilterConstraints(BaseModel):
    """User-specified constraints"""
    calories: Optional[int] = None              # Target (becomes ±50 range)
    macros: Optional[MacroConstraints] = None
    diet: Optional[str] = None                  # e.g., "vegan", "keto"
    excluded_ingredients: List[str] = []        # Allergies/dislikes
    prep_time: Optional[str] = None             # 'quick' | 'medium' | 'long'

class PantryItem(BaseModel):
    """Pantry context (not a hard constraint)"""
    name: str
    category: Optional[str] = None
    confirmed: bool = True

class MealRecommendationRequest(BaseModel):
    """Full request to workflow"""
    user_query: str                             # Free text: "something quick and spicy"
    constraints: FilterConstraints
    pantry_items: List[PantryItem] = []
    chat_history: List[Dict[str, str]] = []     # For context
```

### Normalized Constraints (internal)

```python
class NormalizedConstraints(BaseModel):
    """Standardized constraints after parsing"""
    calorie_range: Optional[Tuple[int, int]] = None  # e.g., (650, 750)
    macro_targets: Optional[MacroConstraints] = None
    diet_type: Optional[str] = None
    excluded_ingredients: Set[str] = set()
    prep_time_max: Optional[int] = None              # minutes (quick=30, medium=60, long=None)
    custom_constraints: Dict[str, Any] = {}          # Parsed from chat (cuisine, meal_type, etc.)
    semantic_query: str = ""                         # Processed search query
```

### Recipe Schema

```python
class Recipe(BaseModel):
    """Recipe from RecipeNLG"""
    id: str
    title: str
    ingredients: List[str]
    directions: str
    ner: List[str]                               # Named entities (ingredients)
    source: Optional[str] = None
    link: Optional[str] = None

class ParsedIngredient(BaseModel):
    """Structured ingredient after LLM parsing"""
    ingredient: str                              # "brown sugar"
    quantity: float                              # 1.0
    unit: str                                    # "cup"
    modifier: Optional[str] = None               # "firmly packed"

class NutritionInfo(BaseModel):
    """Calculated nutrition"""
    calories: int
    protein: int                                 # grams
    carbs: int
    fat: int

class EnrichedRecipe(Recipe):
    """Recipe with calculated nutrition"""
    parsed_ingredients: List[ParsedIngredient]
    nutrition: NutritionInfo
    prep_time_estimate: Optional[int] = None     # minutes
    pantry_match_score: float = 0.0              # 0-1
    semantic_score: float = 0.0                  # 0-1
```

### Response Schema

```python
class MealRecommendation(BaseModel):
    """Final recommendation to return"""
    recipe: EnrichedRecipe
    why_it_fits: str                             # LLM-generated explanation
    ingredient_swaps: List[str] = []             # Suggested modifications
    pantry_utilization: List[str] = []           # Which pantry items used

class MealRecommendationResponse(BaseModel):
    """Workflow output"""
    success: bool
    recommendation: Optional[MealRecommendation] = None
    error_message: Optional[str] = None          # If constraints couldn't be met
    suggestions: List[str] = []                  # How to modify constraints
```

---

## Workflow Definition

```python
# workflow.py

from macronome.ai.core.workflow import Workflow
from macronome.ai.core.schema import WorkflowSchema, NodeConfig
from macronome.ai.meal_recommender.schemas import MealRecommendationRequest
from macronome.ai.meal_recommender.pipeline import (
    NormalizeNode,
    PlanningAgent,
    RetrievalNode,
    NutritionNode,
    QCRouter,
    ExplanationNode,
    RelaxAgent,
    FailureNode,
)

class MealRecommendationWorkflow(Workflow):
    """
    Agentic meal recommendation workflow
    
    Flow:
    1. Normalize constraints (parse chat, standardize formats)
    2. Planning agent (decide search strategy)
    3. Retrieval (semantic search → keyword filter → pantry match)
    4. Nutrition calculation (parse ingredients → USDA lookup → filter by macros)
    5. QC Router → either Explanation (success) or Relax Constraints (retry)
    6a. Explanation node (generate reasoning, return meal)
    6b. Relax Agent → retry or ask user
    7. Failure node (explain why no results, suggest modifications)
    """
    
    workflow_schema = WorkflowSchema(
        event_schema=MealRecommendationRequest,
        start=NormalizeNode,
        nodes=[
            NodeConfig(
                node=NormalizeNode,
                connections=[PlanningAgent]
            ),
            NodeConfig(
                node=PlanningAgent,
                connections=[RetrievalNode]
            ),
            NodeConfig(
                node=RetrievalNode,
                connections=[NutritionNode]
            ),
            NodeConfig(
                node=NutritionNode,
                connections=[QCRouter]
            ),
            NodeConfig(
                node=QCRouter,
                connections=[ExplanationNode, RelaxAgent],
                is_router=True
            ),
            NodeConfig(
                node=ExplanationNode,
                connections=[]  # Terminal node (success)
            ),
            NodeConfig(
                node=RelaxAgent,
                connections=[RetrievalNode, FailureNode]  # Retry or give up
            ),
            NodeConfig(
                node=FailureNode,
                connections=[]  # Terminal node (failure)
            ),
        ]
    )
```

---

## Node Implementations (Placeholders)

### Node 1: NormalizeNode

```python
# pipeline/normalize_node.py

from macronome.ai.core.nodes.base import Node
from macronome.ai.core.task import TaskContext

class NormalizeNode(Node):
    """
    Normalize and standardize user constraints
    
    Tasks:
    - Convert calorie target to range (±50)
    - Parse prep_time categories to minutes
    - Extract custom constraints from chat (cuisine, meal_type)
    - Clean and dedupe excluded ingredients
    - Generate semantic query from user_query + constraints
    """
    
    async def process(self, task_context: TaskContext) -> TaskContext:
        # TODO: Implement constraint normalization
        # - Parse chat_history for custom constraints using LLM/regex
        # - Convert calories to range
        # - Map prep_time categories (quick=30, medium=60, long=None)
        # - Build semantic_query from user_query
        
        task_context.state["normalized_constraints"] = {}  # Placeholder
        return task_context
```

### Node 2: PlanningAgent

```python
# pipeline/planning_agent.py

from macronome.ai.core.nodes.agent import AgentNode, AgentConfig

class PlanningAgent(AgentNode):
    """
    LLM agent that plans the retrieval strategy
    
    Decides:
    - How to prioritize constraints (hard vs soft)
    - What semantic query to use
    - Whether to prioritize pantry matching
    - Tool sequence (search → filter → rank)
    
    Available tools:
    - search_recipes_tool(query, max_results)
    - filter_by_diet_tool(recipes, diet_type)
    - filter_by_pantry_tool(recipes, pantry_items, min_match)
    """
    
    config = AgentConfig(
        system_prompt="""You are a meal planning strategist. Analyze the user's request and decide how to search for recipes.
        Consider: semantic query, constraint priorities, pantry item usage.""",
        model="gpt-4o-mini",
        temperature=0.3,
        tools=[],  # TODO: Define tools in tools/agent_tools.py
    )
    
    async def process(self, task_context: TaskContext) -> TaskContext:
        # TODO: Implement planning logic
        # - Call LLM with constraints
        # - Generate search_plan
        
        task_context.state["search_plan"] = {}  # Placeholder
        return task_context
```

### Node 3: RetrievalNode

```python
# pipeline/retrieval_node.py

from macronome.ai.core.nodes.base import Node

class RetrievalNode(Node):
    """
    Execute retrieval plan
    
    Steps:
    1. FAISS semantic search (top 100)
    2. Keyword filtering (diet, excluded ingredients via NER)
    3. Pantry matching (score by % ingredients available)
    4. Narrow to top 20-30 candidates
    """
    
    async def process(self, task_context: TaskContext) -> TaskContext:
        # TODO: Implement retrieval
        # - Load FAISS index
        # - Semantic search using normalized_constraints.semantic_query
        # - Filter by diet, excluded_ingredients (use NER field)
        # - Score pantry matches
        # - Return top 20-30 candidates
        
        task_context.state["candidate_recipes"] = []  # Placeholder
        return task_context
```

### Node 4: NutritionNode

```python
# pipeline/nutrition_node.py

from macronome.ai.core.nodes.base import Node

class NutritionNode(Node):
    """
    Calculate nutrition for candidates and filter by macro constraints
    
    Steps:
    1. For each candidate (20-30):
       - Parse ingredients with LLM
       - Look up nutrition in USDA API (cached)
       - Calculate total macros
    2. Filter by calorie range and macro targets
    3. Return top 10-15 that meet constraints
    """
    
    async def process(self, task_context: TaskContext) -> TaskContext:
        # TODO: Implement nutrition calculation
        # - Parse ingredients (utils/ingredient_parser.py)
        # - USDA lookup (utils/nutrition_calculator.py)
        # - Filter by calorie_range, macro_targets
        # - Estimate prep_time from directions length
        
        task_context.state["filtered_recipes"] = []  # Placeholder
        return task_context
```

### Node 5: QCRouter

```python
# pipeline/qc_router.py

from macronome.ai.core.nodes.router import BaseRouter

class QCRouter(BaseRouter):
    """
    Quality control router - decide if results are good enough
    
    Routes:
    - ExplanationNode: If ≥1 good result found
    - RelaxAgent: If no results or low quality
    """
    
    def route(self, task_context: TaskContext):
        # TODO: Implement QC logic
        # - Check if filtered_recipes has ≥1 result
        # - Check semantic_score and constraint_fit
        # - Route to ExplanationNode or RelaxAgent
        
        from macronome.ai.meal_recommender.pipeline.explanation_node import ExplanationNode
        return ExplanationNode()  # Placeholder
```

### Node 6: ExplanationNode

```python
# pipeline/explanation_node.py

from macronome.ai.core.nodes.base import Node

class ExplanationNode(Node):
    """
    Generate explanation for the recommended meal
    
    Uses LLM to:
    - Explain why this meal fits the user's request
    - Suggest ingredient swaps (for dietary modifications)
    - Highlight pantry item usage
    """
    
    async def process(self, task_context: TaskContext) -> TaskContext:
        # TODO: Implement explanation generation
        # - Select best recipe from filtered_recipes
        # - Call LLM with recipe + constraints + user_query
        # - Generate why_it_fits, ingredient_swaps, pantry_utilization
        # - Build MealRecommendation response
        
        task_context.state["recommendation"] = None  # Placeholder
        task_context.should_stop = True  # End workflow
        return task_context
```

### Node 7: RelaxAgent

```python
# pipeline/relax_agent.py

from macronome.ai.core.nodes.agent import AgentNode, AgentConfig

class RelaxAgent(AgentNode):
    """
    Decide how to handle failed retrieval
    
    Options:
    - Relax one constraint (e.g., increase calorie range)
    - Suggest user modify request
    - Expand semantic search
    
    Routes:
    - RetrievalNode: Retry with relaxed constraints (max 2 retries)
    - FailureNode: Give up and explain to user
    """
    
    config = AgentConfig(
        system_prompt="""You are a constraint relaxation agent. Analyze why no recipes were found and decide how to adjust.""",
        model="gpt-4o-mini",
        temperature=0.3,
    )
    
    async def process(self, task_context: TaskContext) -> TaskContext:
        # TODO: Implement relaxation logic
        # - Check retry count (max 2)
        # - Decide which constraint to relax
        # - Update normalized_constraints
        # - Route to RetrievalNode or FailureNode
        
        return task_context
```

### Node 8: FailureNode

```python
# pipeline/failure_node.py

from macronome.ai.core.nodes.base import Node

class FailureNode(Node):
    """
    Generate helpful error message when no meal can be recommended
    
    Explains:
    - Why constraints couldn't be met
    - Suggestions for how to modify request
    """
    
    async def process(self, task_context: TaskContext) -> TaskContext:
        # TODO: Implement failure messaging
        # - Analyze which constraints failed
        # - Generate user-friendly error_message and suggestions
        # - Build MealRecommendationResponse with success=False
        
        task_context.state["error_message"] = "Could not find matching meal"  # Placeholder
        task_context.should_stop = True
        return task_context
```

---

## Utility Modules (Placeholders)

### Recipe Search

```python
# utils/recipe_search.py

import faiss
import numpy as np
from sentence_transformers import SentenceTransformer

class RecipeSearchEngine:
    """FAISS-based semantic search for recipes"""
    
    def __init__(self, index_path: str, metadata_path: str):
        # TODO: Load FAISS index and recipe metadata
        self.index = None
        self.recipes = []
        self.model = SentenceTransformer('sentence-transformers/all-MiniLM-L6-v2')
    
    def search(self, query: str, top_k: int = 100) -> List[Recipe]:
        # TODO: Embed query, search FAISS, return top_k recipes
        pass
    
    def filter_by_diet(self, recipes: List[Recipe], diet_type: str) -> List[Recipe]:
        # TODO: Keyword filtering using semantic match
        pass
    
    def filter_by_excluded_ingredients(self, recipes: List[Recipe], excluded: Set[str]) -> List[Recipe]:
        # TODO: Check NER field for excluded ingredients
        pass
    
    def score_pantry_match(self, recipe: Recipe, pantry_items: List[str]) -> float:
        # TODO: Calculate % of recipe ingredients in pantry
        pass
```

### Ingredient Parser

```python
# utils/ingredient_parser.py

from typing import List
from macronome.ai.meal_recommender.schemas import ParsedIngredient

async def parse_ingredients_with_llm(ingredients: List[str]) -> List[ParsedIngredient]:
    """
    Use LLM to parse ingredient strings into structured format
    
    Input: ["1 c. firmly packed brown sugar", "1/2 c. evaporated milk"]
    Output: [ParsedIngredient(ingredient="brown sugar", quantity=1.0, unit="cup"), ...]
    """
    # TODO: Implement LLM parsing
    # - Use instructor with structured output
    # - Handle fractions, abbreviations, modifiers
    pass
```

### Nutrition Calculator

```python
# utils/nutrition_calculator.py

from macronome.ai.meal_recommender.schemas import ParsedIngredient, NutritionInfo

class USDANutritionAPI:
    """Interface to USDA FoodData Central API"""
    
    def __init__(self, api_key: str):
        # TODO: Initialize USDA API client
        self.api_key = api_key
        self.cache = {}  # Cache ingredient lookups
    
    async def lookup_ingredient(self, ingredient: str) -> Dict:
        # TODO: Search USDA API, return nutrition per 100g
        pass

async def calculate_recipe_nutrition(parsed_ingredients: List[ParsedIngredient]) -> NutritionInfo:
    """
    Calculate total nutrition for recipe
    
    Steps:
    1. For each ingredient, lookup USDA nutrition
    2. Convert quantity/unit to grams
    3. Calculate nutrition for that quantity
    4. Sum all ingredients
    """
    # TODO: Implement nutrition calculation
    pass
```

### Constraint Parser

```python
# utils/constraint_parser.py

async def parse_custom_constraints_from_chat(chat_history: List[Dict], user_query: str) -> Dict[str, Any]:
    """
    Extract custom constraints from chat that aren't in explicit filters
    
    Examples:
    - "Italian food" → cuisine_type: "Italian"
    - "breakfast ideas" → meal_type: "breakfast"
    - "comfort food" → vibe: "comfort"
    """
    # TODO: Use LLM or regex to extract custom constraints
    pass
```

---

## Integration Points

### FastAPI Endpoint (future)

```python
# Example endpoint structure (not implemented in this plan)

@app.post("/recommend-meal")
async def recommend_meal(request: MealRecommendationRequest):
    workflow = MealRecommendationWorkflow()
    result = await workflow.run_async(request.dict())
    return result.state.get("recommendation")
```

### Frontend Integration

The mobile app will send requests matching `MealRecommendationRequest` schema:

- User query from chat
- Constraints from filter chips
- Pantry items from scanner

---

## Next Steps (Not in This Plan)

1. Implement data ingestion script (`scripts/ingest_recipe_data.py`)
2. Implement each node with actual logic (replace TODOs)
3. Add tool definitions for planning agent
4. Test workflow with sample requests
5. Optimize USDA API caching
6. Add FastAPI endpoint
7. Connect mobile frontend

---

## Dependencies to Add

```
# Add to pyproject.toml or requirements.txt
sentence-transformers
faiss-cpu  # or faiss-gpu
numpy
instructor
litellm
httpx  # for USDA API
```

---

## Notes

- All nodes are placeholders with TODOs - implementation deferred
- USDA API is free but requires API key (register at fdc.nal.usda.gov)
- FAISS index should be built once and reused (not regenerated per query)
- LLM calls should be cached aggressively (parse results, USDA lookups)
- Workflow supports retry loops via RelaxAgent
- Returns single meal recommendation (simplified from 3-5)