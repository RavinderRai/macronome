"""
Recipe Dataset Download Script

Downloads RecipeNLG dataset from Kaggle and saves to local storage and/or S3.

Usage:
    python -m macronome.data_engineering.data_ingestion.download_recipes [options]

Options:
    --limit LIMIT        Only process first LIMIT recipes (for testing)
    --no-local           Skip local storage (default: save to local)
    --no-s3              Skip S3 upload (default: upload to S3)

Default behavior: Saves to both local and S3
"""

import argparse
import logging
import sys
from pathlib import Path

import kagglehub
import pandas as pd
from datasets import Dataset, load_dataset

from macronome.data_engineering.config import (
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
    dataset_path_str = kagglehub.dataset_download(RECIPENLG_DATASET)
    dataset_path = Path(dataset_path_str)
    logger.info(f"Dataset downloaded to: {dataset_path}")
    
    # Find the main recipe dataset file
    recipe_files = []
    
    # Look for common recipe data file patterns
    for pattern in ["**/full_dataset.csv", "**/dataset.csv", "**/recipes.json", "**/*recipe*.csv"]:
        found = list(dataset_path.glob(pattern))
        if found:
            recipe_files.extend(found)
            break
    
    if not recipe_files:
        # If no common patterns, look for the largest CSV or JSON file
        all_data_files = list(dataset_path.glob("*.csv")) + list(dataset_path.glob("*.json"))
        all_data_files = [f for f in all_data_files if not any(
            x in f.parts for x in ['code', 'model', 'ner', 'vocab', 'test']
        )]
        if all_data_files:
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
        df = pd.read_csv(data_file)
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


def save_to_local(recipes):
    """
    Save recipes to local storage as parquet
    
    Args:
        recipes: List of recipe dictionaries
    """
    logger.info("Saving to local storage...")
    
    # Create output directory
    RECIPES_PROCESSED_DIR.mkdir(parents=True, exist_ok=True)
    
    # Save recipes as parquet
    df = pd.DataFrame(recipes)
    recipes_path = RECIPES_PROCESSED_DIR / RECIPES_PARQUET
    df.to_parquet(recipes_path, index=False)
    logger.info(f"Saved {len(recipes)} recipes to {recipes_path}")


def save_to_s3(recipes):
    """
    Upload recipes to S3 as parquet
    
    Args:
        recipes: List of recipe dictionaries
    """
    logger.info("Uploading to S3...")
    
    try:
        import boto3
        from io import BytesIO
        
        # Create DataFrame
        df = pd.DataFrame(recipes)
        
        # Save to bytes buffer
        buffer = BytesIO()
        df.to_parquet(buffer, index=False)
        buffer.seek(0)
        
        # Configure S3 client
        s3_config = {}
        if DataConfig.AWS_ACCESS_KEY_ID:
            s3_config['aws_access_key_id'] = DataConfig.AWS_ACCESS_KEY_ID
            s3_config['aws_secret_access_key'] = DataConfig.AWS_SECRET_ACCESS_KEY
        
        s3_client = boto3.client('s3', region_name=DataConfig.S3_REGION, **s3_config)
        
        # Upload to S3
        s3_key = f"{RECIPES_PARQUET}"
        s3_client.upload_fileobj(buffer, DataConfig.S3_BUCKET, s3_key)
        
        logger.info(f"Uploaded {len(recipes)} recipes to s3://{DataConfig.S3_BUCKET}/{s3_key}")
        
    except ImportError:
        logger.error("boto3 is not installed. Run: pip install boto3")
        raise
    except Exception as e:
        logger.error(f"Failed to upload to S3: {e}")
        raise


def main():
    """Main download pipeline"""
    parser = argparse.ArgumentParser(description="Download RecipeNLG dataset")
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Limit number of recipes to process (0 = all)"
    )
    parser.add_argument(
        "--no-local",
        action="store_true",
        help="Skip local storage (default: save to local)"
    )
    parser.add_argument(
        "--no-s3",
        action="store_true",
        help="Skip S3 upload (default: upload to S3)"
    )
    args = parser.parse_args()
    
    # Default to both, unless explicitly disabled
    save_local = not args.no_local
    save_s3 = not args.no_s3
    
    # Use environment-specific limit if not specified
    limit = args.limit if args.limit > 0 else DataConfig.RECIPE_LIMIT
    
    logger.info("=" * 60)
    logger.info("RecipeNLG Dataset Download")
    logger.info("=" * 60)
    logger.info(f"Environment: {ENV}")
    logger.info(f"Recipe limit: {limit if limit > 0 else 'None (all recipes)'}")
    logger.info(f"Save to local: {save_local}")
    logger.info(f"Upload to S3: {save_s3}")
    if save_s3:
        logger.info(f"S3 bucket: {DataConfig.S3_BUCKET}")
    logger.info("=" * 60)
    
    if not save_local and not save_s3:
        logger.error("Cannot disable both storage destinations. Remove --no-local or --no-s3.")
        sys.exit(1)
    
    try:
        # Step 1: Download dataset
        hf_dataset = download_recipenlg_dataset()
        
        # Step 2: Process recipes
        recipes = process_recipes(hf_dataset, limit=limit)
        
        # Step 3: Save to storage
        if save_local:
            save_to_local(recipes)
        
        if save_s3:
            save_to_s3(recipes)
        
        logger.info("=" * 60)
        logger.info("Download complete!")
        logger.info("=" * 60)
        
    except Exception as e:
        logger.error(f"Download failed: {e}", exc_info=True)
        sys.exit(1)


if __name__ == "__main__":
    main()

