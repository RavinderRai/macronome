# Macronome MVP: 1-2 Day Build Plan

## Phase 1: Project Structure & Infrastructure Setup

**Goal:** Set up the foundational architecture with Docker services and Supabase integration.

### Backend Setup

- Create project structure:
  - `/backend/vision-api` - FastAPI service for pantry vision detection
  - `/backend/recommender-api` - FastAPI service for meal recommendations
  - `/backend/shared` - Common utilities (Supabase client, auth middleware, Pydantic models)
- Set up `docker-compose.yml` with:
  - `vision-api` service
  - `recommender-api` service
  - Redis cache service
- Create `requirements.txt` for each service with key dependencies:
  - FastAPI, Uvicorn
  - `ultralytics` (YOLOv8) or `transformers` (RT-DETR)
  - `transformers`, `torch`, `pillow` for image processing
  - `litellm` for LLM routing
  - `instructor` + `pydantic` for structured outputs
  - `supabase-py` client
  - `redis` for caching

### Supabase Setup

- Create free Supabase project
- Set up database schema:
  - `users` table (handled by Supabase Auth)
  - `pantry_items` table (user_id, item_name, detected_at, image_url)
  - `meal_history` table (user_id, meal_data, accepted, created_at)
  - `user_preferences` table (user_id, dietary_restrictions, default_constraints)
- Enable Supabase Storage bucket for pantry images
- Configure Row-Level Security policies
- Set up environment variables for API keys

### Frontend Setup

- Initialize Expo React Native project in `/mobile`
- Install dependencies:
  - `expo-camera` for camera access
  - `expo-image-picker` for image selection
  - `nativewind` for Tailwind styling
  - `zustand` for state management
  - `@supabase/supabase-js` for backend integration
- Set up basic navigation structure (Home, History, Settings tabs)

## Phase 2: Vision Pipeline (Pantry Scanning)

**Goal:** Build the pantry detection pipeline with lightweight CV + Vision LLM.

### Vision API Implementation (`/backend/vision-api`)

- **Endpoint:** `POST /detect-pantry`
  - Accept multipart image upload
  - Run object detection (YOLOv8-nano or RT-DETR-small)
  - Generate bounding boxes for food items
  - Crop detected regions
  - For each crop:
    - Send to Vision LLM (GPT-4V or Claude 3.5 Sonnet) with prompt: "What food item is this? Respond with just the item name."
    - Collect results
  - Return JSON: `{ "items": [{"name": str, "confidence": float, "bbox": [...]}] }`
- Add Redis caching (hash image → cache results for 5 mins to avoid duplicate API calls)
- Error handling & fallback: if object detection fails, send full image to Vision LLM

### Model Setup

- Download and cache YOLOv8-nano weights on container startup
- Alternative: Use `RT-DETR-ResNet50` from HuggingFace `transformers` (lighter deployment)
- Test with sample pantry images to tune confidence thresholds

### Mobile Integration

- Create "Add from Pantry" button (matches UI mockup)
- On press: open camera or image picker
- Upload image to `vision-api/detect-pantry`
- Show confirmation screen with detected items (user can edit/remove)
- Save confirmed items to `pantry_items` table via Supabase

## Phase 3: Meal Recommendation System

**Goal:** Build LLM-based meal recommendation with natural language + constraint handling.

### Recommender API Implementation (`/backend/recommender-api`)

- **Endpoint:** `POST /recommend-meals`
  - Accept JSON input:
    ```json
    {
      "user_id": "uuid",
      "query": "something quick and spicy",
      "constraints": {
        "calories": "700 or less",
        "carbs": "moderate",
        "diet": "any",
        "exclude_ingredients": ["peanuts"],
        "prep_time": "quick"
      },
      "pantry_items": ["chicken", "rice", "bell peppers"]
    }
    ```

  - Build LLM prompt with:
    - User query
    - Constraints (formatted naturally)
    - Available pantry items (if provided)
    - System message: "You are Macronome, a nutrition co-pilot. Recommend 3 meal ideas that fit the user's needs. For each meal, provide: name, ingredients, prep time, estimated calories/macros, why it fits their request, and suggested swaps."
  - Use `instructor` to enforce structured output:
    ```python
    class MealRecommendation(BaseModel):
        name: str
        ingredients: List[str]
        prep_time: str
        estimated_calories: int
        estimated_macros: dict
        why_it_fits: str
        suggested_swaps: List[str]
    
    class MealResponse(BaseModel):
        meals: List[MealRecommendation]
    ```

  - Call LLM via `litellm` (GPT-4o-mini or Claude Sonnet for cost efficiency)
  - Return structured meal recommendations

- **LLM Configuration:**
  - Set up LiteLLM with fallbacks: primary (GPT-4o-mini) → fallback (Claude Haiku)
  - Add Redis caching based on hash of (query + constraints + pantry)
  - Token budgeting: ~2000 tokens output should cover 3 detailed meals

### Mobile Chat Interface

- Build chat UI matching the mockup:
  - Navy background (`#1a2332`)
  - Message input at bottom
  - Constraint chips above input (700 kcal, Diet: Any, etc.)
  - "Add food from pantry" button (coral `#ff6b5a`)
- State management (Zustand):
  - Store active constraints
  - Store chat history
  - Store meal recommendations
- On user message send:
  - Show loading state
  - Call `recommender-api/recommend-meals`
  - Display meal cards with:
    - Meal name & image placeholder
    - Ingredients list
    - Prep time & macros
    - "Why it fits" explanation
    - Suggested swaps
    - Accept/Reject buttons

### Meal Card Actions

- **Accept meal:** Save to `meal_history` table with `accepted: true`
- **Reject meal:** Save with `accepted: false` (for future learning)
- Track interactions for preference learning (Phase 4+)

## Phase 4: Integration & Polish

**Goal:** Connect all pieces and make it usable end-to-end.

### Authentication

- Implement Supabase Auth in mobile app (email/password or magic link)
- Add auth middleware to FastAPI services (validate Supabase JWT)
- Store user session in Zustand

### Constraint Management

- Implement chip UI for quick constraint editing:
  - Calorie range selector
  - Diet dropdown (Any, Vegan, High-Protein, Low-Carb, Keto)
  - Exclude ingredients modal
  - Prep time (Quick <15min, Medium 15-30min, Flexible)
- Save user preferences to `user_preferences` table

### History View

- Fetch `meal_history` from Supabase
- Display previously accepted/rejected meals
- Allow re-viewing meal details

### Settings View

- User profile (basic info)
- Default dietary preferences
- Logout

### Error Handling & UX

- Add loading states for all API calls
- Network error handling with retry logic
- Graceful degradation if vision or LLM APIs fail
- Toast notifications for success/error states

## Phase 5: Testing & Deployment

**Goal:** Ensure everything works locally and prepare for future deployment.

### Local Testing

- Test full flow:

  1. Sign up → set preferences
  2. Scan pantry → detect items → confirm
  3. Chat request → receive recommendations → accept meal
  4. View history

- Test edge cases:
  - No pantry items
  - Invalid image uploads
  - LLM API failures
  - Network interruptions

### Docker Compose Validation

- Ensure all services start cleanly
- Verify Redis caching works
- Check container health endpoints
- Test hot-reload for development

### Documentation

- Update README with:
  - Local setup instructions
  - Environment variable configuration
  - API documentation (endpoints, payloads)
  - Architecture diagram
  - Screenshot/demo video

### Cost Tracking (for ML showcase)

- Add basic logging for LLM API costs:
  - Log tokens used per request
  - Track Vision LLM vs text LLM usage
  - Estimate monthly cost based on usage patterns
- This demonstrates ML cost awareness

## Key Files to Create

**Backend:**

- `/backend/vision-api/main.py` - FastAPI app with detection endpoint
- `/backend/vision-api/models.py` - YOLO/RT-DETR model loading
- `/backend/vision-api/Dockerfile`
- `/backend/recommender-api/main.py` - FastAPI app with recommendation endpoint
- `/backend/recommender-api/llm.py` - LiteLLM configuration & prompt engineering
- `/backend/recommender-api/Dockerfile`
- `/backend/shared/supabase_client.py` - Supabase initialization
- `/backend/shared/auth.py` - JWT validation middleware
- `/backend/shared/schemas.py` - Shared Pydantic models
- `/docker-compose.yml`
- `/backend/requirements-vision.txt`
- `/backend/requirements-recommender.txt`

**Frontend:**

- `/mobile/app/(tabs)/_layout.tsx` - Tab navigation
- `/mobile/app/(tabs)/index.tsx` - Home/Chat screen
- `/mobile/app/(tabs)/history.tsx` - History screen
- `/mobile/app/(tabs)/settings.tsx` - Settings screen
- `/mobile/components/MealCard.tsx` - Meal recommendation card
- `/mobile/components/ConstraintChips.tsx` - Constraint UI
- `/mobile/components/PantryScanner.tsx` - Camera/upload interface
- `/mobile/store/useStore.ts` - Zustand store
- `/mobile/lib/supabase.ts` - Supabase client setup
- `/mobile/lib/api.ts` - Backend API calls

**Configuration:**

- `/.env.example` - Environment variable template
- `/mobile/.env.example`

## Success Criteria for MVP

✅ User can sign up and authenticate

✅ User can snap a photo → see detected pantry items → save them

✅ User can chat with constraints → receive 3 meal recommendations

✅ Meal recommendations include explanations and fit user constraints

✅ User can accept/reject meals → saved to history

✅ App works end-to-end locally with Docker + Expo

✅ Demonstrates ML skills: CV pipeline (YOLO) + Vision LLM + Text LLM orchestration

✅ Code is clean, documented, and deployment-ready

## Post-MVP Optimizations (Not in 1-2 Day Scope)

- Recipe database integration (Edamam API) for richer meal options
- MLflow integration for LLM tracing & cost monitoring
- CLIP embeddings for recipe similarity search
- Celery for async background processing
- Fine-tuned preference learning model
- Terraform for infrastructure-as-code
- CI/CD pipeline with GitHub Actions

## Frontend Learning and Building Plan

Mobile App Step-by-Step Implementation Plan
Overview
This plan is structured in 12 incremental phases. Each phase builds on the previous one, making it easy to learn frontend development progressively. We'll use Zustand for state management and set up API client structure with TODOs since the backend isn't ready yet.

---

Phase 1: Foundation & Theme Setup
Goal: Set up project structure, styling system, and basic constants

Files to Create:
apps/mobile/src/
├── theme/
│   ├── colors.ts          # Midnight Rhythm color palette
│   ├── typography.ts      # Font styles
│   └── spacing.ts         # Spacing scale
│
└── utils/
    └── constants.ts       # App-wide constants
What You'll Learn:
TypeScript basics for React Native
Theme/design system structure
Constants organization
Dependencies: None (using built-in React Native)
---

Phase 2: Basic Navigation Setup
Goal: Set up navigation structure (Stack + Drawer)

Files to Create:
apps/mobile/src/
├── navigation/
│   ├── index.tsx          # Navigation setup
│   └── types.ts           # Navigation types
│
└── screens/
    └── HomeScreen.tsx     # Basic empty screen
Dependencies to Install:
@react-navigation/native
@react-navigation/stack
@react-navigation/drawer
react-native-screens
react-native-safe-area-context
react-native-gesture-handler
What You'll Learn:
React Navigation basics
Stack vs Drawer navigators
Screen components
---

Phase 3: State Management with Zustand
Goal: Set up Zustand stores for app state

Files to Create:
apps/mobile/src/
├── store/
│   ├── index.ts           # Store exports
│   ├── chatStore.ts       # Chat messages state
│   ├── filterStore.ts     # Filter constraints state
│   ├── pantryStore.ts     # Pantry items state
│   └── uiStore.ts         # UI state (collapsed, drawer open)
│
└── types/
    ├── chat.ts            # Message, Meal types
    ├── filters.ts           # Filter types
    └── pantry.ts           # Pantry item types
Dependencies to Install:
zustand
What You'll Learn:
State management concepts
Zustand store patterns
TypeScript types for state
---

Phase 4: Common Components
Goal: Build reusable UI components

Files to Create:
apps/mobile/src/
└── components/
    └── common/
        ├── Header.tsx             # App header with icons
        ├── LoadingSpinner.tsx     # Loading indicator
        └── EmptyState.tsx         # Empty state placeholder
What You'll Learn:
React Native components
Props and TypeScript
Basic styling with StyleSheet
---

Phase 5: Filter Components
Goal: Build filter chips and collapsible section

Files to Create:
apps/mobile/src/
└── components/
    └── filters/
        ├── FilterSection.tsx      # Collapsible header
        ├── FilterChip.tsx         # Individual chip
        └── AddFilterButton.tsx    # "+ Calories" buttons
What You'll Learn:
Conditional rendering
State-driven UI updates
TouchableOpacity/Button interactions
Animated API basics
---

Phase 6: Chat Components
Goal: Build chat interface components

Files to Create:
apps/mobile/src/
└── components/
    └── chat/
        ├── ChatMessage.tsx        # Message bubble
        ├── ChatInput.tsx          # Input with camera button
        └── MealCard.tsx           # Meal recommendation card
What You'll Learn:
FlatList/ScrollView for lists
TextInput handling
Component composition
Styling message bubbles
---

Phase 7: HomeScreen Integration
Goal: Combine all components into main screen

Files to Update:
apps/mobile/src/
└── screens/
    └── HomeScreen.tsx     # Full chat interface
What You'll Learn:
Component composition
Layout with Flexbox
Connecting components to state
ScrollView behavior
---

Phase 8: Pantry Drawer
Goal: Build left-side drawer for pantry items

Files to Create:
apps/mobile/src/
└── components/
    └── pantry/
        ├── PantryDrawer.tsx       # Drawer component
        ├── PantryItem.tsx         # Item row
        └── PantryItemList.tsx     # List component
What You'll Learn:
Drawer navigation patterns
List rendering
Badge/count display
---

Phase 9: Camera Integration
Goal: Add camera screen for pantry scanning

Files to Create:
apps/mobile/src/
├── screens/
│   └── CameraScreen.tsx   # Full-screen camera
│
└── services/
    └── camera/
        └── cameraService.ts  # Camera utilities
Dependencies to Install:
expo-camera
What You'll Learn:
Camera API usage
Image capture
Modal navigation
Permissions handling
---

Phase 10: Pantry Review Bottom Sheet
Goal: Add bottom sheet to review scanned items

Files to Create:
apps/mobile/src/
└── components/
    └── pantry/
        └── PantryReviewSheet.tsx  # Bottom sheet component
Dependencies to Install:
@gorhom/bottom-sheet
react-native-reanimated
What You'll Learn:
Bottom sheet patterns
Animated components
Form/checkbox handling
---

Phase 11: API Client Setup (TODOs)
Goal: Set up API structure with placeholder functions

Files to Create:
apps/mobile/src/
├── services/
│   └── api/
│       ├── client.ts      # HTTP client setup (TODO)
│       ├── chat.ts        # Chat endpoints (TODO)
│       └── pantry.ts      # Pantry endpoints (TODO)
│
└── types/
    └── api.ts             # API response types
Dependencies to Install:
@supabase/supabase-js (for future use)
axios (for FastAPI calls)
What You'll Learn:
API client patterns
Async/await in React Native
Error handling structure
TypeScript for API responses
Note: These files will have TODO comments and placeholder functions since backend isn't set up yet. Example:

// TODO: Set up Supabase client when backend is ready
export const supabaseClient = null;

// TODO: Implement when FastAPI endpoint is ready
export async function sendChatMessage(message: string) {
  // Placeholder - return mock data for now
  return { response: "Mock response" };
}
---

Phase 12: Polish & Onboarding
Goal: Add animations, hints, and error handling

Files to Update:
Add onboarding hints to HomeScreen
Add loading states
Add error boundaries
Add animations to filter collapse
Dependencies to Install:
react-native-reanimated (if not already)
What You'll Learn:
Animation basics
User experience patterns
Error handling
Loading states
---

Complete File Structure (Reference)
apps/mobile/
├── App.tsx                    # Root with navigation
├── src/
│   ├── navigation/
│   │   ├── index.tsx
│   │   └── types.ts
│   ├── screens/
│   │   ├── HomeScreen.tsx
│   │   └── CameraScreen.tsx
│   ├── components/
│   │   ├── chat/
│   │   │   ├── ChatMessage.tsx
│   │   │   ├── ChatInput.tsx
│   │   │   └── MealCard.tsx
│   │   ├── filters/
│   │   │   ├── FilterSection.tsx
│   │   │   ├── FilterChip.tsx
│   │   │   └── AddFilterButton.tsx
│   │   ├── pantry/
│   │   │   ├── PantryDrawer.tsx
│   │   │   ├── PantryItem.tsx
│   │   │   ├── PantryItemList.tsx
│   │   │   └── PantryReviewSheet.tsx
│   │   └── common/
│   │       ├── Header.tsx
│   │       ├── LoadingSpinner.tsx
│   │       └── EmptyState.tsx
│   ├── store/
│   │   ├── index.ts
│   │   ├── chatStore.ts
│   │   ├── filterStore.ts
│   │   ├── pantryStore.ts
│   │   └── uiStore.ts
│   ├── services/
│   │   ├── api/
│   │   │   ├── client.ts (TODO)
│   │   │   ├── chat.ts (TODO)
│   │   │   └── pantry.ts (TODO)
│   │   └── camera/
│   │       └── cameraService.ts
│   ├── types/
│   │   ├── chat.ts
│   │   ├── filters.ts
│   │   ├── pantry.ts
│   │   └── api.ts
│   ├── theme/
│   │   ├── colors.ts
│   │   ├── typography.ts
│   │   └── spacing.ts
│   └── utils/
│       └── constants.ts
Key Dependencies Summary
@react-navigation/native - Navigation
@react-navigation/stack - Stack navigation
@react-navigation/drawer - Drawer navigation
react-native-screens - Screen support
react-native-safe-area-context - Safe area handling
react-native-gesture-handler - Gesture support
zustand - State management
expo-camera - Camera access
@gorhom/bottom-sheet - Bottom sheet
react-native-reanimated - Animations
@supabase/supabase-js - Supabase client (future)
axios - HTTP client for FastAPI (future)