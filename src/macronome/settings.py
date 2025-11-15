import os
from dotenv import load_dotenv

load_dotenv()

# Legacy (for backwards compatibility)
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
    S3_RECIPES_PREFIX = os.getenv("S3_RECIPES_PREFIX", "")  # Optional prefix for S3 keys
    
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


class BackendConfig:
    """Backend API configuration"""
    
    # Server config
    HOST = os.getenv("BACKEND_HOST", "0.0.0.0")
    PORT = int(os.getenv("BACKEND_PORT", "8000"))
    DEBUG = ENV == "dev"
    
    # CORS settings
    CORS_ORIGINS = os.getenv(
        "CORS_ORIGINS",
        "http://localhost:8081,http://localhost:19006,exp://192.168.*:8081"  # Expo dev
    ).split(",")
    
    # Supabase
    SUPABASE_URL = os.getenv("SUPABASE_URL", "")
    SUPABASE_KEY = os.getenv("SUPABASE_KEY", "")  # Anon/public key
    SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY", "")  # Service role key (admin)
    
    # Clerk authentication
    CLERK_PUBLISHABLE_KEY = os.getenv("CLERK_PUBLISHABLE_KEY", "")
    CLERK_SECRET_KEY = os.getenv("CLERK_SECRET_KEY", "")
    CLERK_JWT_VERIFICATION_KEY = os.getenv("CLERK_JWT_VERIFICATION_KEY", "")  # PEM public key
    
    # Redis
    REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
    REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
    REDIS_DB = int(os.getenv("REDIS_DB", "0"))
    REDIS_PASSWORD = os.getenv("REDIS_PASSWORD", "")
    REDIS_URL = os.getenv(
        "REDIS_URL",
        f"redis://:{REDIS_PASSWORD}@{REDIS_HOST}:{REDIS_PORT}/{REDIS_DB}" if REDIS_PASSWORD
        else f"redis://{REDIS_HOST}:{REDIS_PORT}/{REDIS_DB}"
    )
    
    # Celery
    CELERY_BROKER_URL = REDIS_URL
    CELERY_RESULT_BACKEND = REDIS_URL
    CELERY_TASK_TRACK_STARTED = True
    CELERY_TASK_TIME_LIMIT = 300  # 5 minutes max per task
    
    # LLM cache settings
    LLM_CACHE_TTL = int(os.getenv("LLM_CACHE_TTL", "3600"))  # 1 hour default
    
    # File upload settings
    MAX_UPLOAD_SIZE = int(os.getenv("MAX_UPLOAD_SIZE", "10485760"))  # 10MB default
    ALLOWED_IMAGE_TYPES = ["image/jpeg", "image/png", "image/jpg", "image/webp"]
    
    # Supabase Storage buckets
    PANTRY_IMAGES_BUCKET = os.getenv("PANTRY_IMAGES_BUCKET", "pantry-images")
    
    # Image storage backend (local = local filesystem, supabase = Supabase Storage)
    IMAGE_STORAGE_BACKEND = os.getenv("IMAGE_STORAGE_BACKEND", "local" if ENV == "dev" else "supabase")
