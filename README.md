# 🥗 Macronome — Eat in Rhythm, Not in Restriction

## 🎯 Overview

**Macronome** is an AI-powered nutrition co-pilot that helps people stay *in rhythm* with their goals — recommending meals that match their **cravings**, **diet**, **time**, and **available ingredients**.

Instead of forcing calorie counting, Macronome focuses on **balance and flow**.  
You describe what you feel like eating (or show your fridge), and the app recommends meals that align with your nutrition rhythm.

> **Tagline:** *Eat in rhythm, not in restriction.*

---

## 💡 Philosophy

Most calorie apps make eating mechanical. Macronome makes it intuitive — helping you make good choices dynamically, not rigidly.

You don’t obsessively track calories.  
You stay consistent *in rhythm* with how you actually live.

---

## 🧭 Core Features

### 🧠 AI Meal Recommendations
- Suggests meals that fit:
  - Diet type (vegan, high-protein, low-carb, etc.)
  - Remaining macros/calories (optional)
  - Cravings and prep time
  - Pantry/fridge inventory
- Hybrid logic: deterministic constraint fitting + LLM reasoning for natural input (“something quick and spicy”).

### 💬 Chat-like Experience
- Conversational interface for intuitive requests.
- Structured chips for key constraints (diet, cravings, time, pantry mode).
- “Add From Pantry” button for contextual recommendations.

### 📸 Pantry / Fridge Vision Scan
- Snap a photo → Macronome detects what you have.
- Pipeline:
  1. Bounding boxes (YOLO/RT-DETR)
  2. Crop + embed (OpenCLIP / SigLIP)
  3. OCR/barcode fusion
  4. Optional Vision-LLM fallback (Qwen2-VL / MiniCPM-V)
- User can confirm or edit detected items before saving.

### 🍽️ Meal Cards & Explanations
- Each meal includes:
  - Image, ingredients, prep time
  - “Why it fits” explanation
  - Suggested swaps (e.g. “swap rice → quinoa”)

### 📈 History & Learning
- Tracks accepted/rejected meals.
- Learns preferences to improve future recommendations.
- Focuses on *consistency over perfection.*

---

## 📱 Platform

- **Mobile-first:** Expo (React Native)
- Tabs:
  - 🏠 Home (Chat + Recommendations)
  - 🕒 History
  - ⚙️ Settings
  - 🧺 Pantry Capture (modal)
- Design language: **Midnight Rhythm**  
  Deep navy base • coral highlights • soft white cards.

---

## ⚙️ Architecture Overview

### **Frontend**
| Layer | Tech |
|-------|------|
| Framework | Expo (React Native) |
| State | Zustand / Redux Toolkit |
| Styling | NativeWind (Tailwind RN) |
| Auth | Supabase Auth SDK |
| API | REST (Supabase Edge Functions + FastAPI) |
| Storage | Supabase Storage (images, snapshots) |

---

### **Backend**
#### Managed: **Supabase**
- Postgres + `pgvector`
- Auth & JWT
- Storage for images
- Row-Level Security (per-user isolation)
- Edge Functions for lightweight orchestration

#### Dockerized Services
| Service | Description |
|----------|--------------|
| **vision-api** | Detects and classifies pantry items (YOLO + CLIP + OCR + optional VLM fallback). |
| **recommender-api** | Parses constraints, retrieves recipes, and ranks results. |
| **mlflow-agent-logger** | Logs LLM traces and ML experiments to MLflow GenAI. |

#### Async + Compute
- **Celery + Redis** → background jobs (embeddings, retraining, batch inference)
- **Redis cache** → deduplicate expensive calls (LLM & embeddings)

---

## 🧠 AI / ML Stack

| Layer | Tool |
|--------|------|
| **Embeddings** | OpenCLIP / SigLIP (Hugging Face) |
| **Vision** | YOLOv8-n or RT-DETR |
| **OCR / Barcode** | PaddleOCR + ZXing |
| **Vision-LLM Fallback** | Qwen2-VL / MiniCPM-V |
| **Text LLMs** | LiteLLM router (OpenAI, Claude, Gemini, etc.) |
| **Output Validation** | Pydantic + instructor |
| **Tracking & Registry** | MLflow (self-hosted) |
| **LLM Tracing** | MLflow GenAI (new) |
| **Workflow Orchestration** | Airflow / Celery Beat |
| **Caching** | Redis |

---

## 🔍 Observability & Tracing

| Area | Tool | Purpose |
|-------|------|----------|
| **LLM Tracing / Cost Tracking** | MLflow GenAI | Prompt-level tracing, token usage, latency, cost. |
| **Infra Metrics** | Prometheus + Grafana | API latency, Celery queue depth, uptime. |
| **Error Tracking** | Sentry | Crash/error visibility (FastAPI + Expo). |
| **Infra Tracing** | OpenTelemetry | Cross-service spans and traces. |

---

## 🧱 Infra & DevOps

| Layer | Tool | Purpose |
|-------|------|----------|
| **Containerization** | Docker + Docker Compose | Reproducible builds and deployment |
| **Infra-as-Code** | Terraform | Provision Supabase, VM, monitoring |
| **CI/CD** | GitHub Actions | Build/test/deploy containers & infra |
| **Reverse Proxy** | Caddy / Traefik | HTTPS + routing |
| **Scheduler** | Airflow / Celery Beat | Periodic retraining & embedding rebuilds |
| **VM Hosting** | Hetzner / Fly.io / Render | Cheap single-instance deployment |
| **Secrets** | Supabase Vault / AWS SSM | Environment and API keys |

---

## 💸 Expected Monthly Cost

| Component | Cost |
|------------|------|
| Supabase (Auth + DB + Storage) | $0–25 |
| Small VM (Docker services) | $10–15 |
| Redis Cloud (Free Tier) | $0 |
| MLflow self-host | $0 |
| Grafana Cloud / Sentry | Free tiers |
| LLM API (LiteLLM pay-per-use) | ~$10–20 |
| **Total** | **≈ $25–40 / month** |

---

## 🧩 Why This Stack

✅ **Full-stack ML/AI coverage** – from mobile UX → backend → models → infra.  
✅ **Industry-standard tools** – Celery, Redis, MLflow, Docker, Terraform, FastAPI, pgvector.  
✅ **Modern LLM practices** – LiteLLM routing, MLflow GenAI tracing, JSON validation.  
✅ **Cheap but real** – Runs on <$40/month infra.  
✅ **Portfolio showcase** – Demonstrates end-to-end MLOps ability.

---

## 🧠 Future Roadmap

- 🧩 Adaptive meal planning based on user history
- 📦 Grocery list generator from pantry
- 🔗 Integration with MyFitnessPal / Fitbit
- 👥 Community recipe upload + enrichment
- 🧮 LLM-based macro estimation for meals

---

## 🚀 Quick Setup (MVP Dev)

```bash
# Clone the repo
git clone https://github.com/yourusername/macronome
cd macronome

# Start backend services
docker-compose up --build

# Run Expo app
cd mobile
npm install
npx expo start
