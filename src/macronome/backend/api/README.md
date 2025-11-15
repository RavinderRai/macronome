# Macronome API Documentation

## Overview

The Macronome API is organized using a **domain-driven structure** with FastAPI tags for ML vs. CRUD operations:

- **Domain-based routing**: `/api/{domain}/` (pantry, meals, chat, preferences)
- **FastAPI tags**: `ml` tag for ML endpoints, domain tag for CRUD
- **Authentication**: All endpoints protected with Clerk JWT via `Authorization: Bearer <token>` header

---

## API Structure

```
/api/
├── pantry/
│   ├── scan (POST) [ml, pantry] - AI pantry scanning
│   ├── items (GET) [pantry] - Get pantry items
│   ├── items (POST) [pantry] - Add pantry items
│   └── items/{item_id} (DELETE) [pantry] - Delete pantry item
├── meals/
│   ├── recommend (POST) [ml, meals] - AI meal recommendation (async)
│   ├── recommend/{task_id} (GET) [ml, meals] - Poll recommendation status
│   ├── history (GET) [meals] - Get meal history
│   ├── history (POST) [meals] - Save meal to history
│   └── history/{meal_id}/rating (PUT) [meals] - Update meal rating
├── chat/
│   ├── message (POST) [ml, chat] - AI chat workflow
│   ├── sessions (GET) [chat] - Get chat sessions
│   ├── sessions (POST) [chat] - Create chat session
│   └── sessions/{session_id}/messages (GET) [chat] - Get session messages
└── preferences/
    ├── / (GET) [preferences] - Get user preferences
    ├── / (PUT) [preferences] - Update user preferences
    └── / (DELETE) [preferences] - Reset preferences
```

---

## Endpoints by Domain

### 1. Pantry (`/api/pantry/`)

#### **POST /api/pantry/scan** [ML]
AI: Scan pantry image to detect food items

**Request:**
- Headers: `Authorization: Bearer <token>`
- Body: `multipart/form-data` with `file` (image)

**Response:**
```json
{
  "items": [
    {
      "name": "Apple",
      "category": "Fruit",
      "confidence": 0.95,
      "bounding_box": {"x": 10, "y": 20, "width": 100, "height": 150}
    }
  ],
  "num_items": 1
}
```

#### **GET /api/pantry/items**
Get user's pantry items

**Response:**
```json
{
  "items": [
    {
      "id": "uuid",
      "user_id": "clerk_user_id",
      "name": "Apple",
      "category": "Fruit",
      "confirmed": true,
      "confidence": 0.95,
      "created_at": "2024-01-01T00:00:00Z",
      "updated_at": "2024-01-01T00:00:00Z"
    }
  ],
  "total": 1
}
```

#### **POST /api/pantry/items**
Add items to pantry

**Request:**
```json
[
  {
    "name": "Apple",
    "category": "Fruit",
    "confirmed": true,
    "confidence": 0.95
  }
]
```

#### **DELETE /api/pantry/items/{item_id}**
Delete pantry item

**Response:** `204 No Content`

---

### 2. Meals (`/api/meals/`)

#### **POST /api/meals/recommend** [ML]
AI: Request meal recommendation (async)

**Request:**
```json
{
  "user_query": "I want a vegan meal under 600 calories",
  "constraints": {
    "calories": 600,
    "diet": "vegan"
  }
}
```

**Response:**
```json
{
  "task_id": "celery_task_id",
  "message": "Meal recommendation in progress. Use task_id to check status."
}
```

#### **GET /api/meals/recommend/{task_id}** [ML]
AI: Poll meal recommendation status

**Response:**
```json
{
  "status": "success",
  "result": {
    "recipe": {
      "id": "recipe_123",
      "name": "Vegan Buddha Bowl",
      "ingredients": ["quinoa", "chickpeas", "avocado"],
      "directions": "1. Cook quinoa...",
      "prep_time": 30,
      "calories": 550,
      "nutrition": {"carbs": 60, "protein": 20, "fat": 15}
    },
    "why_it_fits": "This recipe fits your vegan preference...",
    "ingredient_swaps": ["Use brown rice instead of quinoa"],
    "pantry_utilization": ["chickpeas", "avocado"],
    "recipe_instructions": "Step-by-step instructions..."
  },
  "error": null
}
```

#### **GET /api/meals/history**
Get meal recommendation history

**Query Params:**
- `limit` (optional, default: 50)

**Response:**
```json
[
  {
    "id": "uuid",
    "user_id": "clerk_user_id",
    "name": "Vegan Buddha Bowl",
    "description": "Healthy and delicious",
    "ingredients": ["quinoa", "chickpeas"],
    "reasoning": "Fits your vegan preference",
    "accepted": true,
    "rating": 5,
    "created_at": "2024-01-01T00:00:00Z"
  }
]
```

#### **POST /api/meals/history**
Save meal to history

**Request:**
```json
{
  "name": "Vegan Buddha Bowl",
  "description": "Healthy and delicious",
  "ingredients": ["quinoa", "chickpeas"],
  "reasoning": "Fits your vegan preference",
  "meal_data": {},
  "accepted": true
}
```

#### **PUT /api/meals/history/{meal_id}/rating**
Update meal rating

**Request:**
```json
{
  "rating": 5
}
```

---

### 3. Chat (`/api/chat/`)

#### **POST /api/chat/message** [ML]
AI: Send chat message

**Request:**
```json
{
  "message": "I want a low-carb meal",
  "chat_session_id": "uuid" // optional, creates new if not provided
}
```

**Response:**
```json
{
  "response": "I've updated your preferences to include low-carb meals!",
  "action": "add_constraint",
  "task_id": null,
  "updated_constraints": {
    "default_constraints": {"diet": "low-carb"},
    "dietary_restrictions": [],
    "custom_constraints": {},
    "disliked_ingredients": [],
    "favorite_cuisines": [],
    "updated_fields": ["default_constraints"]
  },
  "chat_session_id": "uuid"
}
```

**Actions:**
- `add_constraint`: Parses and saves constraints to `user_preferences`
- `start_recommendation`: Queues meal recommendation task (returns `task_id`)
- `general_chat`: Provides helpful response

#### **GET /api/chat/sessions**
Get user's chat sessions

**Query Params:**
- `limit` (optional, default: 50)

**Response:**
```json
[
  {
    "id": "uuid",
    "user_id": "clerk_user_id",
    "is_active": true,
    "filters": {},
    "created_at": "2024-01-01T00:00:00Z",
    "updated_at": "2024-01-01T00:00:00Z"
  }
]
```

#### **POST /api/chat/sessions**
Create new chat session

**Request:**
```json
{
  "filters": {}
}
```

**Response:**
```json
{
  "id": "uuid",
  "user_id": "clerk_user_id",
  "is_active": true,
  "filters": {},
  "created_at": "2024-01-01T00:00:00Z",
  "updated_at": "2024-01-01T00:00:00Z"
}
```

#### **GET /api/chat/sessions/{session_id}/messages**
Get messages for a chat session

**Query Params:**
- `limit` (optional, default: 100)

**Response:**
```json
[
  {
    "id": "uuid",
    "chat_session_id": "uuid",
    "text": "I want a low-carb meal",
    "type": "user",
    "timestamp": "2024-01-01T00:00:00Z"
  },
  {
    "id": "uuid",
    "chat_session_id": "uuid",
    "text": "I've updated your preferences!",
    "type": "assistant",
    "timestamp": "2024-01-01T00:00:00Z"
  }
]
```

---

### 4. Preferences (`/api/preferences/`)

#### **GET /api/preferences/**
Get user preferences

**Response:**
```json
{
  "id": "uuid",
  "user_id": "clerk_user_id",
  "dietary_restrictions": ["vegan", "gluten-free"],
  "default_constraints": {
    "calories": 600,
    "macros": {"carbs": 50, "protein": 30, "fat": 20},
    "diet": "vegan",
    "excludedIngredients": ["onions"],
    "prepTime": 30
  },
  "custom_constraints": {
    "spicy": true,
    "cuisine": "Mexican"
  },
  "favorite_cuisines": ["Japanese", "Thai"],
  "disliked_ingredients": ["cilantro"],
  "created_at": "2024-01-01T00:00:00Z",
  "updated_at": "2024-01-01T00:00:00Z"
}
```

#### **PUT /api/preferences/**
Update user preferences

**Request:** (all fields optional)
```json
{
  "dietary_restrictions": ["vegan"],
  "default_constraints": {
    "calories": 600
  },
  "custom_constraints": {
    "spicy": true
  },
  "favorite_cuisines": ["Japanese"],
  "disliked_ingredients": ["cilantro"]
}
```

**Response:** Same as GET

#### **DELETE /api/preferences/**
Reset user preferences to defaults

**Response:** `204 No Content`

---

## Authentication

All endpoints require Clerk JWT authentication via the `Authorization` header:

```
Authorization: Bearer <clerk_jwt_token>
```

If the token is missing or invalid, you'll receive:
```json
{
  "detail": "Invalid or expired token"
}
```
**Status Code:** `401 Unauthorized`

---

## Error Handling

All endpoints return standard HTTP status codes:

- `200 OK`: Successful GET/PUT
- `201 Created`: Successful POST
- `204 No Content`: Successful DELETE
- `400 Bad Request`: Invalid input
- `401 Unauthorized`: Missing or invalid auth token
- `404 Not Found`: Resource not found
- `500 Internal Server Error`: Server error

Error responses follow this format:
```json
{
  "detail": "Error message describing what went wrong"
}
```

---

## MLOps: Observability & Monitoring

### FastAPI Tags
All endpoints are tagged for easy filtering:
- **`ml` tag**: AI/ML endpoints (pantry scan, meal recommendation, chat)
- **Domain tags**: `pantry`, `meals`, `chat`, `preferences`

### Accessing ML Endpoints
Filter by `ml` tag in API docs to see all AI-powered endpoints:
- `/api/pantry/scan` [ml, pantry]
- `/api/meals/recommend` [ml, meals]
- `/api/meals/recommend/{task_id}` [ml, meals]
- `/api/chat/message` [ml, chat]

### Logging
All endpoints log:
- Request start (with user_id)
- Success/failure
- Error details

Example:
```
2024-01-01 00:00:00 - INFO - 🍽️ Queuing meal recommendation for user clerk_user_123
2024-01-01 00:00:01 - INFO - ✅ Queued meal recommendation task abc123 for user clerk_user_123
```

---

## Running the API

### Development
```bash
python -m macronome.backend.app
```

or

```bash
uvicorn macronome.backend.app:app --reload
```

### Production
```bash
uvicorn macronome.backend.app:app --host 0.0.0.0 --port 8000 --workers 4
```

### Environment Variables
See `src/macronome/settings.py` for required environment variables:
- `CLERK_JWT_PUBLIC_KEY`
- `SUPABASE_URL`, `SUPABASE_KEY`
- `REDIS_URL`
- `CELERY_BROKER_URL`, `CELERY_RESULT_BACKEND`
- `QDRANT_URL`, `QDRANT_API_KEY`
- `S3_BUCKET_NAME`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`

---

## Next Steps

1. **Frontend Integration**: Connect mobile app to these endpoints
2. **Streaming**: Implement SSE for chat streaming (`/api/chat/message/stream`)
3. **Testing**: Add integration tests for all endpoints
4. **Deployment**: Deploy to AWS/GCP with proper CI/CD pipeline

