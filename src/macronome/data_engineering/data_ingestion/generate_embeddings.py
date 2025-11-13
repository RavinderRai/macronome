"""
Recipe Embedding Generation Script

Generates embeddings for recipes and stores in FAISS (local) or Qdrant (cloud).

Usage:
    python -m macronome.data_engineering.data_ingestion.generate_embeddings [options]

Options:
    --source SOURCE      Load recipes from 'local' or 's3' (default: local)
    --target TARGET      Save embeddings to 'faiss', 'qdrant', or 'both' (default: qdrant)
"""

import argparse
import json
import logging
import sys
from pathlib import Path
from typing import List, Dict

import pandas as pd
import torch
from sentence_transformers import SentenceTransformer

from macronome.data_engineering.config import (
    EMBEDDING_BATCH_SIZE,
    EMBEDDING_MODEL,
    EMBEDDINGS_FAISS,
    METADATA_JSON,
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
        import boto3
        from io import BytesIO
        
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


def generate_embeddings(recipes: List[Dict]):
    """
    Generate embeddings for recipes using sentence-transformers
    
    Embeds only title + ingredients (not directions) for better query matching.
    
    Uses Metal (MPS) acceleration on Apple Silicon Macs if available.
    
    Args:
        recipes: List of recipe dictionaries
    
    Returns:
        Tuple of (embeddings array, metadata dict)
    """
    logger.info("Generating embeddings...")
    
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
    
    # Prepare texts for embedding (title + ingredients only, per Option A)
    texts = []
    for recipe in recipes:
        # Join ingredients into a space-separated string
        ingredients_str = " ".join(recipe["ingredients"]) if isinstance(recipe["ingredients"], list) else str(recipe["ingredients"])
        
        # Combine title and ingredients
        text = f"{recipe['title']} {ingredients_str}"
        texts.append(text)
    
    # Generate embeddings in batches
    logger.info(f"Generating embeddings for {len(texts)} recipes on {device.upper()}...")
    logger.info("Embedding format: title + ingredients (no directions)")
    embeddings = model.encode(
        texts,
        batch_size=EMBEDDING_BATCH_SIZE,
        show_progress_bar=True,
        convert_to_numpy=True
    )
    
    logger.info(f"Generated embeddings with shape: {embeddings.shape}")
    
    # Create metadata mapping (recipe_id -> index in vector store)
    metadata = {
        recipe["id"]: i for i, recipe in enumerate(recipes)
    }
    
    return embeddings, metadata, recipes


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


def save_to_qdrant(embeddings, metadata, recipes):
    """
    Upload embeddings to Qdrant cloud
    
    Args:
        embeddings: Numpy array of embeddings
        metadata: Recipe metadata dictionary
        recipes: List of recipe dictionaries
    """
    logger.info("Uploading to Qdrant...")
    
    try:
        from qdrant_client import QdrantClient
        from qdrant_client.models import Distance, VectorParams, PointStruct
    except ImportError:
        logger.error("qdrant-client is not installed. Run: pip install qdrant-client")
        raise
    
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
    
    # Get collection name
    collection_name = DataConfig.QDRANT_COLLECTION_NAME
    
    # Check if collection exists, create if not
    try:
        collections = client.get_collections().collections
        collection_names = [col.name for col in collections]
        
        if collection_name in collection_names:
            logger.info(f"Collection '{collection_name}' already exists, deleting and recreating...")
            client.delete_collection(collection_name)
        
        # Create collection
        logger.info(f"Creating collection '{collection_name}'...")
        client.create_collection(
            collection_name=collection_name,
            vectors_config=VectorParams(
                size=embeddings.shape[1],
                distance=Distance.COSINE  # Cosine similarity for semantic search
            )
        )
        logger.info(f"Collection '{collection_name}' created successfully")
        
    except Exception as e:
        logger.error(f"Failed to setup collection: {e}")
        raise
    
    # Prepare points for upload
    logger.info("Preparing vectors for upload...")
    points = []
    for i, (recipe, embedding) in enumerate(zip(recipes, embeddings)):
        point = PointStruct(
            id=i,
            vector=embedding.tolist(),
            payload={
                "recipe_id": recipe["id"],
                "title": recipe["title"],
                "ingredients": recipe["ingredients"],
                "directions": recipe["directions"],
                "ner": recipe["ner"],
                "source": recipe.get("source", ""),
                "link": recipe.get("link", ""),
            }
        )
        points.append(point)
        
        if (i + 1) % 1000 == 0:
            logger.info(f"Prepared {i + 1}/{len(recipes)} vectors...")
    
    # Upload in batches
    logger.info(f"Uploading {len(points)} vectors to Qdrant...")
    batch_size = 100
    for i in range(0, len(points), batch_size):
        batch = points[i:i + batch_size]
        client.upsert(
            collection_name=collection_name,
            points=batch
        )
        if (i + batch_size) % 1000 == 0:
            logger.info(f"Uploaded {min(i + batch_size, len(points))}/{len(points)} vectors...")
    
    logger.info(f"Successfully uploaded {len(points)} vectors to Qdrant collection '{collection_name}'")
    
    # Verify upload
    collection_info = client.get_collection(collection_name)
    logger.info(f"Collection info: {collection_info.points_count} points")


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
    args = parser.parse_args()
    
    logger.info("=" * 60)
    logger.info("Recipe Embedding Generation")
    logger.info("=" * 60)
    logger.info(f"Environment: {ENV.value}")
    logger.info(f"Source: {args.source}")
    logger.info(f"Target: {args.target}")
    logger.info(f"Embedding model: {EMBEDDING_MODEL}")
    logger.info(f"Embedding format: title + ingredients (Option A)")
    if args.target in ["qdrant", "both"]:
        logger.info(f"Qdrant collection: {DataConfig.QDRANT_COLLECTION_NAME}")
    logger.info("=" * 60)
    
    try:
        # Step 1: Load recipes
        if args.source == "local":
            recipes = load_recipes_from_local()
        elif args.source == "s3":
            recipes = load_recipes_from_s3()
        else:
            raise ValueError(f"Unknown source: {args.source}")
        
        # Step 2: Generate embeddings
        embeddings, metadata, recipes = generate_embeddings(recipes)
        
        # Step 3: Save to target(s)
        if args.target in ["faiss", "both"]:
            save_to_faiss(embeddings, metadata, recipes)
        
        if args.target in ["qdrant", "both"]:
            save_to_qdrant(embeddings, metadata, recipes)
        
        logger.info("=" * 60)
        logger.info("Embedding generation complete!")
        logger.info("=" * 60)
        
    except Exception as e:
        logger.error(f"Embedding generation failed: {e}", exc_info=True)
        sys.exit(1)


if __name__ == "__main__":
    main()

