from celery import Celery
from macronome.settings import BackendConfig

def get_redis_url():
    return BackendConfig.REDIS_URL

def get_celery_config():
    """
    Get the Celery configuration

    Returns:
        dict: Celery configuration
    """
    redis_url = get_redis_url()
    return {
        'broker_url': redis_url,
        'result_backend': redis_url,
        'task_serializer': 'json',
        'accept_content': ['json'],
        'result_serializer': 'json',
        'enable_utc': True,
        'broker_connection_retry_on_startup': True,
    }

celery_app = Celery("tasks")
celery_app.config_from_object(get_celery_config())

# Automatically discover and register tasks
celery_app.autodiscover_tasks(["macronome.backend.worker"], force=True)