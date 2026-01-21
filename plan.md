Macronome V2 Development Roadmap

Core Identity:
"AI-powered macro tracker for flexible dieters - makes restaurant tracking effortless"

---

## Core Estimation Approach (All Meals)

Every meal logged in Macronome follows the same pattern:

1. **Photo → Dish Recognition** - Identify what the meal is
2. **Dish → Ingredient Breakdown** - Decompose into individual ingredients with portions
3. **RAG Grounding** - Find similar meals in database to validate/calibrate estimates
4. **Nutrition Lookup** - USDA lookup for each ingredient, sum for total
5. **User Editable** - Always show ingredient list, let users adjust

**Portion Handling:**
- Default to "1 serving" for all meals
- Offer Small / Regular / Large modifier (RAG database defines what these mean per dish)
- Users can edit individual ingredient quantities if needed

**Why This Approach:**
- Transparency builds trust (users see *why* we estimate X calories)
- Editable ingredients handle edge cases without complex CV
- RAG grounding keeps estimates realistic based on real meal data

---

## Restaurant vs Home Meals

**Home Meals:**
- Match against home-cooked recipe database
- Standard portion assumptions
- USDA ingredient lookup

**Restaurant Meals:**
- Match against restaurant meal database only (don't mix with home-cooked)
- Restaurant-style defaults: larger portions, more oil/butter/sauce
- Chain restaurants: use published nutrition data when available
- Independent restaurants: component breakdown with conservative estimates

**Data Sources to Explore:**
- Chain nutrition data (Chipotle, Sweetgreen, etc.) - accurate, published
- MenuStat database - 300+ chains, standardized
- Nutrition5k - 5k meal images with labels (validate coverage)
- User corrections over time - personalized learning

---

## V2 Feature Set

### Priority 1: Core Macro Tracking (Foundation)

Must-Have:
- User profile setup (goals, stats, macro targets)
- Daily macro tracking (log meals, view progress)
- Progress visualization (bars, daily totals, weekly trends)
- Saved meals (for meal prep repeats)
- Quick-add common foods (eggs, chicken, rice, etc.)

Deliverable: Basic functional macro tracker

---

### Priority 2: AI Photo Tracking

Must-Have:
- Camera integration (snap photo of any meal)
- Dish recognition → ingredient breakdown pipeline
- RAG lookup for similar meals (separate DBs for home vs restaurant)
- Show ingredient list with estimated portions
- Small / Regular / Large portion selector
- Editable ingredients (add, remove, adjust quantities)
- One-tap logging to daily tracker

Restaurant-Specific:
- Detect/select if meal is from restaurant
- Use restaurant meal database for matching
- Apply restaurant-style portion/prep defaults
- Chain restaurant lookup when identifiable

Deliverable: "Snap photo → see ingredient breakdown → adjust if needed → log"

---

### Priority 3: Smart Meal Recommendations

Must-Have:
- Recipe database (scrape 5-10k recipes with macros)
- Tag recipes during scraping (diet type, cuisine, cooking time)
- Recommendation engine:
  - Calculate remaining macros for the day
  - Filter recipes by macro range (±10% tolerance)
  - Rank by fit + user preferences
- Show top 5-10 recommendations
- Full recipe view → log if cooked (adds ingredients to daily log)

Optional Enhancement:
- Filter by available ingredients (pantry mode from V1)

Deliverable: "Need 800 cal, 60g protein" → get recipe recommendations that fit

---

## Open Questions / Feasibility to Test

1. **RAG for portion sizing** - Can we reliably define Small/Regular/Large from meal database? Need to test coverage and variance.

2. **Restaurant meal database coverage** - Is Nutrition5k + MenuStat enough? What's the fallback for unmatched meals?

3. **Dish → Ingredient decomposition** - LLM-based? Template-based? Hybrid? Test accuracy.

4. **Photo → Dish recognition accuracy** - CLIP/DINOv2 embedding + vector search vs fine-tuned classifier?