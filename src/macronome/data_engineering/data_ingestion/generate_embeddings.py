"""
Recipe Embedding Generation Script

Generates embeddings for recipes and stores in FAISS (local) or Qdrant (cloud).

Usage:
    python -m macronome.data_engineering.data_ingestion.generate_embeddings [options]

Options:
    --source SOURCE         Load recipes from 'local' or 's3' (default: local)
    --target TARGET         Save embeddings to 'faiss', 'qdrant', or 'both' (default: qdrant)
    --limit LIMIT           Limit number of recipes to process (0 = all, for testing)
    --no-clear-existing     Don't clear existing Qdrant collection (default: clear to avoid duplicates)
"""

import argparse
import json
import logging
import sys
import time
from typing import List, Dict

import boto3
from io import BytesIO
import pandas as pd
from qdrant_client import QdrantClient
from qdrant_client.models import PointStruct
import torch
from sentence_transformers import SentenceTransformer

from macronome.data_engineering.config import (
    EMBEDDING_BATCH_SIZE,
    EMBEDDING_MODEL,
    EMBEDDINGS_FAISS,
    METADATA_JSON,
    QDRANT_UPLOAD_BATCH_SIZE,
    RECIPE_CHUNK_SIZE,
    RECIPES_PARQUET,
    RECIPES_PROCESSED_DIR,
)
from macronome.settings import ENV, DataConfig

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def load_recipes_from_local() -> List[Dict]:
    """
    Load recipes from local parquet file
    
    Returns:
        List of recipe dictionaries
    """
    logger.info("Loading recipes from local storage...")
    
    recipes_path = RECIPES_PROCESSED_DIR / RECIPES_PARQUET
    if not recipes_path.exists():
        raise FileNotFoundError(
            f"Recipe file not found at {recipes_path}. "
            f"Run download_recipes.py first."
        )
    
    df = pd.read_parquet(recipes_path)
    recipes = df.to_dict('records')
    
    logger.info(f"Loaded {len(recipes)} recipes from {recipes_path}")
    return recipes


def load_recipes_from_s3() -> List[Dict]:
    """
    Download recipes from S3 and load
    
    Returns:
        List of recipe dictionaries
    """
    logger.info("Loading recipes from S3...")
    
    try:
        
        # Configure S3 client
        s3_config = {}
        if DataConfig.AWS_ACCESS_KEY_ID:
            s3_config['aws_access_key_id'] = DataConfig.AWS_ACCESS_KEY_ID
            s3_config['aws_secret_access_key'] = DataConfig.AWS_SECRET_ACCESS_KEY
        
        s3_client = boto3.client('s3', region_name=DataConfig.S3_REGION, **s3_config)
        
        # Download from S3
        s3_key = f"{DataConfig.S3_RECIPES_PREFIX}{RECIPES_PARQUET}"
        buffer = BytesIO()
        s3_client.download_fileobj(DataConfig.S3_BUCKET, s3_key, buffer)
        buffer.seek(0)
        
        # Load parquet from buffer
        df = pd.read_parquet(buffer)
        recipes = df.to_dict('records')
        
        logger.info(f"Loaded {len(recipes)} recipes from s3://{DataConfig.S3_BUCKET}/{s3_key}")
        return recipes
        
    except ImportError:
        logger.error("boto3 is not installed. Run: pip install boto3")
        raise
    except Exception as e:
        logger.error(f"Failed to load from S3: {e}")
        raise


def generate_embeddings(recipes: List[Dict], model=None, id_offset=0, show_progress=True):
    """
    Generate embeddings for recipes using sentence-transformers
    
    Embeds only title + ingredients (not directions) for better query matching.
    
    Uses Metal (MPS) acceleration on Apple Silicon Macs if available.
    
    Args:
        recipes: List of recipe dictionaries
        model: Pre-loaded SentenceTransformer model (optional, for reuse across chunks)
        id_offset: Offset for metadata indexing (for chunked processing)
        show_progress: Show progress bar
    
    Returns:
        Tuple of (embeddings array, metadata dict, model)
    """

    
    # Load model if not provided
    if model is None:
        # Detect best device for embedding generation
        if torch.backends.mps.is_available():
            device = "mps"  # Metal Performance Shaders (Apple Silicon GPU)
            logger.info("Using Metal (MPS) acceleration for faster embedding generation")
        elif torch.cuda.is_available():
            device = "cuda"
            logger.info("Using CUDA acceleration")
        else:
            device = "cpu"
            logger.info("Using CPU for embedding generation")
        
        # Load embedding model on selected device
        logger.info(f"Loading embedding model: {EMBEDDING_MODEL}")
        model = SentenceTransformer(EMBEDDING_MODEL, device=device)
    
    # Prepare texts for embedding (title + ingredients only)
    texts = [
        f"{recipe['title']}: {' '.join(recipe['ingredients']) if isinstance(recipe['ingredients'], list) else str(recipe['ingredients'])}"
        for recipe in recipes
    ]
    
    # Generate embeddings in batches
    logger.info(f"Generating embeddings for {len(texts)} recipes (batch_size={EMBEDDING_BATCH_SIZE})...")
    start_time = time.time()
    
    embeddings = model.encode(
        texts,
        batch_size=EMBEDDING_BATCH_SIZE,
        show_progress_bar=show_progress,
        convert_to_numpy=True,
    )
    
    elapsed = time.time() - start_time
    logger.info(f"Generated embeddings with shape {embeddings.shape} in {elapsed:.2f}s ({len(texts)/elapsed:.0f} recipes/sec)")
    
    # Create metadata mapping (recipe_id -> index in vector store)
    metadata = {
        recipe["id"]: id_offset + i for i, recipe in enumerate(recipes)
    }
    
    return embeddings, metadata, model


def save_to_faiss(embeddings, metadata, recipes):
    """
    Build FAISS index and save locally
    
    Args:
        embeddings: Numpy array of embeddings
        metadata: Recipe metadata dictionary
        recipes: List of recipe dictionaries
    """
    logger.info("Saving to FAISS...")
    
    try:
        import faiss
    except ImportError:
        logger.error("FAISS is not installed. Run: pip install faiss-cpu or faiss-gpu")
        raise
    
    # Create output directory
    RECIPES_PROCESSED_DIR.mkdir(parents=True, exist_ok=True)
    
    # Build FAISS index
    logger.info("Building FAISS index...")
    dim = embeddings.shape[1]
    index = faiss.IndexFlatL2(dim)
    index.add(embeddings.astype('float32'))
    logger.info(f"FAISS index built successfully. Total vectors: {index.ntotal}")
    
    # Save FAISS index
    index_path = RECIPES_PROCESSED_DIR / EMBEDDINGS_FAISS
    faiss.write_index(index, str(index_path))
    logger.info(f"Saved FAISS index to {index_path}")
    
    # Save metadata
    metadata_path = RECIPES_PROCESSED_DIR / METADATA_JSON
    # Store full recipes in metadata for retrieval
    metadata_with_recipes = {
        "recipe_id_to_index": metadata,
        "recipes": recipes
    }
    with open(metadata_path, 'w') as f:
        json.dump(metadata_with_recipes, f, indent=2)
    logger.info(f"Saved metadata to {metadata_path}")


def init_qdrant_client():
    """Initialize and return a Qdrant client"""    
    # Check configuration
    if not DataConfig.QDRANT_URL or not DataConfig.QDRANT_API_KEY:
        logger.error("QDRANT_URL and QDRANT_API_KEY must be set in environment")
        raise ValueError("Missing Qdrant configuration")
    
    # Initialize Qdrant client
    logger.info(f"Connecting to Qdrant at {DataConfig.QDRANT_URL}")
    client = QdrantClient(
        url=DataConfig.QDRANT_URL,
        api_key=DataConfig.QDRANT_API_KEY,
    )
    return client


def setup_qdrant_collection(client, vector_dim, clear_existing=True):
    """
    Setup Qdrant collection (create or clear if needed)
    
    Args:
        client: QdrantClient instance
        vector_dim: Dimension of embedding vectors
        clear_existing: If True, delete and recreate collection
    """
    try:
        from qdrant_client.models import Distance, VectorParams
    except ImportError:
        logger.error("qdrant-client is not installed")
        raise
    
    collection_name = DataConfig.QDRANT_COLLECTION_NAME
    
    # Check if collection exists
    collections = client.get_collections().collections
    collection_names = [col.name for col in collections]
    collection_exists = collection_name in collection_names
    
    if collection_exists and clear_existing:
        logger.info(f"Collection '{collection_name}' exists. Deleting to avoid duplicates...")
        client.delete_collection(collection_name)
        logger.info(f"Collection '{collection_name}' deleted successfully")
        collection_exists = False
    
    # Create collection if it doesn't exist
    if not collection_exists:
        logger.info(f"Creating collection '{collection_name}'...")
        client.create_collection(
            collection_name=collection_name,
            vectors_config=VectorParams(
                size=vector_dim,
                distance=Distance.COSINE  # Cosine similarity for semantic search
            )
        )
        logger.info(f"Collection '{collection_name}' created successfully")


def upload_to_qdrant_chunk(client, embeddings, recipes, id_offset=0):
    """
    Upload a chunk of embeddings to Qdrant
    
    Args:
        client: QdrantClient instance
        embeddings: Numpy array of embeddings for this chunk
        recipes: List of recipe dictionaries for this chunk
        id_offset: Global ID offset for this chunk
    """

    
    collection_name = DataConfig.QDRANT_COLLECTION_NAME
    batch_size = QDRANT_UPLOAD_BATCH_SIZE  # 1000 is much faster than 100
    
    # Upload in batches
    for i in range(0, len(recipes), batch_size):
        batch_recipes = recipes[i:i + batch_size]
        batch_embeddings = embeddings[i:i + batch_size]
        
        # Build points on-the-fly (don't store full list in memory)
        points = [
            PointStruct(
                id=id_offset + i + j,
                vector=vector.tolist(),
                payload={
                    "recipe_id": recipe["id"],
                    "title": recipe["title"],  # Keep title for quick display/filtering
                }
            )
            for j, (recipe, vector) in enumerate(zip(batch_recipes, batch_embeddings))
        ]
        
        # Upload batch
        client.upsert(collection_name=collection_name, points=points)
    
    logger.info(f"Uploaded chunk: {len(recipes)} vectors (IDs {id_offset} - {id_offset + len(recipes) - 1})")


def process_qdrant_streamed(source_path, is_s3=False, limit=0, clear_existing=True):
    """
    Stream-process recipes in chunks for Qdrant (memory-efficient for large datasets)
    
    Args:
        source_path: Path to parquet file (local or S3 key)
        is_s3: Whether source is S3
        limit: Max recipes to process (0 = all)
        clear_existing: Clear Qdrant collection before starting
    """
    import time
    
    # Initialize Qdrant client
    client = init_qdrant_client()
    
    # Load model once
    model = None
    total_processed = 0
    chunk_num = 0
    vector_dim = None
    start_time = time.time()
    
    # Determine total recipes for limit
    if is_s3:
        # For S3, we'll read file info to get row count (parquet metadata)
        s3_config = {}
        if DataConfig.AWS_ACCESS_KEY_ID:
            s3_config['aws_access_key_id'] = DataConfig.AWS_ACCESS_KEY_ID
            s3_config['aws_secret_access_key'] = DataConfig.AWS_SECRET_ACCESS_KEY
        
        s3_client = boto3.client('s3', region_name=DataConfig.S3_REGION, **s3_config)
        buffer = BytesIO()
        s3_client.download_fileobj(DataConfig.S3_BUCKET, source_path, buffer)
        buffer.seek(0)
        total_recipes = len(pd.read_parquet(buffer))
        buffer.seek(0)
        parquet_file = buffer
    else:
        total_recipes = len(pd.read_parquet(source_path))
        parquet_file = source_path
    
    # Apply limit
    if limit > 0:
        total_recipes = min(total_recipes, limit)
        logger.info(f"Processing limit: {total_recipes} recipes")
    
    logger.info(f"Total recipes to process: {total_recipes}")
    logger.info(f"Chunk size: {RECIPE_CHUNK_SIZE}")
    logger.info(f"Estimated chunks: {(total_recipes + RECIPE_CHUNK_SIZE - 1) // RECIPE_CHUNK_SIZE}")
    
    # Process in chunks
    offset = 0
    while offset < total_recipes:
        chunk_size = min(RECIPE_CHUNK_SIZE, total_recipes - offset)
        chunk_num += 1
        
        logger.info("=" * 60)
        logger.info(f"Processing chunk {chunk_num} (recipes {offset} - {offset + chunk_size - 1})")
        logger.info("=" * 60)
        
        # Read chunk
        logger.info("Reading chunk from parquet...")
        df_chunk = pd.read_parquet(parquet_file, engine='pyarrow')
        df_chunk = df_chunk.iloc[offset:offset + chunk_size]
        recipes_chunk = df_chunk.to_dict('records')
        
        logger.info(f"Loaded {len(recipes_chunk)} recipes for this chunk")
        
        # Generate embeddings for this chunk
        embeddings_chunk, _, model = generate_embeddings(
            recipes_chunk, 
            model=model,  # Reuse model across chunks
            id_offset=offset, 
            show_progress=(chunk_num == 1)  # Only show progress on first chunk
        )
        
        # Setup collection on first chunk
        if chunk_num == 1:
            if vector_dim is None:
                vector_dim = embeddings_chunk.shape[1]
            setup_qdrant_collection(client, vector_dim, clear_existing=clear_existing)
        
        # Upload this chunk
        upload_to_qdrant_chunk(client, embeddings_chunk, recipes_chunk, id_offset=offset)
        
        total_processed += len(recipes_chunk)
        offset += chunk_size
        
        # Log progress
        elapsed = time.time() - start_time
        recipes_per_sec = total_processed / elapsed
        logger.info(f"Progress: {total_processed}/{total_recipes} recipes ({100*total_processed/total_recipes:.1f}%) in {elapsed:.1f}s ({recipes_per_sec:.0f} recipes/sec)")
    
    # Final verification
    collection_info = client.get_collection(DataConfig.QDRANT_COLLECTION_NAME)
    logger.info(f"Final collection: {collection_info.points_count} points")
    
    elapsed = time.time() - start_time
    logger.info(f"Total time: {elapsed:.1f}s ({total_processed/elapsed:.0f} recipes/sec)")


def main():
    """Main embedding generation pipeline"""
    parser = argparse.ArgumentParser(description="Generate recipe embeddings")
    parser.add_argument(
        "--source",
        type=str,
        choices=["local", "s3"],
        default="local",
        help="Load recipes from 'local' or 's3' (default: local)"
    )
    parser.add_argument(
        "--target",
        type=str,
        choices=["faiss", "qdrant", "both"],
        default="qdrant",
        help="Save embeddings to 'faiss', 'qdrant', or 'both' (default: qdrant)"
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Limit number of recipes to process (0 = all, for testing)"
    )
    parser.add_argument(
        "--no-clear-existing",
        action="store_true",
        help="Don't clear existing Qdrant collection (default: clear to avoid duplicates)"
    )
    args = parser.parse_args()
    
    # Clear existing flag
    clear_existing = not args.no_clear_existing
    
    logger.info("=" * 60)
    logger.info("Recipe Embedding Generation")
    logger.info("=" * 60)
    logger.info(f"Environment: {ENV}")
    logger.info(f"Source: {args.source}")
    logger.info(f"Target: {args.target}")
    logger.info(f"Recipe limit: {args.limit if args.limit > 0 else 'None (all recipes)'}")
    logger.info(f"Embedding model: {EMBEDDING_MODEL}")
    logger.info(f"Embedding batch size: {EMBEDDING_BATCH_SIZE}")
    logger.info(f"Chunk size: {RECIPE_CHUNK_SIZE}")
    logger.info("Embedding format: title: ingredients")
    if args.target in ["qdrant", "both"]:
        logger.info(f"Qdrant collection: {DataConfig.QDRANT_COLLECTION_NAME}")
        logger.info(f"Qdrant upload batch size: {QDRANT_UPLOAD_BATCH_SIZE}")
        logger.info(f"Clear existing vectors: {clear_existing}")
    logger.info("=" * 60)
    
    try:
        # Determine source path
        if args.source == "local":
            source_path = RECIPES_PROCESSED_DIR / RECIPES_PARQUET
            is_s3 = False
        else:
            source_path = RECIPES_PARQUET
            is_s3 = True
        
        # Process based on target
        if args.target == "qdrant":
            # Use streaming for Qdrant (memory-efficient)
            process_qdrant_streamed(source_path, is_s3, args.limit, clear_existing)
        elif args.target == "faiss":
            # FAISS needs all data in memory (old approach)
            logger.info("Loading all recipes into memory (required for FAISS)...")
            if args.source == "local":
                recipes = load_recipes_from_local()
            else:
                recipes = load_recipes_from_s3()
            
            if args.limit > 0:
                recipes = recipes[:args.limit]
                logger.info(f"Limited to {len(recipes)} recipes")
            
            embeddings, metadata, model = generate_embeddings(recipes)
            save_to_faiss(embeddings, metadata, recipes)
        else:  # both
            # For both, use old approach (needs all in memory for FAISS anyway)
            logger.warning("Target 'both' requires loading all recipes into memory (for FAISS)")
            if args.source == "local":
                recipes = load_recipes_from_local()
            else:
                recipes = load_recipes_from_s3()
            
            if args.limit > 0:
                recipes = recipes[:args.limit]
                logger.info(f"Limited to {len(recipes)} recipes")
            
            embeddings, metadata, model = generate_embeddings(recipes)
            save_to_faiss(embeddings, metadata, recipes)
            
            # For Qdrant, use streaming
            logger.info("\nNow uploading to Qdrant...")
            process_qdrant_streamed(source_path, is_s3, args.limit, clear_existing)
        
        logger.info("=" * 60)
        logger.info("Embedding generation complete!")
        logger.info("=" * 60)
        
    except Exception as e:
        logger.error(f"Embedding generation failed: {e}", exc_info=True)
        sys.exit(1)


if __name__ == "__main__":
    main()

