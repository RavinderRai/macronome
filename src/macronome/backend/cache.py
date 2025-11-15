"""
Redis Cache Module

Provides Redis connection and caching utilities for:
- LLM response caching
- Session storage
- General purpose caching
"""
import hashlib
import json
import logging
from functools import wraps
from typing import Any, Optional, Callable

import redis
from macronome.settings import BackendConfig

logger = logging.getLogger(__name__)


class RedisCache:
    """Redis cache client with connection pooling"""
    
    _instance: Optional[redis.Redis] = None
    
    @classmethod
    def get_client(cls) -> redis.Redis:
        """
        Get Redis client (singleton with connection pooling)
        
        Returns:
            Redis client instance
        """
        if cls._instance is None:
            try:
                cls._instance = redis.from_url(
                    BackendConfig.REDIS_URL,
                    decode_responses=True,
                    socket_connect_timeout=5,
                    socket_keepalive=True,
                    health_check_interval=30
                )
                # Test connection
                cls._instance.ping()
                logger.info("✅ Redis connection established")
            except Exception as e:
                logger.error(f"❌ Failed to connect to Redis: {e}")
                raise
        
        return cls._instance
    
    @classmethod
    def health_check(cls) -> bool:
        """
        Check Redis connection health
        
        Returns:
            True if Redis is reachable, False otherwise
        """
        try:
            client = cls.get_client()
            return client.ping()
        except Exception as e:
            logger.error(f"Redis health check failed: {e}")
            return False


def cache_llm_response(ttl: int = None) -> Callable:
    """
    Decorator to cache LLM responses in Redis
    
    Args:
        ttl: Time to live in seconds (default: from BackendConfig.LLM_CACHE_TTL)
    
    Usage:
        @cache_llm_response(ttl=3600)
        async def get_llm_response(prompt: str) -> str:
            return await llm_call(prompt)
    """
    if ttl is None:
        ttl = BackendConfig.LLM_CACHE_TTL
    
    def decorator(func: Callable) -> Callable:
        @wraps(func)
        async def wrapper(*args, **kwargs):
            # Generate cache key from function name and arguments
            key_data = {
                "func": func.__name__,
                "args": args,
                "kwargs": kwargs
            }
            key_hash = hashlib.sha256(
                json.dumps(key_data, sort_keys=True, default=str).encode()
            ).hexdigest()
            cache_key = f"llm:{key_hash}"
            
            # Try to get from cache
            redis_client = RedisCache.get_client()
            try:
                cached_value = redis_client.get(cache_key)
                if cached_value:
                    logger.debug(f"Cache hit for {func.__name__}")
                    return json.loads(cached_value)
            except Exception as e:
                logger.warning(f"Cache read error: {e}")
            
            # Cache miss - call function
            logger.debug(f"Cache miss for {func.__name__}")
            result = await func(*args, **kwargs)
            
            # Store in cache
            try:
                redis_client.setex(
                    cache_key,
                    ttl,
                    json.dumps(result, default=str)
                )
            except Exception as e:
                logger.warning(f"Cache write error: {e}")
            
            return result
        
        return wrapper
    return decorator


def cache_set(key: str, value: Any, ttl: int = 3600) -> bool:
    """
    Set a value in Redis cache
    
    Args:
        key: Cache key
        value: Value to cache (will be JSON serialized)
        ttl: Time to live in seconds
    
    Returns:
        True if successful, False otherwise
    """
    try:
        redis_client = RedisCache.get_client()
        redis_client.setex(
            key,
            ttl,
            json.dumps(value, default=str)
        )
        return True
    except Exception as e:
        logger.error(f"Cache set error for key {key}: {e}")
        return False


def cache_get(key: str) -> Optional[Any]:
    """
    Get a value from Redis cache
    
    Args:
        key: Cache key
    
    Returns:
        Cached value if exists, None otherwise
    """
    try:
        redis_client = RedisCache.get_client()
        value = redis_client.get(key)
        if value:
            return json.loads(value)
        return None
    except Exception as e:
        logger.error(f"Cache get error for key {key}: {e}")
        return None


def cache_delete(key: str) -> bool:
    """
    Delete a value from Redis cache
    
    Args:
        key: Cache key
    
    Returns:
        True if successful, False otherwise
    """
    try:
        redis_client = RedisCache.get_client()
        redis_client.delete(key)
        return True
    except Exception as e:
        logger.error(f"Cache delete error for key {key}: {e}")
        return False


def cache_clear_pattern(pattern: str) -> int:
    """
    Clear all keys matching a pattern
    
    Args:
        pattern: Redis key pattern (e.g., "llm:*", "user:123:*")
    
    Returns:
        Number of keys deleted
    """
    try:
        redis_client = RedisCache.get_client()
        keys = redis_client.keys(pattern)
        if keys:
            return redis_client.delete(*keys)
        return 0
    except Exception as e:
        logger.error(f"Cache clear error for pattern {pattern}: {e}")
        return 0

