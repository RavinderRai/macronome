<!-- 17a28e7c-1c7b-477f-9898-f0ecde17185b 0b1adbf4-97bb-4421-b39d-b5dc73a116dc -->
# 48-Hour MVP Sprint Plan (Updated)

## Overview

Two-phase implementation plan for Macronome MVP:

- **Phase 1 (Today)**: Get app running locally with cloud services, production-ready architecture
- **Phase 2 (Tomorrow)**: Docker, monitoring, polish, and Play Store submission

**Goal:** Impressive MVP showcasing full-stack ML/AI capabilities with zero refactoring between phases

**Current Status:**

- ✅ 1.1 Cloud Data Setup - Complete (S3, Qdrant, RetrievalNode)
- ✅ 1.2 Backend Foundation - Complete (FastAPI app, auth, database models, SQL schema)
- ⏳ Next: Infrastructure, Services, API Endpoints, Chat Workflow, Frontend Integration

---

## Phase 1: Production-Ready Local Setup (Today)

**Timeline:** 12-18 hours

**Goal:** Fully functional app running locally, using cloud services, ready for deployment

---

### 1.1 Cloud Data Setup ✅ COMPLETE

**Status:** Done

- S3 bucket configured for recipe dataset
- Qdrant Cloud collection set up with INT8 quantization
- Data ingestion scripts updated (download_recipes.py, generate_embeddings.py)
- RetrievalNode refactored to use Qdrant with S3 recipe lookup
- 1M recipes sampled and embedded in Qdrant

---

### 1.2 Backend Foundation ✅ COMPLETE

**Status:** Done

- FastAPI app structure (`backend/app.py`)
- Database models aligned with frontend types (`backend/db/models.py`)
- SQL schema created and ready for Supabase
- Clerk authentication setup (`backend/auth/`)
- Supabase client initialization (`backend/db/session.py`)
- Chat session helpers (`backend/db/chat_helpers.py`)
- All config centralized in `settings.py`

**Database Tables:**

- `pantry_images` - Uploaded images
- `pantry_items` - Detected/manual items (FK to images)
- `user_preferences` - Global user preferences (needs update for custom constraints)
- `chat_sessions` - Conversation sessions (one active per user)
- `chat_messages` - Message history
- `meal_recommendations` - Recommended meals

---

### 1.3 Infrastructure Setup (2-3 hours)

**Objective:** Redis and Celery for async tasks and caching

#### Redis Setup

**Files to Create:**

- `src/macronome/backend/cache.py` - Redis client and caching utilities

**Implementation:**

- Redis connection pool with `redis-py`
- LLM response cache: `cache_key = f"llm:{prompt_hash}"`, TTL from `BackendConfig.LLM_CACHE_TTL`
- Simple cache decorator for expensive calls
- Connection health check for `/health` endpoint

#### Celery Setup

**Files to Create:**

- `src/macronome/backend/worker.py` - Celery app configuration
- `src/macronome/backend/tasks/__init__.py`
- `src/macronome/backend/tasks/meal_recommendation.py` - Async meal recommendation task

**Implementation:**

- Celery app with Redis broker (`BackendConfig.CELERY_BROKER_URL`)
- Task: `recommend_meal_async(request_data: dict) -> dict`
- Task stores result in Redis with `task_id` key
- Error handling and retry logic (max 2 retries)
- Task time limit: 5 minutes

**Dependencies:**

- `redis`, `celery`

---

### 1.4 Update User Preferences Model (30 min)

**Objective:** Update `user_preferences` table to store custom constraints

**Files to Update:**

- `src/macronome/backend/db/models.py` - Update `UserPreferences` model
- Add SQL migration for `user_preferences` table

**Changes:**

- Add `custom_constraints` JSONB field to store LLM-parsed custom constraints
- Update Pydantic model to include `custom_constraints: Dict[str, Any]`
- Update SQL schema in `models.py`

**Note:** All constraints (preset and custom) live in `user_preferences`, not `chat_sessions.filters`

---

### 1.5 Cloud Storage Setup (1-2 hours)

**Objective:** Supabase Storage for user images

**Files to Create:**

- `src/macronome/backend/storage/__init__.py`
- `src/macronome/backend/storage/supabase_storage.py` - Supabase Storage wrapper

**Implementation:**

- `upload_image(user_id: str, image_bytes: bytes, filename: str) -> str` - Returns storage URL
- `get_image_url(bucket: str, path: str) -> str` - Get public URL
- `delete_image(bucket: str, path: str)` - Delete image
- Local fallback for dev (save to `data/uploads/`)
- Use `BackendConfig.PANTRY_IMAGES_BUCKET`

**Dependencies:**

- `supabase-py` (already installed)

---

### 1.6 Service Layer (2-3 hours)

**Objective:** Wrap ML workflows for backend use

**Files to Create:**

- `src/macronome/backend/services/__init__.py`
- `src/macronome/backend/services/pantry_scanner.py` - Wraps `PantryScannerWorkflow`
- `src/macronome/backend/services/meal_recommender.py` - Wraps `MealRecommendationWorkflow`

#### Pantry Scanner Service

**Implementation:**

- Accept image upload (bytes or PIL Image)
- Image processing (resize, format conversion)
- Run `PantryScannerWorkflow` with `PantryScanRequest`
- Return detected items as list of `PantryItem` dicts
- Error handling and logging

#### Meal Recommender Service

**Implementation:**

- Accept `MealRecommendationRequest` (constraints, pantry items, chat context)
- Queue Celery task: `recommend_meal_async`
- Return `task_id` for polling
- Error handling and input validation

**Dependencies:**

- Import workflows from `macronome.ai.workflows`

---

### 1.7 Chat Workflow (3-4 hours)

**Objective:** Create AI workflow for chat that routes user messages to appropriate actions

**Files to Create:**

- `src/macronome/ai/workflows/chat_workflow.py` - Main chat workflow
- `src/macronome/ai/workflows/chat_workflow_nodes/__init__.py`
- `src/macronome/ai/workflows/chat_workflow_nodes/chat_router.py` - Router node (AgentNode)
- `src/macronome/ai/workflows/chat_workflow_nodes/constraint_parser.py` - Constraint parsing node (AgentNode)
- `src/macronome/ai/schemas/chat_schema.py` - Chat request/response schemas

#### Chat Router Node

**Purpose:** Decide action based on user message (don't parse if nothing to parse)

**Actions:**

1. **Add Constraint** - User mentions constraint (preset or custom)
2. **Start Meal Recommendation** - User asks for meal recommendation
3. **General Chat** - User has question, confusion, or general conversation

**Output Schema:**

```python
class ChatAction(str, Enum):
    ADD_CONSTRAINT = "add_constraint"
    START_RECOMMENDATION = "start_recommendation"
    GENERAL_CHAT = "general_chat"

class ChatRouterOutput(BaseModel):
    action: ChatAction
    confidence: float
    reasoning: str
    # If ADD_CONSTRAINT:
    constraint_type: Optional[str]  # "preset" or "custom"
    constraint_data: Optional[Dict[str, Any]]
```

#### Constraint Parser Node

**Purpose:** Parse constraint from user message (only called if router decides ADD_CONSTRAINT)

**Implementation:**

- Extract constraint details (calories, macros, diet, custom constraints)
- Return structured constraint data
- Update `user_preferences.custom_constraints` via backend service

#### Chat Workflow Structure

**Simple 2-node workflow:**

1. **ChatRouter** (AgentNode) - Routes to action
2. **ConstraintParser** (AgentNode) - Only called if action is ADD_CONSTRAINT

**Flow:**

- Router decides action
- If ADD_CONSTRAINT → Call ConstraintParser → Update user_preferences → Return confirmation
- If START_RECOMMENDATION → Return signal to trigger meal recommendation workflow (async)
- If GENERAL_CHAT → Return helpful response

**Streaming:**

- Chat workflow responses should stream text as they generate
- Use FastAPI StreamingResponse for SSE (Server-Sent Events)

#### Integration Points

**Backend Service:**

- `src/macronome/backend/services/chat.py` - Wraps ChatWorkflow
- Handles streaming responses
- Updates user_preferences when constraints added
- Triggers meal recommendation workflow (returns task_id)

**Chat Schema:**

```python
class ChatRequest(BaseModel):
    message: str
    chat_session_id: str
    user_id: str
    pantry_items: List[PantryItem]  # Current pantry state
    user_preferences: UserPreferences  # Current preferences

class ChatResponse(BaseModel):
    response: str  # Streamed text
    action: Optional[ChatAction]
    task_id: Optional[str]  # If START_RECOMMENDATION
```

---

### 1.8 API Endpoints (3-4 hours)

**Objective:** FastAPI routers split into AI endpoints and backend CRUD

**Files to Create:**

- `src/macronome/backend/api/__init__.py`
- `src/macronome/backend/api/routers/__init__.py`
- `src/macronome/backend/api/routers/ai/__init__.py`
- `src/macronome/backend/api/routers/ai/pantry.py` - AI pantry scanning
- `src/macronome/backend/api/routers/ai/meals.py` - AI meal recommendation
- `src/macronome/backend/api/routers/ai/chat.py` - AI chat workflow (streaming)
- `src/macronome/backend/api/routers/pantry.py` - Pantry CRUD
- `src/macronome/backend/api/routers/chat.py` - Chat session/message CRUD
- `src/macronome/backend/api/routers/meals.py` - Meal history CRUD
- `src/macronome/backend/api/routers/preferences.py` - User preferences CRUD
- `src/macronome/backend/api/schemas.py` - Pydantic request/response schemas

#### AI Endpoints (`/api/ai/`)

**Pantry:**

- `POST /api/ai/pantry/scan` - Upload image, return detected items
    - Calls `pantry_scanner` service
    - Returns list of `PantryItem`

**Meals:**

- `POST /api/ai/meals/recommend` - Request meal recommendation (async)
    - Calls `meal_recommender` service
    - Returns `task_id`
- `GET /api/ai/meals/recommend/{task_id}` - Poll for recommendation result
    - Returns meal data or status

**Chat:**

- `POST /api/ai/chat/message` - Send chat message (streaming)
    - Calls `chat` service
    - Returns SSE stream with response text
    - If action is START_RECOMMENDATION, includes `task_id` in final message

#### Backend CRUD Endpoints (`/api/`)

**Pantry:**

- `GET /api/pantry/items` - Get user's pantry items
- `POST /api/pantry/items` - Save pantry items to DB
- `DELETE /api/pantry/items/{item_id}` - Delete pantry item
- `POST /api/pantry/images` - Upload image, return image_id

**Chat:**

- `GET /api/chat/sessions` - Get user's chat sessions
- `POST /api/chat/sessions` - Create new chat session (deactivates old)
- `GET /api/chat/sessions/{session_id}/messages` - Get messages for session
- `POST /api/chat/sessions/{session_id}/messages` - Add message (manual, for history)

**Meals:**

- `GET /api/meals/history` - Get meal recommendation history
- `POST /api/meals/history` - Save accepted meal
- `PUT /api/meals/history/{id}/rating` - Update meal rating

**Preferences:**

- `GET /api/preferences` - Get user preferences
- `PUT /api/preferences` - Update user preferences

**All endpoints protected with Clerk auth middleware**

**Dependencies:**

- `python-multipart` (file uploads)
- `sse-starlette` (Server-Sent Events for streaming)

---



### 1.9 Frontend Integration (4-5 hours)



1.9.1 Clerk Auth Setup (1 hour)

 - Install @clerk/clerk-expo, expo-secure-store

 - Set up Clerk provider in App.tsx

 - Create AuthContext with token management

 - Create sign in/up screens

 - Store token in secure storage

 - Add token refresh logic



1.9.2 Clerk → Supabase Sync (30 min)

 - Backend: POST /api/auth/sync endpoint

 - Frontend: Call sync after Clerk sign-in

 - Handle user creation/update



1.9.3 API Client Setup (1 hour)

 - Create axios client with interceptors

 - Add auth token to all requests

 - Error handling (401, 500, network)

 - Request/response logging (dev only)

 - TypeScript types matching backend schemas



1.9.4 API Service Files (1 hour)

 - services/api/ai/pantry.ts

 - services/api/ai/meals.ts

 - services/api/ai/chat.ts (with streaming)

 - services/api/pantry.ts

 - services/api/chat.ts

 - services/api/meals.ts

 - services/api/preferences.ts

 - services/api/types.ts



1.9.5 Connect Screens (1 hour)

 - CameraScreen: Replace mock with /api/ai/pantry/scan

 - HomeScreen: Chat API integration, meal polling

 - PantryDrawer: Fetch from /api/pantry/items

 - Sync pantry store with backend

 - Load preferences on app start



1.9.6 Chat Integration (1 hour)

 - ChatInterface: Connect to /api/ai/chat/message

 - Streaming support (EventSource or fetch streaming)

 - Handle START_RECOMMENDATION action

 - Poll meal recommendation status

 - Save messages to chat history

 - Auto-update preferences when constraints added



1.9.7 Error Handling & UX (30 min)

 - Global error boundary

 - Toast notifications for errors

 - Loading states for all async operations

 - Offline detection (optional)



apps/mobile/

├── src/

│   ├── services/

│   │   ├── auth/

│   │   │   ├── clerk.ts          # Clerk client setup

│   │   │   └── tokenManager.ts   # Token storage/refresh

│   │   ├── api/

│   │   │   ├── client.ts         # Axios client with auth

│   │   │   ├── types.ts          # API response types

│   │   │   ├── ai/

│   │   │   │   ├── pantry.ts

│   │   │   │   ├── meals.ts

│   │   │   │   └── chat.ts

│   │   │   └── [pantry|chat|meals|preferences].ts

│   │   └── sync/

│   │       └── userSync.ts       # Clerk → Supabase sync

│   ├── contexts/

│   │   └── AuthContext.tsx       # Auth state management

│   ├── screens/

│   │   └── auth/

│   │       ├── SignInScreen.tsx

│   │       └── SignUpScreen.tsx

│   └── utils/

│       ├── errorHandler.ts       # Centralized error handling

│       └── env.ts                # Environment config





---



### 1.10 Testing & Iteration (2-3 hours)

**Objective:** Verify everything works end-to-end

**Tasks:**

- Test Clerk auth flow (sign up, sign in, token refresh)
- Test pantry scan with real images
- Test chat workflow (all 3 actions: add constraint, recommend meal, general chat)
- Test meal recommendation workflow (async polling)
- Test chat streaming responses
- Verify Celery async task completion
- Test error handling (invalid images, failed recommendations, network errors)
- Verify Redis caching works
- Test all CRUD endpoints
- Fix any integration issues

---

## Phase 1 Success Criteria

✅ Recipe data and embeddings in cloud (S3 + Qdrant)

✅ RetrievalNode works with Qdrant

✅ FastAPI app running with Clerk auth

✅ Supabase database with all tables and RLS policies

✅ Redis + Celery working for async tasks

✅ Chat workflow with router-based action selection

✅ All API endpoints functional and protected (AI + CRUD)

✅ Frontend connects to backend with Clerk auth

✅ Chat streaming working

✅ Full end-to-end flow working locally

✅ No refactoring needed for Phase 2

---

## Phase 2: Deployment & Polish (Tomorrow)

**Timeline:** 8-12 hours

**Goal:** Docker setup, monitoring, polish, and Play Store submission

### 2.1 Docker Setup (2-3 hours)

**Files to Create:**

- `docker-compose.yml` - Local development setup
- `Dockerfile.backend` - Backend API container
- `Dockerfile.celery` - Celery worker container
- `.dockerignore`

**Services:**

- `backend` - FastAPI app (port 8000)
- `celery-worker` - Celery worker process
- `redis` - Redis service (or use external)

### 2.2 Monitoring & Observability (2-3 hours)

**Files to Create:**

- Basic logging setup
- Error tracking (Sentry)
- Health check improvements
- Prometheus and Grafana for CV model
- Tracing for LLM API calls

### 2.3 Polish & Testing (2-3 hours)

- UI/UX improvements
- Error message improvements
- Performance optimization
- Final end-to-end testing

### 2.4 Play Store Submission (1-2 hours)

- Build production APK
- Prepare store listing
- Submit to Google Play Store

---

## Implementation Order Summary

**Recommended execution order:**

1. ✅ 1.1 Cloud Data Setup (DONE)
2. ✅ 1.2 Backend Foundation (DONE)
3. **1.3 Infrastructure Setup** (Redis + Celery)
4. **1.4 Update User Preferences Model** (add custom_constraints)
5. **1.5 Cloud Storage Setup** (Supabase Storage)
6. **1.6 Service Layer** (wrap ML workflows)
7. **1.7 Chat Workflow** (AI workflow with router)
8. **1.8 API Endpoints** (AI + CRUD routers)
9. **1.9 Frontend Integration** (Clerk auth + API client + screens)
10. **1.10 Testing & Iteration**

---

## Key Design Decisions

1. **Chat Workflow:** Simple 2-node workflow (Router + ConstraintParser) for minimal complexity
2. **Constraints Storage:** All constraints (preset + custom) in `user_preferences`, not `chat_sessions`
3. **API Structure:** Split into `/api/ai/` (ML workflows) and `/api/` (CRUD) for clarity
4. **Streaming:** Chat responses stream via SSE for real-time UX
5. **Meal Recommendation:** Async via Celery, frontend polls with loading state
6. **Auth:** Clerk JWT verification on all protected endpoints