import os
from enum import Enum
from dotenv import load_dotenv

load_dotenv()

SUPABASE_PASSWORD = os.getenv("SUPABASE_PASSWORD")

# Current environment (checks ENV first, falls back to ENVIRONMENT for backwards compatibility)
ENV = os.getenv("ENV", "dev")


class DataConfig:
    """Data storage configuration"""
    
    # Storage backend (auto-detect from environment)
    STORAGE_BACKEND = os.getenv("STORAGE_BACKEND", "local" if ENV == "dev" else "s3")
    
    # Local paths (dev)
    LOCAL_DATA_DIR = "data"
    LOCAL_RECIPES_DIR = f"{LOCAL_DATA_DIR}/recipes"
    
    # Cloud paths (prod)
    S3_BUCKET = os.getenv("S3_BUCKET", "macronome-recipes")
    S3_REGION = os.getenv("AWS_REGION", "us-east-2")
    
    # AWS credentials (optional, will use default boto3 credential chain)
    AWS_ACCESS_KEY_ID = os.getenv("AWS_ACCESS_KEY_ID", "")
    AWS_SECRET_ACCESS_KEY = os.getenv("AWS_SECRET_ACCESS_KEY", "")
    
    # Qdrant vector database
    QDRANT_URL = os.getenv("QDRANT_URL", "")
    QDRANT_API_KEY = os.getenv("QDRANT_API_KEY", "")
    QDRANT_COLLECTION_NAME = os.getenv("QDRANT_COLLECTION_NAME", "recipes")
    
    # Vector database backend (local = FAISS, cloud = Qdrant)
    VECTOR_BACKEND = os.getenv("VECTOR_BACKEND", "local" if ENV == "dev" else "qdrant")
    
    # Dataset size limits (dev uses subset for speed)
    # 0 = no limit (use all data)
    RECIPE_LIMIT = int(os.getenv("RECIPE_LIMIT", "10000" if ENV == "dev" else "0"))
    
    # USDA FoodData Central API
    USDA_API_KEY = os.getenv("USDA_API_KEY", "")  # Required for nutrition data
    