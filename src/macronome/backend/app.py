from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import logging

from macronome.settings import BackendConfig, ENV

# Configure logging
logging.basicConfig(
    level=logging.DEBUG if BackendConfig.DEBUG else logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Create FastAPI app
app = FastAPI(
    title="Macronome API",
    description="Meal recommendation and pantry scanning API",
    version="0.1.0",
    docs_url="/docs" if BackendConfig.DEBUG else None,  # Disable docs in prod
    redoc_url="/redoc" if BackendConfig.DEBUG else None,
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=BackendConfig.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "service": "macronome-api",
        "version": "0.1.0",
        "environment": ENV,
        "endpoints": {
            "/health": "Health check",
            "/docs": "API documentation (dev only)" if BackendConfig.DEBUG else None,
        }
    }


@app.get("/health")
async def health_check():
    """Health check endpoint for monitoring"""
    # TODO: Add checks for:
    # - Redis connection
    # - Supabase connection
    # - Qdrant connection
    # - Celery worker status
    
    return JSONResponse(
        status_code=200,
        content={
            "status": "healthy",
            "environment": ENV,
            "services": {
                "api": "up",
                "redis": "TODO",  # Add Redis ping
                "database": "TODO",  # Add Supabase check
                "vector_db": "TODO",  # Add Qdrant check
                "worker": "TODO",  # Add Celery check
            }
        }
    )


# Startup event
@app.on_event("startup")
async def startup_event():
    """Initialize services on startup"""
    logger.info(f"🚀 Starting Macronome API in {ENV} mode")
    logger.info(f"📍 CORS origins: {BackendConfig.CORS_ORIGINS}")
    
    # TODO: Initialize connections
    # - Redis connection pool
    # - Supabase client
    # - Load ML models if needed


# Shutdown event
@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup on shutdown"""
    logger.info("👋 Shutting down Macronome API")
    
    # TODO: Cleanup connections
    # - Close Redis pool
    # - Close database connections


# Import and register routers (after app creation to avoid circular imports)
# TODO: Uncomment once routers are created
# from macronome.backend.api.routers import pantry, meals
# app.include_router(pantry.router, prefix="/api/pantry", tags=["pantry"])
# app.include_router(meals.router, prefix="/api/meals", tags=["meals"])


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "macronome.backend.app:app",
        host=BackendConfig.HOST,
        port=BackendConfig.PORT,
        reload=BackendConfig.DEBUG,
    )

