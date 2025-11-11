import os
from enum import Enum
from dotenv import load_dotenv

load_dotenv()

# Legacy settings
SUPABASE_PASSWORD = os.getenv("SUPABASE_PASSWORD")


class Environment(str, Enum):
    """Environment configuration"""
    DEV = "dev"
    PROD = "prod"


# Current environment
ENV = Environment(os.getenv("ENVIRONMENT", "dev"))


class DataConfig:
    """Data storage configuration"""
    
    # Storage backend (auto-detect from environment)
    STORAGE_BACKEND = os.getenv("STORAGE_BACKEND", "local" if ENV == Environment.DEV else "s3")
    
    # Local paths (dev)
    LOCAL_DATA_DIR = "data"
    LOCAL_RECIPES_DIR = f"{LOCAL_DATA_DIR}/recipes"
    
    # Cloud paths (prod)
    S3_BUCKET = os.getenv("S3_BUCKET", "macronome-prod")
    S3_RECIPES_PREFIX = "recipes/"
    
    # Dataset size limits (dev uses subset for speed)
    # 0 = no limit (use all data)
    RECIPE_LIMIT = int(os.getenv("RECIPE_LIMIT", "10000" if ENV == Environment.DEV else "0"))
    
    # USDA FoodData Central API
    USDA_API_KEY = os.getenv("USDA_API_KEY", "")  # Required for nutrition data
    