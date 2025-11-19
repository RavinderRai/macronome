import json
import logging
from typing import List
import numpy as np

import faiss
from sentence_transformers import SentenceTransformer
from qdrant_client import QdrantClient

from macronome.ai.core.nodes.base import Node
from macronome.ai.core.task import TaskContext
from macronome.ai.schemas.recipe_schema import Recipe
from macronome.ai.schemas.workflow_schemas import PlanningOutput
from macronome.ai.workflows.meal_recommender_workflow_nodes.planning_agent import PlanningAgent
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
        """Initialize Qdrant client (no S3 loading needed - recipes built from payloads)"""
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
        """Perform Qdrant semantic search and build Recipe objects from payloads"""
        logger.debug(f"Qdrant search: query='{query}', top_k={top_k}")
        
        # Embed query
        query_embedding = self._embed_query(query)
        
        # Search Qdrant
        collection_name = DataConfig.QDRANT_COLLECTION_NAME
        search_results = self._qdrant_client.search(
            collection_name=collection_name,
            query_vector=query_embedding[0].tolist(),
            limit=top_k,
            with_payload=True  # Ensure payloads are returned
        )
                
        # Build Recipe objects directly from Qdrant payloads (no S3 lookup needed!)
        results = []
        for i, result in enumerate(search_results):
            payload = result.payload
            
            # Debug first result payload structure
            if i == 0:
                ingredients = payload.get("ingredients", [])
                logger.debug(
                    f"First result payload: recipe_id={payload.get('recipe_id')}, "
                    f"title={payload.get('title', '')[:50]}, "
                    f"ingredients_type={type(ingredients).__name__}, "
                    f"ingredients_count={len(ingredients) if isinstance(ingredients, list) else 'N/A'}"
                )
            
            # Build Recipe from payload metadata
            recipe = Recipe(
                id=payload["recipe_id"],
                title=payload.get("title", ""),
                ingredients=payload.get("ingredients", []) if isinstance(payload.get("ingredients"), list) else [],
                directions="",  # Not needed for SelectionAgent
                ner=[],  # Not using NER filtering anymore
                source="",
                link="",
            )
            
            # Qdrant returns cosine similarity score (0-1)
            results.append((recipe, float(result.score)))
        
        return results
    
    async def process(self, task_context: TaskContext) -> TaskContext:
        """
        Execute recipe retrieval - pure semantic search, no filtering.
        
        Args:
            task_context: Contains PlanningOutput from PlanningAgent
            
        Returns:
            TaskContext with candidate recipes saved
        """
        # Load index and embedding model (lazy)
        self._load_index_and_recipes()
        
        # Get planning output
        planning_output = self.get_output(PlanningAgent)
        if planning_output is None:
            raise ValueError("PlanningOutput not found in task context")
        
        planning: PlanningOutput = planning_output.model_output
        logger.info(f"Retrieving recipes with query: '{planning.search_query}'")
        logger.debug(f"Search strategy: {planning.search_strategy}, Top K: {planning.top_k}")
        
        # Semantic search only - return top 10 for SelectionAgent to choose from
        candidates = self._semantic_search(planning.search_query, 10)
        
        # Extract recipes (already sorted by score)
        top_recipes = [recipe for recipe, score in candidates]
        
        logger.info(f"Returning {len(top_recipes)} recipes to SelectionAgent")
        
        # Save to task context
        self.save_output(top_recipes)
        
        return task_context

