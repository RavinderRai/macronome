Macronome V2 Development Roadmap
Core Identity:
"AI-powered macro tracker for flexible dieters - makes restaurant tracking effortless"

V2 Feature Set:
Priority 1: Core Macro Tracking (Foundation)
Week 1-3
Must-Have:

User profile setup (goals, stats, macro targets)
Daily macro tracking (log meals, view progress)
Progress visualization (bars, daily totals, weekly trends)
Saved meals (for meal prep repeats)
Quick-add common foods (eggs, chicken, rice, etc.)

Deliverable: Basic functional macro tracker

Priority 2: Restaurant Photo Tracking (Killer Feature)
Week 4-7
Must-Have:

Camera integration (take photo of meal)
Image retrieval system:

Embed photos with CLIP/DINOv2
Query vector DB (Nutrition5k dataset)
Return top 5 similar meals


Show matches with estimated macros
One-tap logging to daily tracker
Manual adjustment option (if estimate is off)

Deliverable: "Snap photo → instant macro estimate → log"

Priority 3: Smart Meal Recommendations (Unique Value)
Week 8-11
Must-Have:

Recipe database (scrape 5-10k recipes with macros)
Tag recipes during scraping (diet type, cuisine, cooking time)
Recommendation engine:

Calculate remaining macros
Filter recipes by macro range (±10% tolerance)
Rank by fit + user preferences


Show top 5-10 recommendations
Full recipe view → log if cooked

Optional Enhancement:

Filter by available ingredients (if user manually inputs pantry items)

Deliverable: "Need 800 cal, 60g protein" → get recipe recommendations that fit

Priority 4: Recipe Nutrition Prediction (Enabler)
Week 9-10 (Parallel with Priority 3)
Purpose: Many scraped recipes lack nutrition data
Must-Have:

Train ML model on 50k recipes (AllRecipes, Food.com with nutrition labels)
Input: Recipe name + ingredient list (no portions)
Output: Predicted macros per serving
Apply to recipes without nutrition data
Store predictions in database

Deliverable: All 10k recipes have macro data (calculated or predicted)