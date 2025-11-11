"""
Recipe Data Ingestion Script

Downloads RecipeNLG dataset from Kaggle via HuggingFace,
processes recipes, generates embeddings, and builds FAISS index.

Usage:
    # From src/ directory:
    python -m macronome.data_engineering.data_ingestion.ingest_recipes [--limit LIMIT]
    # Or from repo root:
    python src/macronome/data_engineering/data_ingestion/ingest_recipes.py [--limit LIMIT]

Options:
    --limit LIMIT    Only process first LIMIT recipes (for testing)
"""

import argparse
import json
import logging
import sys
from pathlib import Path
import faiss
import kagglehub
import pandas as pd
import torch
from datasets import load_dataset
from sentence_transformers import SentenceTransformer

# Import from macronome package
from macronome.data_engineering.config import (
    EMBEDDING_BATCH_SIZE,
    EMBEDDING_MODEL,
    EMBEDDINGS_FAISS,
    MAX_TEXT_LENGTH,
    METADATA_JSON,
    RECIPENLG_DATASET,
    RECIPES_PARQUET,
    RECIPES_PROCESSED_DIR,
)
from macronome.settings import ENV, DataConfig

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def download_recipenlg_dataset():
    """
    Download RecipeNLG dataset from Kaggle using HuggingFace datasets
    
    Downloads via kagglehub, then loads with HuggingFace datasets library.
    
    Returns:
        HuggingFace Dataset object
    """
    logger.info("Downloading RecipeNLG dataset from Kaggle...")
    
    # Download dataset using kagglehub (downloads to cache)
    # Returns a string path, convert to Path object
    dataset_path_str = kagglehub.dataset_download(RECIPENLG_DATASET)
    dataset_path = Path(dataset_path_str)
    logger.info(f"Dataset downloaded to: {dataset_path}")
    
    # Find the main recipe dataset file (exclude model/code files)
    # RecipeNLG typically has files like: full_dataset.csv, dataset.csv, recipes.json, etc.
    recipe_files = []
    
    # Look for common recipe data file patterns
    for pattern in ["**/full_dataset.csv", "**/dataset.csv", "**/recipes.json", "**/*recipe*.csv"]:
        found = list(dataset_path.glob(pattern))
        if found:
            recipe_files.extend(found)
            break  # Use the first pattern that matches
    
    if not recipe_files:
        # If no common patterns, look for the largest CSV or JSON file (likely the dataset)
        all_data_files = list(dataset_path.glob("*.csv")) + list(dataset_path.glob("*.json"))
        # Exclude files in subdirectories like 'code', 'model', 'ner', etc.
        all_data_files = [f for f in all_data_files if not any(
            x in f.parts for x in ['code', 'model', 'ner', 'vocab', 'test']
        )]
        if all_data_files:
            # Get the largest file (likely the main dataset)
            recipe_files = [max(all_data_files, key=lambda f: f.stat().st_size)]
    
    if not recipe_files:
        raise FileNotFoundError(
            f"Could not find recipe dataset in {dataset_path}. "
            f"Found files: {list(dataset_path.glob('*'))}"
        )
    
    logger.info(f"Found recipe data file: {recipe_files[0]}")
    
    # Load based on file extension
    data_file = recipe_files[0]
    if data_file.suffix == '.csv':
        # Load CSV file with pandas then convert to HF dataset
        import pandas as pd
        df = pd.read_csv(data_file)
        from datasets import Dataset
        hf_dataset = Dataset.from_pandas(df)
    elif data_file.suffix == '.json':
        hf_dataset = load_dataset("json", data_files=str(data_file), split="train")
    else:
        raise ValueError(f"Unsupported file format: {data_file.suffix}")
    
    logger.info(f"Dataset loaded successfully: {hf_dataset}")
    logger.info(f"Number of recipes: {len(hf_dataset)}")
    logger.info(f"Features: {hf_dataset.features}")
    
    return hf_dataset


def process_recipes(hf_dataset, limit: int = 0):
    """
    Convert HuggingFace dataset to list of recipe dictionaries
    
    Args:
        hf_dataset: HuggingFace dataset
        limit: Maximum number of recipes to process (0 = all)
    
    Returns:
        List of recipe dictionaries
    """
    logger.info("Converting recipes to structured format...")
    
    recipes = []
    dataset_size = len(hf_dataset)
    process_count = limit if limit > 0 else dataset_size
    
    logger.info(f"Processing {process_count} of {dataset_size} recipes...")
    
    for i, recipe in enumerate(hf_dataset):
        if limit > 0 and i >= limit:
            break
        
        # Convert to dictionary with unique ID
        processed_recipe = {
            "id": f"recipe_{i:07d}",
            "title": recipe.get("title", ""),
            "ingredients": recipe.get("ingredients", []),
            "directions": recipe.get("directions", ""),
            "ner": recipe.get("NER", []),
            "source": recipe.get("source", ""),
            "link": recipe.get("link", ""),
        }
        
        recipes.append(processed_recipe)
        
        if (i + 1) % 10000 == 0:
            logger.info(f"Processed {i + 1}/{process_count} recipes...")
    
    logger.info(f"Converted {len(recipes)} recipes successfully")
    return recipes


def generate_embeddings(recipes):
    """
    Generate embeddings for recipes using sentence-transformers
    
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
    
    # Prepare texts for embedding
    # Combine title, ingredients, and directions for semantic search
    texts = []
    for recipe in recipes:
        ingredients_str = " ".join(recipe["ingredients"])
        directions_str = recipe["directions"][:MAX_TEXT_LENGTH]
        text = f"{recipe['title']} {ingredients_str} {directions_str}"
        texts.append(text)
    
    # Generate embeddings in batches
    logger.info(f"Generating embeddings for {len(texts)} recipes on {device.upper()}...")
    embeddings = model.encode(
        texts,
        batch_size=EMBEDDING_BATCH_SIZE,
        show_progress_bar=True,
        convert_to_numpy=True
    )
    
    logger.info(f"Generated embeddings with shape: {embeddings.shape}")
    
    # Create metadata mapping (recipe_id -> index in FAISS)
    metadata = {
        recipe["id"]: i for i, recipe in enumerate(recipes)
    }
    
    return embeddings, metadata


def build_faiss_index(embeddings):
    """
    Build FAISS index for fast similarity search
    
    Args:
        embeddings: Numpy array of embeddings
    
    Returns:
        FAISS index object
    """
    logger.info("Building FAISS index...")
    
    # Get embedding dimension
    dim = embeddings.shape[1]
    logger.info(f"Creating FAISS index with dimension: {dim}")
    
    # Use IndexFlatL2 for exact nearest neighbor search
    # L2 distance (Euclidean) works well for sentence-transformer embeddings
    index = faiss.IndexFlatL2(dim)
    
    # Add embeddings to index
    logger.info(f"Adding {len(embeddings)} embeddings to index...")
    index.add(embeddings.astype('float32'))
    
    logger.info(f"FAISS index built successfully. Total vectors: {index.ntotal}")
    return index


def save_artifacts(recipes, embeddings, metadata, index):
    """
    Save processed recipes, embeddings, and FAISS index to storage
    
    Args:
        recipes: List of recipe dictionaries
        embeddings: Numpy array of embeddings (unused but kept for consistency)
        metadata: Metadata dictionary (recipe_id -> index mapping)
        index: FAISS index object
    """
    logger.info("Saving artifacts...")
    
    # Create output directory
    RECIPES_PROCESSED_DIR.mkdir(parents=True, exist_ok=True)
    
    # Save recipes as parquet
    logger.info("Saving recipes...")
    df = pd.DataFrame(recipes)
    recipes_path = RECIPES_PROCESSED_DIR / RECIPES_PARQUET
    df.to_parquet(recipes_path, index=False)
    logger.info(f"Saved {len(recipes)} recipes to {recipes_path}")
    
    # Save FAISS index
    logger.info("Saving FAISS index...")
    index_path = RECIPES_PROCESSED_DIR / EMBEDDINGS_FAISS
    faiss.write_index(index, str(index_path))
    logger.info(f"Saved FAISS index to {index_path}")
    
    # Save metadata (recipe_id -> index mapping for lookup)
    logger.info("Saving metadata...")
    metadata_path = RECIPES_PROCESSED_DIR / METADATA_JSON
    with open(metadata_path, 'w') as f:
        json.dump(metadata, f, indent=2)
    logger.info(f"Saved metadata to {metadata_path}")
    
    logger.info("All artifacts saved successfully!")


def main():
    """Main ingestion pipeline"""
    parser = argparse.ArgumentParser(description="Ingest RecipeNLG dataset")
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Limit number of recipes to process (0 = all)"
    )
    args = parser.parse_args()
    
    # Use environment-specific limit if not specified
    limit = args.limit if args.limit > 0 else DataConfig.RECIPE_LIMIT
    
    logger.info("=" * 60)
    logger.info("RecipeNLG Data Ingestion Pipeline")
    logger.info("=" * 60)
    logger.info(f"Environment: {ENV.value}")
    logger.info(f"Storage backend: {DataConfig.STORAGE_BACKEND}")
    logger.info(f"Recipe limit: {limit if limit > 0 else 'None (all recipes)'}")
    logger.info("=" * 60)
    
    try:
        # Step 1: Download dataset
        hf_dataset = download_recipenlg_dataset()
        
        # Step 2: Process recipes
        recipes = process_recipes(hf_dataset, limit=limit)
        
        # Step 3: Generate embeddings
        embeddings, metadata = generate_embeddings(recipes)
        
        # Step 4: Build FAISS index
        index = build_faiss_index(embeddings)
        
        # Step 5: Save artifacts
        save_artifacts(recipes, embeddings, metadata, index)
        
        logger.info("=" * 60)
        logger.info("Ingestion complete!")
        logger.info("=" * 60)
        
    except Exception as e:
        logger.error(f"Ingestion failed: {e}", exc_info=True)
        sys.exit(1)


if __name__ == "__main__":
    main()

