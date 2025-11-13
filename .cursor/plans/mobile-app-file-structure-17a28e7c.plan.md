<!-- 17a28e7c-1c7b-477f-9898-f0ecde17185b 0b1adbf4-97bb-4421-b39d-b5dc73a116dc -->
# 48-Hour MVP Sprint Plan

## Overview

Two-phase implementation plan for Macronome MVP:

- **Phase 1 (Today)**: Get app running locally with cloud services, production-ready architecture
- **Phase 2 (Tomorrow)**: Docker, monitoring, polish, and Play Store submission

**Goal:** Impressive MVP showcasing full-stack ML/AI capabilities with zero refactoring between phases

---

## Phase 1: Production-Ready Local Setup (Today)

**Timeline:** 12-18 hours
**Goal:** Fully functional app running locally, using cloud services, ready for deployment

---

### 1.1 Cloud Data Setup (2-3 hours)

**Objective:** Move recipe data and embeddings to cloud storage

**Tasks:**

- Set up S3 bucket for recipe dataset
- Set up Qdrant Cloud (free tier) collection
- Update data ingestion script:
- Upload recipe parquet to S3
- Upload embeddings to Qdrant (downsample to ~50K-100K recipes for free tier)
- Store Qdrant collection name/URL in config
- Refactor `RetrievalNode` to use Qdrant client instead of FAISS
- Test retrieval from Qdrant

**Files to Create/Update:**

- `src/macronome/data_engineering/data_ingestion/ingest_recipes.py` - Add S3/Qdrant upload
- `src/macronome/ai/workflows/meal_recommender_workflow_nodes/retrieval_node.py` - Qdrant integration
- `src/macronome/backend/config.py` - Add S3, Qdrant config

**Dependencies:**

- `qdrant-client`, `boto3`

---

### 1.2 Backend Foundation (3-4 hours)

**Objective:** FastAPI app with auth, database, and infrastructure

**Tasks:**

#### FastAPI App Structure

- `src/macronome/backend/__init__.py`
- `src/macronome/backend/app.py` - FastAPI app with CORS, middleware
- `src/macronome/backend/config.py` - Environment config (Supabase, Redis, S3, Qdrant, Clerk, API keys)
- Health check endpoint (`/health`)

#### Database Setup

- `src/macronome/backend/db/__init__.py`
- `src/macronome/backend/db/session.py` - Supabase client initialization
- `src/macronome/backend/db/models.py` - SQLAlchemy models:
- `pantry_items`: id, user_id (clerk_user_id), name, category, confirmed, image_url, created_at
- `meal_history`: id, user_id, meal_data (JSON), accepted, created_at
- `user_preferences`: id, user_id, dietary_restrictions (JSON), default_constraints (JSON)
- `src/macronome/backend/alembic.ini` - Alembic config
- `src/macronome/backend/alembic/env.py` - Alembic environment
- `src/macronome/backend/alembic/versions/001_initial_schema.py` - Initial migration

#### Auth Setup (Clerk + Supabase)

- `src/macronome/backend/auth/__init__.py`
- `src/macronome/backend/auth/middleware.py` - Clerk JWT verification middleware
- `src/macronome/backend/auth/clerk.py` - Clerk client setup
- Set up Supabase tables with `clerk_user_id` foreign key
- Clerk webhook or manual sync to create users in Supabase on first login

**Dependencies:**

- `fastapi`, `uvicorn[standard]`
- `supabase-py`
- `clerk-sdk-python` or `pyjwt` for Clerk verification
- `sqlalchemy`, `alembic`

---

### 1.3 Infrastructure Setup (2-3 hours)

**Objective:** Redis and Celery for async tasks and caching

#### Redis Setup

- `src/macronome/backend/cache.py` - Redis client and caching utilities
- LLM response cache: `cache_key = f"llm:{prompt_hash}"`, TTL 1 hour
- Simple cache decorator for expensive calls
- Connection pooling

#### Celery Setup

- `src/macronome/backend/worker.py` - Celery app configuration
- `src/macronome/backend/tasks/__init__.py`
- `src/macronome/backend/tasks/meal_recommendation.py` - Async meal recommendation task
- Celery app with Redis broker
- Task: `recommend_meal_async(request_data: dict) -> dict`
- Task stores result in Redis with task_id key
- Error handling and retry logic (max 2 retries)

**Dependencies:**

- `redis`, `celery`

---

### 1.4 Service Layer (2-3 hours)

**Objective:** Wrap ML workflows for backend use

**Files to Create:**

- `src/macronome/backend/services/__init__.py`
- `src/macronome/backend/services/pantry_scanner.py` - Wraps `PantryScannerWorkflow`
- Accept image upload
- Run workflow
- Return detected items
- `src/macronome/backend/services/meal_recommender.py` - Wraps `MealRecommendationWorkflow`
- Accept `MealRecommendationRequest`
- Queue Celery task
- Return task_id

**Implementation:**

- Both services handle errors and logging
- Image processing (resize, format conversion)
- Input validation

---

### 1.5 API Endpoints (2-3 hours)

**Objective:** FastAPI routers for all functionality

**Files to Create:**

- `src/macronome/backend/api/__init__.py`
- `src/macronome/backend/api/routers/__init__.py`
- `src/macronome/backend/api/routers/pantry.py` - Pantry endpoints
- `src/macronome/backend/api/routers/meals.py` - Meal recommendation endpoints
- `src/macronome/backend/api/schemas.py` - Pydantic request/response schemas

**Endpoints:**

**Pantry:**

- `POST /api/pantry/scan` - Upload image, return detected items (calls pantry scanner service)
- `POST /api/pantry/items` - Save pantry items to DB
- `GET /api/pantry/items` - Get user's pantry items
- `DELETE /api/pantry/items/{item_id}` - Delete pantry item

**Meals:**

- `POST /api/meals/recommend` - Request meal recommendation (async, returns task_id)
- `GET /api/meals/recommend/{task_id}` - Poll for recommendation result
- `POST /api/meals/history` - Save accepted meal to history

**All endpoints protected with Clerk auth middleware**

**Dependencies:**

- `python-multipart` (file uploads)

---

### 1.6 Cloud Storage Setup (1-2 hours)

**Objective:** S3 for recipe data, Supabase Storage for user images

**Files to Create:**

- `src/macronome/backend/storage/__init__.py`
- `src/macronome/backend/storage/s3.py` - S3 client wrapper (for recipe dataset)
- `src/macronome/backend/storage/supabase_storage.py` - Supabase Storage wrapper (for pantry images)

**Implementation:**

- S3: `upload_file()`, `download_file()` - for recipe artifacts
- Supabase Storage: `upload_image()`, `get_image_url()` - for pantry images
- Local fallback for dev (save to `data/uploads/`)

**Dependencies:**

- `boto3` (S3)
- `supabase-py` (already installed)

---

### 1.7 Frontend Integration (4-5 hours)

**Objective:** Connect mobile app to backend

#### API Client Setup

- `apps/mobile/src/services/api/client.ts` - HTTP client setup
- `apps/mobile/src/services/api/pantry.ts` - Pantry API calls
- `apps/mobile/src/services/api/meals.ts` - Meal recommendation API calls
- `apps/mobile/src/services/api/types.ts` - API response types

**Implementation:**

- Axios client with base URL from env
- Error handling wrapper
- Request/response interceptors
- Add Clerk auth token to all requests
- TypeScript types matching backend schemas

#### Clerk Auth in Mobile

- Install `@clerk/clerk-expo`
- Set up Clerk provider
- Sign up/sign in screens
- Store auth token
- Add token to API requests

#### Connect Services

- `apps/mobile/src/screens/CameraScreen.tsx` - Call `/api/pantry/scan` endpoint
- `apps/mobile/src/screens/HomeScreen.tsx` - Call `/api/meals/recommend` with polling
- `apps/mobile/src/components/pantry/PantryDrawer.tsx` - Fetch pantry items from API
- `apps/mobile/src/store/pantryStore.ts` - Sync with backend on add/remove

**Implementation:**

- Replace mock ML pipeline with real API calls
- Add loading states for async operations
- Poll Celery task status every 2 seconds
- Handle errors gracefully with user feedback

**Dependencies:**

- `axios` (if not already)
- `@clerk/clerk-expo`

---

### 1.8 Testing & Iteration (2-3 hours)

**Objective:** Verify everything works end-to-end

**Tasks:**

- Test full flow: auth → scan → recommend → save
- Test pantry scan with real images
- Test meal recommendation with real workflow
- Verify Celery async task completion
- Test error handling (invalid images, failed recommendations)
- Verify Redis caching works
- Test Clerk auth flow
- Fix any integration issues

---

## Phase 1 Success Criteria

✅ Recipe data and embeddings in cloud (S3 + Qdrant)
✅ RetrievalNode works with Qdrant
✅ FastAPI app running with Clerk auth
✅ Supabase database with tables and migrations
✅ Redis + Celery working for async tasks
✅ All API endpoints functional and protected
✅ Frontend connects to backend with auth
✅ Full end-to-end flow working locally
✅ No refactoring needed for Phase 2

---

## Phase 2: Deployment & Polish (Tomorrow)

**Timeline:** 8-12 hours
**Goal:** Docker setup, monitoring, polish, and Play Store submission

---

### 2.1 Docker Setup (2-3 hours)

**Objective:** Containerize for easy deployment

**Files to Create:**

- `docker-compose.yml` - Local development setup
- `Dockerfile.backend` - Backend API container
- `Dockerfile.celery` - Celery worker container
- `.dockerignore` - Exclude unnecessary files
- `.env.example` - Template for environment variables

**Services:**

- `backend` - FastAPI app (port 8000)
- `celery-worker` - Celery worker process
- `re