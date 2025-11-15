"""
Celery worker module
"""
from macronome.backend.worker.config import celery_app
from macronome.backend.worker.tasks import recommend_meal_async

__all__ = ["celery_app", "recommend_meal_async"]

