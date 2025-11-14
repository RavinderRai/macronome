# Macronome Backend API

FastAPI backend for meal recommendation and pantry scanning.

## Quick Start

### 1. Install Dependencies

```bash
pip install -r src/macronome/backend/requirements.txt
```

### 2. Configure Environment

Copy `.env.example` to `.env` and fill in your API keys:

```bash
cp .env.example .env
# Edit .env with your keys
```

### 3. Set Up Database

Run the SQL commands in `db/models.py` to create Supabase tables:

1. Go to your Supabase project SQL editor
2. Copy and run the CREATE TABLE statements from `models.py`
3. Verify tables are created with RLS policies

### 4. Run the Server

```bash
# Development mode (with auto-reload)
python -m macronome.backend.app

# Or with uvicorn directly
uvicorn macronome.backend.app:app --reload --host 0.0.0.0 --port 8000
```

API will be available at `http://localhost:8000`

- Health check: `GET /health`
- API docs: `GET /docs` (dev only)

## Project Structure

```
backend/
├── __init__.py
├── app.py              # FastAPI app initialization
│
├── api/                # API routes
│   └── routers/        # TODO: Create pantry and meals routers
│
├── auth/               # Authentication
│   ├── clerk.py        # Clerk JWT verification
│   └── middleware.py   # Auth dependencies
│
├── db/                 # Database
│   ├── models.py       # Pydantic models + SQL schema
│   └── session.py      # Supabase client
│
├── services/           # Business logic
│   └── ...             # TODO: Create ML service wrappers
│
└── tasks/              # Celery async tasks
    └── ...             # TODO: Create async meal recommendation task
```

## TODO

### Next Steps (in order):

1. **Infrastructure Setup** (Section 1.3 in plan):
   - Set up Redis connection pool
   - Create Celery worker
   - Implement LLM caching

2. **Service Layer** (Section 1.4):
   - Create `services/pantry_scanner.py`
   - Create `services/meal_recommender.py`

3. **API Endpoints** (Section 1.5):
   - Create `api/routers/pantry.py`
   - Create `api/routers/meals.py`
   - Register routers in `app.py`

4. **Cloud Storage** (Section 1.6):
   - Create `storage/s3.py`
   - Create `storage/supabase_storage.py`

## Authentication

Uses Clerk for JWT authentication. All protected endpoints require:

```
Authorization: Bearer <clerk_jwt_token>
```

Example:

```python
from fastapi import Depends
from macronome.backend.auth import get_current_user

@app.get("/protected")
async def protected_route(user: Dict = Depends(get_current_user)):
    user_id = user["sub"]  # Clerk user ID
    return {"user_id": user_id}
```

## Database

Uses Supabase with Row Level Security (RLS). Tables:

- `pantry_items` - User's pantry inventory
- `meal_history` - Meal recommendation history
- `user_preferences` - User dietary preferences and constraints

RLS policies ensure users can only access their own data.

## Configuration

All environment variables are centralized in `src/macronome/settings.py`:
- `DataConfig` - Data storage, S3, Qdrant, USDA API
- `BackendConfig` - Backend API, Supabase, Clerk, Redis, Celery

See `.env.example` for all configuration options.

Required for production:
- `SUPABASE_URL`, `SUPABASE_KEY`
- `CLERK_PUBLISHABLE_KEY`, `CLERK_SECRET_KEY`
- `REDIS_URL` or `REDIS_HOST`
- `QDRANT_URL`, `QDRANT_API_KEY`
- `S3_BUCKET`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`

