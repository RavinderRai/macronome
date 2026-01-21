# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Macronome is an AI-powered nutrition co-pilot that recommends meals based on constraints (macros, diet type, allergies, cravings, prep time) without calorie counting. It combines deterministic constraint satisfaction with LLM reasoning and uses vision AI for pantry scanning.

## Development Commands

### Backend (Python/FastAPI)

```bash
# Install dependencies (uses uv package manager)
uv sync

# Run FastAPI server
python -m macronome.backend.app

# Run Celery worker
celery -A macronome.backend.worker.config.celery_app worker --loglevel=info --pool=solo
```

### Mobile (Expo/React Native)

```bash
cd apps/mobile
npm install
npx expo start        # Development server
npx expo run:android  # Run on Android
npx expo run:ios      # Run on iOS
```

### Docker

```bash
docker-compose up --build  # Runs api (port 8000) and worker services
```

## Architecture

### Directory Structure

- `apps/mobile/` - Expo React Native app
- `src/macronome/` - Main Python package
  - `backend/` - FastAPI application, routers, auth, database models
  - `ai/` - AI/ML workflows and pipelines
  - `data_engineering/` - Recipe ingestion and embedding generation

### Key Architectural Patterns

**Workflow Orchestration Framework** (`src/macronome/ai/core/`):
- Custom Node-based DAG execution with Chain of Responsibility pattern
- `Workflow` class orchestrates nodes, `TaskContext` passes data between them
- Nodes: `AgentNode` (LLM with tools), `BaseRouter` (routing logic), `ConcurrentNode`

**Meal Recommendation Workflow** (`ai/workflows/meal_recommender_workflow.py`):
9-node pipeline: NormalizeNode → PlanningAgent → RetrievalNode → SelectionAgent → InitialNutritionNode → ModificationAgent (max 5 iterations) → QCRouter → ExplanationAgent/FailureAgent

**Pantry Scanner Workflow** (`ai/workflows/pantry_scanner_workflow.py`):
YOLO detection → Crop → Vision LLM classification

### Frontend State Management

Zustand stores in `apps/mobile/src/store/`:
- `chatStore` - Messages and loading state
- `pantryStore` - Pantry items
- `filterStore` - User constraints
- `uiStore` - UI state (drawer visibility, etc.)

### Backend Services

- FastAPI routes: `/api/users`, `/api/pantry`, `/api/meals`, `/api/chat`, `/api/preferences`
- Clerk JWT authentication with middleware
- Supabase (Postgres + pgvector) for database
- Redis for caching and Celery broker
- Qdrant for recipe vector search

### Configuration

Centralized in `src/macronome/settings.py`:
- `ENV` - deployment environment (dev/prod)
- `DataConfig` - Vector DB, recipe limits
- `BackendConfig` - Server config, auth, Redis, file uploads

## Required Environment Variables

- `SUPABASE_URL`, `SUPABASE_KEY`, `SUPABASE_SERVICE_KEY`
- `CLERK_PUBLISHABLE_KEY`, `CLERK_SECRET_KEY`
- `OPENAI_API_KEY`
- `USDA_API_KEY` (for nutrition calculation)
- `QDRANT_URL`, `QDRANT_API_KEY`
- `REDIS_URL`
- AWS credentials for S3 storage (optional)

## Code Conventions

Keep Python imports at the top of the file.
