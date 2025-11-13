<!-- 17a28e7c-1c7b-477f-9898-f0ecde17185b 0b1adbf4-97bb-4421-b39d-b5dc73a116dc -->
# 48-Hour MVP Sprint Plan

## Overview

Complete end-to-end implementation for Macronome MVP: backend API, infrastructure services, frontend integration, Docker containerization, and Play Store submission. Keep everything minimal but functional.

**Timeline:** 48-60 hours (Thursday-Saturday)

**Goal:** Impressive MVP showcasing full-stack ML/AI capabilities

---

## Phase 1: Backend API Foundation (6-8 hours)

### 1.1 FastAPI App Structure

**Files to Create:**

- `src/macronome/backend/__init__.py`
- `src/macronome/backend/app.py` - FastAPI app with CORS, middleware
- `src/macronome/backend/config.py` - Environment config (Supabase, Redis, S3, API keys)
- `src/macronome/backend/db/__init__.py`
- `src/macronome/backend/db/session.py` - Supabase client initialization
- `src/macronome/backend/db/models.py` - SQLAlchemy models (pantry_items, meal_history, user_preferences)

**Implementation:**

- FastAPI app with CORS enabled for mobile
- Health check endpoint (`/health`)
- Basic error handling middleware
- Supabase client connection (using `supabase-py`)
- SQLAlchemy models for core tables (minimal schema)

### 1.2 API Routers

**Files to Create:**

- `src/macronome/backend/api/__init__.py`
- `src/macronome/backend/api/routers/__init__.py`
- `src/macronome/backend/api/routers/pantry.py` - Pantry endpoints
- `src/macronome/backend/api/routers/meals.py` - Meal recommendation endpoints
- `src/macronome/backend/api/schemas.py` - Pydantic request/response schemas

**Endpoints:**

- `POST /api/pantry/scan` - Upload image, return detected items (calls pantry scanner service)
- `POST /api/pantry/items` - Save pantry items to DB
- `GET /api/pantry/items` - Get user's pantry items
- `DELETE /api/pantry/items/{item_id}` - Delete pantry item
- `POST /api/meals/recommend` - Request meal recommendation (async, returns task_id)
- `GET /api/meals/recommend/{task_id}` - Poll for recommendation result
- `POST /api/meals/history` - Save accepted meal to history

### 1.3 Service Layer

**Files to Create:**

- `src/macronome/backend/services/__init__.py`
- `src/macronome/backend/services/pantry_scanner.py` - Wraps `PantryDetector` class
- `src/macronome/backend/services/meal_recommender.py` - Wraps `MealRecommendationWorkflow`

**Implementation:**

- `pantry_scanner.py`: Load image, call `PantryDetector.detect()`, return `List[PantryItem]`
- `meal_recommender.py`: Accept `MealRecommendationRequest`, run workflow, return result
- Both services handle errors and logging

---

## Phase 2: Infrastructure Setup (4-5 hours)

### 2.1 Redis Setup

**Files to Create:**

- `src/macronome/backend/cache.py` - Redis client and caching utilities

**Implementation:**

- Redis connection (using `redis` package)
- LLM response cache: `cache_key = f"llm:{prompt_hash}"`, TTL 1 hour
- Simple cache decorator for expensive calls
- Connection pooling

### 2.2 Celery Setup

**Files to Create:**

- `src/macronome/backend/worker.py` - Celery app configuration
- `src/macronome/backend/tasks/__init__.py`
- `src/macronome/backend/tasks/meal_recommendation.py` - Async meal recommendation task

**Implementation:**

- Celery app with Redis broker
- Single task: `recommend_meal_async(request_data: dict) -> dict`
- Task stores result in Redis with task_id key
- Returns task_id immediately, frontend polls for result
- Error handling and retry logic (max 2 retries)

### 2.3 Database Migrations

**Files to Create:**

- `src/macronome/backend/alembic.ini` - Alembic config
- `src/macronome/backend/alembic/env.py` - Alembic environment
- `src/macronome/backend/alembic/versions/001_initial_schema.py` - Initial migration

**Schema:**

- `pantry_items`: id, user_id, name, category, confirmed, image_url, created_at
- `meal_history`: id, user_id, meal_data (JSON), accepted, created_at
- `user_preferences`: id, user_id, dietary_restrictions (JSON), default_constraints (JSON)

---

## Phase 3: Cloud Storage & Monitoring (3-4 hours)

### 3.1 S3 Integration

**Files to Create:**

- `src/macronome/backend/storage/__init__.py`
- `src/macronome/backend/storage/s3.py` - S3 client wrapper

**Implementation:**

- `upload_image(file_bytes, filename) -> str` (returns S3 URL)
- `download_file(key) -> bytes`
- Uses `boto3` with environment variables for credentials
- Local fallback for dev (save to `data/uploads/`)

### 3.2 Prometheus Metrics

**Files to Create:**

- `src/macronome/backend/metrics.py` - Prometheus metrics

**Metrics:**

- `http_requests_total` (counter)
- `http_request_duration_seconds` (histogram)
- `llm_tokens_total` (counter)
- `celery_tasks_total` (counter)

**Implementation:**

- Use `prometheus_client` package
- Expose `/metrics` endpoint
- Basic instrumentation on API routes

### 3.3 Grafana Dashboard

**Files to Create:**

- `grafana/dashboards/api.json` - Single dashboard config

**Dashboard Panels:**

- API request rate (graph)
- Average latency (graph)
- LLM token usage (counter)
- Celery queue depth (gauge)

---

## Phase 4: Frontend Integration (6-8 hours)

### 4.1 API Client

**Files to Update:**

- `apps/mobile/src/services/api/client.ts` - HTTP client setup
- `apps/mobile/src/services/api/pantry.ts` - Pantry API calls
- `apps/mobile/src/services/api/meals.ts` - Meal recommendation API calls
- `apps/mobile/src/services/api/types.ts` - API response types

**Implementation:**

- Axios client with base URL from env
- Error handling wrapper
- Request/response interceptors
- TypeScript types matching backend schemas

### 4.2 Connect Services

**Files to Update:**

- `apps/mobile/src/screens/CameraScreen.tsx` - Call `/api/pantry/scan` endpoint
- `apps/mobile/src/screens/HomeScreen.tsx` - Call `/api/meals/recommend` with polling
- `apps/mobile/src/components/pantry/PantryDrawer.tsx` - Fetch pantry items from API
- `apps/mobile/src/store/pantryStore.ts` - Sync with backend on add/remove

**Implementation:**

- Replace mock ML pipeline with real API calls
- Add loading states for async operations
- Poll Celery task status every 2 seconds
- Handle errors gracefully with user feedback

---

## Phase 5: Docker Setup (3-4 hours)

### 5.1 Docker Compose

**Files to Create:**

- `docker-compose.yml` - Local development setup

**Services:**

- `backend` - FastAPI app (port 8000)
- `celery-worker` - Celery worker process
- `redis` - Redis cache/broker (port 6379)
- `prometheus` - Prometheus server (port 9090)
- `grafana` - Grafana dashboard (port 3000)

**Volumes:**

- `./data` - Local data storage
- `./grafana/dashboards` - Grafana dashboard configs

### 5.2 Dockerfiles

**Files to Create:**

- `Dockerfile.backend` - Backend API container
- `Dockerfile.celery` - Celery worker container
- `.dockerignore` - Exclude unnecessary files

**Implementation:**

- Multi-stage builds for optimization
- Install Python dependencies from `pyproject.toml`
- Copy only necessary source files
- Set working directory and entrypoints

### 5.3 Environment Configuration

**Files to Create:**

- `.env.example` - Template for environment variables
- `docker-compose.override.yml.example` - Local overrides template

**Variables:**

- `SUPABASE_URL`, `SUPABASE_KEY`
- `REDIS_URL`
- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `S3_BUCKET`
- `OPENAI_API_KEY`, `USDA_API_KEY`
- `ENVIRONMENT` (dev/prod)

---

## Phase 6: Testing & Polish (4-5 hours)

### 6.1 Integration Testing

**Tasks:**

- Test pantry scan flow end-to-end
- Test meal recommendation with real workflow
- Verify Celery async task completion
- Test error handling (invalid images, failed recommendations)
- Verify Redis caching works

### 6.2 Frontend Polish

**Updates:**

- Add proper loading indicators
- Improve error messages
- Add retry logic for failed API calls
- Optimize image upload size
- Add basic offline handling

### 6.3 Performance Tuning

**Optimizations:**

- Enable response compression
- Add request timeouts
- Optimize image processing (resize before upload)
- Cache FAISS index loading
- Reduce LLM calls where possible

---

## Phase 7: Build & Deployment Prep (4-6 hours)

### 7.1 Android Build

**Tasks:**

- Configure `app.json` for Android
- Set up signing keys
- Test build locally with `eas build --platform android`
- Fix any build errors

### 7.2 Store Assets

**Files to Create:**

- `apps/mobile/assets/store/icon.png` - App icon (1024x1024)
- `apps/mobile/assets/store/splash.png` - Splash screen
- `apps/mobile/assets/store/feature-graphic.png` - Play Store feature graphic

### 7.3 Store Listing

**Content:**

- App name: "Macronome"
- Short description: "AI-powered meal recommendations based on your pantry and dietary goals"
- Full description: Detailed feature list
- Screenshots (from simulator)
- Privacy policy URL (placeholder for now)

### 7.4 Final Testing

**Checklist:**

- Test on physical Android device
- Verify all API endpoints work
- Test camera functionality
- Verify meal recommendations display correctly
- Check error handling

---

## File Structure Summary

```
src/macronome/backend/
├── __init__.py
├── app.py                      # FastAPI app
├── config.py                   # Environment config
├── worker.py                   # Celery app
├── cache.py                    # Redis cache
├── metrics.py                  # Prometheus metrics
├── api/
│   ├── __init__.py
│   ├── routers/
│   │   ├── __init__.py
│   │   ├── pantry.py
│   │   └── meals.py
│   └── schemas.py
├── services/
│   ├── __init__.py
│   ├── pantry_scanner.py
│   └── meal_recommender.py
├── tasks/
│   ├── __init__.py
│   └── meal_recommendation.py
├── storage/
│   ├── __init__.py
│   └── s3.py
├── db/
│   ├── __init__.py
│   ├── session.py
│   └── models.py
└── alembic/
    ├── env.py
    └── versions/
        └── 001_initial_schema.py

docker-compose.yml
Dockerfile.backend
Dockerfile.celery
.env.example

grafana/
└── dashboards/
    └── api.json

apps/mobile/src/services/api/
├── client.ts
├── pantry.ts
├── meals.ts
└── types.ts
```

---

## Dependencies to Add

**Backend (`pyproject.toml`):**

- `fastapi`, `uvicorn[standard]`
- `supabase-py`
- `redis`, `celery`
- `boto3` (S3)
- `prometheus-client`
- `sqlalchemy`, `alembic`
- `python-multipart` (file uploads)

**Frontend (`apps/mobile/package.json`):**

- `axios` (if not already)

---

## Success Criteria

✅ Backend API serves pantry scan and meal recommendation endpoints

✅ Celery handles async meal recommendations

✅ Redis caches LLM responses

✅ Frontend connects to backend and displays real data

✅ Docker Compose runs all services locally

✅ Prometheus metrics are collected

✅ Grafana dashboard displays basic metrics

✅ Android build succeeds

✅ App can be submitted to Play Store

---

## Time Estimates

- Phase 1 (Backend API): 6-8 hours
- Phase 2 (Infrastructure): 4-5 hours
- Phase 3 (Cloud & Monitoring): 3-4 hours
- Phase 4 (Frontend Integration): 6-8 hours
- Phase 5 (Docker): 3-4 hours
- Phase 6 (Testing & Polish): 4-5 hours
- Phase 7 (Build & Deploy): 4-6 hours

**Total: 30-40 hours of focused work**

---

## Notes

- Keep implementations minimal but functional
- Use existing ML workflows (`MealRecommendationWorkflow`, `PantryDetector`) - no refactoring needed
- Prioritize core functionality over edge cases
- Accept technical debt for speed (document TODOs)
- Test incrementally as you build
- Docker setup enables easy local development and future deployment