import json
import logging
from typing import List
import numpy as np

try:
    import faiss
    FAISS_AVAILABLE = True
except ImportError:
    FAISS_AVAILABLE = False
    
from sentence_transformers import SentenceTransformer
from qdrant_client import QdrantClient

from macronome.ai.core.nodes.base import Node
from macronome.ai.core.task import TaskContext
from macronome.ai.schemas.recipe_schema import Recipe
from macronome.ai.schemas.workflow_schemas import PlanningOutput
from macronome.data_engineering.config import (
    RECIPES_PROCESSED_DIR,
    EMBEDDINGS_FAISS,
    METADATA_JSON,
    EMBEDDING_MODEL,
)
from macronome.settings import DataConfig

logger = logging.getLogger(__name__)

"""
Retrieval Node

Regular node (not AgentNode) that executes semantic search using FAISS.
Retrieves top candidate recipes based on planning strategy.
"""


class RetrievalNode(Node):
    """
    Third node in meal recommendation workflow.
    
    Executes semantic search to find candidate recipes.
    
    Input: PlanningOutput from PlanningAgent
    Output: List[Recipe] saved to task_context.nodes["RetrievalNode"]
    
    Steps:
    1. Load FAISS index and recipe metadata
    2. Embed search query
    3. Semantic search for top candidates
    4. Filter by hard constraints (diet, excluded ingredients)
    5. Score by pantry match
    6. Return top K recipes
    """
    
    def __init__(self, task_context: TaskContext = None):
        super().__init__(task_context)
        self._faiss_index = None
        self._qdrant_client = None
        self._recipes = None
        self._model = None
        self._use_qdrant = DataConfig.VECTOR_BACKEND == "qdrant"
    
    class OutputType(List[Recipe]):
        """RetrievalNode outputs List[Recipe]"""
        pass
    
    def _load_index_and_recipes(self):
        """Load vector index (FAISS or Qdrant) and recipe metadata (lazy loading)"""
        if self._model is not None:
            return  # Already loaded
        
        # Load embedding model (needed for both FAISS and Qdrant)
        logger.info(f"Loading embedding model: {EMBEDDING_MODEL}")
        self._model = SentenceTransformer(EMBEDDING_MODEL)
        
        if self._use_qdrant:
            self._load_qdrant()
        else:
            self._load_faiss()
    
    def _load_faiss(self):
        """Load FAISS index and local metadata"""
        if self._faiss_index is not None:
            return
        
        if not FAISS_AVAILABLE:
            raise RuntimeError(
                "FAISS is not installed. Run: pip install faiss-cpu or faiss-gpu"
            )
        
        # Load FAISS index
        index_path = RECIPES_PROCESSED_DIR / EMBEDDINGS_FAISS
        if not index_path.exists():
            raise FileNotFoundError(
                f"FAISS index not found at {index_path}. "
                f"Run generate_embeddings.py first."
            )
        
        logger.info(f"Loading FAISS index from {index_path}")
        self._faiss_index = faiss.read_index(str(index_path))
        
        # Load recipe metadata (new format has "recipes" key)
        metadata_path = RECIPES_PROCESSED_DIR / METADATA_JSON
        if not metadata_path.exists():
            raise FileNotFoundError(
                f"Recipe metadata not found at {metadata_path}. "
                f"Run generate_embeddings.py first."
            )
        
        logger.info(f"Loading recipe metadata from {metadata_path}")
        with open(metadata_path, 'r') as f:
            metadata = json.load(f)
            # New format: {"recipe_id_to_index": {...}, "recipes": [...]}
            if isinstance(metadata, dict) and "recipes" in metadata:
                recipes_data = metadata["recipes"]
            else:
                # Legacy format: just a list of recipes
                recipes_data = metadata
            self._recipes = [Recipe(**r) for r in recipes_data]
        
        logger.info(f"Loaded {len(self._recipes)} recipes")
    
    def _load_qdrant(self):
        """Initialize Qdrant client"""
        if self._qdrant_client is not None:
            return
        
        if not DataConfig.QDRANT_URL or not DataConfig.QDRANT_API_KEY:
            raise ValueError("QDRANT_URL and QDRANT_API_KEY must be set in environment")
        
        logger.info(f"Connecting to Qdrant at {DataConfig.QDRANT_URL}")
        self._qdrant_client = QdrantClient(
            url=DataConfig.QDRANT_URL,
            api_key=DataConfig.QDRANT_API_KEY,
        )
        
        # Verify collection exists
        collection_name = DataConfig.QDRANT_COLLECTION_NAME
        try:
            collection_info = self._qdrant_client.get_collection(collection_name)
            logger.info(f"Connected to Qdrant collection '{collection_name}' with {collection_info.points_count} recipes")
        except Exception as e:
            raise RuntimeError(
                f"Failed to connect to Qdrant collection '{collection_name}': {e}. "
                f"Run generate_embeddings.py first."
            )
    
    def _embed_query(self, query: str) -> np.ndarray:
        """Embed search query using sentence-transformers"""
        embedding = self._model.encode([query], convert_to_numpy=True)
        return embedding.astype('float32')
    
    def _semantic_search(self, query: str, top_k: int) -> List[Recipe]:
        """Perform semantic search using FAISS or Qdrant"""
        if self._use_qdrant:
            return self._semantic_search_qdrant(query, top_k)
        else:
            return self._semantic_search_faiss(query, top_k)
    
    def _semantic_search_faiss(self, query: str, top_k: int) -> List[tuple]:
        """Perform FAISS semantic search"""
        # Embed query
        query_embedding = self._embed_query(query)
        
        # Search FAISS index
        distances, indices = self._faiss_index.search(query_embedding, top_k * 2)  # Get more for filtering
        
        # Get recipes
        results = []
        for dist, idx in zip(distances[0], indices[0]):
            if idx < len(self._recipes):
                recipe = self._recipes[int(idx)]
                # Add semantic score (convert distance to similarity)
                results.append((recipe, float(1 / (1 + dist))))
        
        return results
    
    def _semantic_search_qdrant(self, query: str, top_k: int) -> List[tuple]:
        """Perform Qdrant semantic search"""
        # Embed query
        query_embedding = self._embed_query(query)
        
        # Search Qdrant
        collection_name = DataConfig.QDRANT_COLLECTION_NAME
        search_results = self._qdrant_client.search(
            collection_name=collection_name,
            query_vector=query_embedding[0].tolist(),
            limit=top_k * 2  # Get more for filtering
        )
        
        # Convert to Recipe objects
        results = []
        for result in search_results:
            payload = result.payload
            recipe_dict = {
                "id": payload["recipe_id"],
                "title": payload["title"],
                "ingredients": payload["ingredients"],
                "directions": payload["directions"],
                "ner": payload["ner"],
                "source": payload.get("source", ""),
                "link": payload.get("link", ""),
            }
            recipe = Recipe(**recipe_dict)
            # Qdrant returns cosine similarity score (0-1)
            results.append((recipe, float(result.score)))
        
        return results
    
    def _filter_by_diet(self, recipes: List[tuple], diet_type: str) -> List[tuple]:
        """Filter recipes by diet type using NER (named entity recognition) field"""
        if not diet_type:
            return recipes
        
        filtered = []
        
        # Simple diet filtering (can be enhanced)
        exclude_keywords = {
            "vegan": ["beef", "chicken", "pork", "fish", "milk", "egg", "cheese", "butter", "meat"],
            "vegetarian": ["beef", "chicken", "pork", "fish", "meat"],
            "keto": ["rice", "pasta", "bread", "potato", "sugar"],
            # Add more as needed
        }
        
        keywords = exclude_keywords.get(diet_type.lower(), [])
        
        for recipe, score in recipes:
            # Check if any excluded keywords appear in NER
            recipe_ingredients = set(ing.lower() for ing in recipe.ner)
            if not any(keyword in ing for keyword in keywords for ing in recipe_ingredients):
                filtered.append((recipe, score))
        
        return filtered
    
    def _filter_by_excluded(self, recipes: List[tuple], must_exclude: List[str]) -> List[tuple]:
        """Filter out recipes containing excluded ingredients"""
        if not must_exclude:
            return recipes
        
        excluded_set = set(item.lower() for item in must_exclude)
        filtered = []
        
        for recipe, score in recipes:
            recipe_ingredients = set(ing.lower() for ing in recipe.ner)
            # Exclude if any excluded ingredient is found
            if not any(excluded in ing for excluded in excluded_set for ing in recipe_ingredients):
                filtered.append((recipe, score))
        
        return filtered
    
    def _score_pantry_match(self, recipe: Recipe, pantry_items: List[str]) -> float:
        """Calculate pantry match score (0-1)"""
        if not pantry_items:
            return 0.0
        
        pantry_set = set(item.lower() for item in pantry_items)
        recipe_ingredients = set(ing.lower() for ing in recipe.ner)
        
        # Count matches
        matches = sum(
            1 for pantry_item in pantry_set
            if any(pantry_item in recipe_ing for recipe_ing in recipe_ingredients)
        )
        
        # Score as percentage of pantry used
        return matches / len(pantry_set)
    
    async def process(self, task_context: TaskContext) -> TaskContext:
        """
        Execute recipe retrieval based on planning output.
        
        Args:
            task_context: Contains PlanningOutput from PlanningAgent
            
        Returns:
            TaskContext with candidate recipes saved
        """
        # Load index and recipes (lazy)
        self._load_index_and_recipes()
        
        # Get planning output
        planning: PlanningOutput = task_context.nodes.get("PlanningAgent")
        if planning is None:
            raise ValueError("PlanningOutput not found in task context")
        
        logger.info(f"Retrieving recipes with query: '{planning.search_query}'")
        logger.info(f"Strategy: {planning.search_strategy}, Top K: {planning.top_k}")
        
        # 1. Semantic search
        candidates = self._semantic_search(planning.search_query, planning.top_k * 3)
        logger.info(f"Semantic search returned {len(candidates)} candidates")
        
        # 2. Filter by hard constraints
        if planning.hard_filters.get("diet_type"):
            candidates = self._filter_by_diet(candidates, planning.hard_filters["diet_type"])
            logger.info(f"After diet filter: {len(candidates)} candidates")
        
        if planning.must_exclude:
            candidates = self._filter_by_excluded(candidates, planning.must_exclude)
            logger.info(f"After exclude filter: {len(candidates)} candidates")
        
        # 3. Score by pantry match if strategy prioritizes it
        if planning.search_strategy == "pantry_first" and planning.must_include:
            # Re-score with pantry match
            scored_candidates = []
            for recipe, semantic_score in candidates:
                pantry_score = self._score_pantry_match(recipe, planning.must_include)
                # Weighted combination: 60% pantry, 40% semantic
                combined_score = (pantry_score * 0.6) + (semantic_score * 0.4)
                scored_candidates.append((recipe, combined_score))
            
            # Sort by combined score
            scored_candidates.sort(key=lambda x: x[1], reverse=True)
            candidates = scored_candidates
        
        # 4. Get top K recipes
        top_recipes = [recipe for recipe, score in candidates[:planning.top_k]]
        
        logger.info(f"Final selection: {len(top_recipes)} recipes")
        
        # Save to task context
        self.save_output(top_recipes)
        
        return task_context

