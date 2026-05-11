# TODOS

Tracked work items deferred from reviews and design sessions. Each entry includes context for someone (or future-you) picking it up cold.

---

## P1 — Eval set sourcing (web-sourced, start small)

**What:** Source ~100 labeled examples across the three ML stages from public datasets. No cook-and-log. Start small; expand only if eval signal is too noisy.

**Concrete sources (locked in /plan-eng-review):**
- **Home photo→macros (~30 photos):** subset of Nutrition5k, filtered to dishes that map to common Western recipes.
- **Dish recognition only (~20 photos):** Food-101 sample for top-1/top-5 of the recognition stage.
- **Menu items (~30, text-only):** MenuStat + scraped published nutrition pages from 5 chains (Chipotle, Sweetgreen, Cava, Five Guys, Panera).
- **Receipts (~20):** SROIE public dataset subset + a few manually photographed grocery receipts (label canonical ingredient mapping only, not macros).

**Why:** The eval narrative is the central rigor signal of the v2 portfolio plan. Without labeled ground truth, "MAE on photo→macros" is unverifiable. This is the single highest-priority unblocker for ML implementation work.

**Pros:**
- Unblocks the entire eval-numbers narrative for the portfolio.
- Web-sourced means no multi-week cooking discipline.
- Acknowledged biases (Nutrition5k = American dishes; SROIE = Asian retail) are honest disclosure for a portfolio.

**Cons:**
- Self-collected receipts add a small (1 evening) labeling task.
- Eval set has selection bias; not production-grade — fine for portfolio, would need broadening for a real product.

**Context:**
- Eval set lives at `evals/{stage_name}/` checked into the repo with a manifest YAML mapping image filename → labels. Use git-lfs or pointer file + R2 if image size exceeds reasonable git limits.
- CI runs evals on every PR touching the relevant ML stage. Compares against a baseline file.
- Expansion trigger: noise floor on a metric is too high to draw conclusions across runs.

**Effort:** S–M (CC handles dataset loaders, MenuStat scraping, manifest generation; user labels ~20 receipts).

**Priority:** P1 — blocks the eval narrative; should land before any ML pipeline work that claims numbers.

**Depends on / blocked by:** None. Can start immediately.

**Source:** /plan-ceo-review on 2026-05-10, refined in /plan-eng-review on 2026-05-10.

---

## P1 — Workflow framework migration: boilerplate → Pydantic AI

**What:** Migrate the 9-node meal-recommender DAG from the current boilerplate-based custom framework (`src/macronome/ai/core/`) to Pydantic AI. Build new ML pipelines (photo→macros, menu-photo, receipt-scan, recommendation) on Pydantic AI from day one. Document the choice in ADR-001.

**Why:** Boilerplate origin weakens any "I built a custom framework" portfolio narrative. The current implementation has unexplained slowness. Pydantic AI gives type-safety, modern signal, model-agnostic via its own provider abstraction (no LiteLLM dependency, sidesteps the LiteLLM security concern). Migration is a chance to fix the slowness with intent.

**Concrete migration steps:**
1. Diagnose the slowness on the current 9-node DAG (likely sync I/O blocking or excessive serialization).
2. Define typed state models (Pydantic) for what flows between agents.
3. Re-implement each node (NormalizeNode, PlanningAgent, RetrievalNode, SelectionAgent, InitialNutritionNode, ModificationAgent, QCRouter, ExplanationAgent, FailureAgent) as a Pydantic AI agent or step.
4. Eval before/after to confirm parity (or improvement) on regression cases.
5. Delete `src/macronome/ai/core/` once parity is confirmed.
6. Build the four new ML pipelines on Pydantic AI from the start.

**Pros:**
- Clean ownership story (no boilerplate baggage).
- Type-safe end-to-end; fewer mistakes.
- Modern signal; growing ecosystem.
- No LiteLLM dependency.

**Cons:**
- Pydantic AI API may evolve over the next 12 months; expect minor refactors.
- Migration itself is real work even with CC.

**Effort:** M (with CC; ~3 days human time → ~3–4 hours CC time for the migration scaffold + per-agent rewrites).

**Priority:** P1 — every new ML pipeline depends on this choice. Land before building any new agent code.

**Depends on / blocked by:** Choice locked in /plan-eng-review on 2026-05-10.

---

## P1 — Deploy-target abstraction interfaces (LLM/queue/blob/vector)

**What:** Spec the four deploy-target abstraction interfaces before writing new ML pipeline code. Concretely:

- **LLMClient** — Pydantic AI's own model abstraction handles this. Per-deploy config selects provider (OpenAI/Anthropic for free, Bedrock or same providers for AWS).
- **QueueRunner** — abstract interface with two implementations: CeleryRunner (Upstash Redis on free) and StepFunctionsRunner (AWS). Workflows are defined deploy-agnostic.
- **BlobStore** — abstract interface with two implementations: R2Store (Cloudflare R2 on free) and S3Store (AWS). Single put/get/sign API.
- **VectorStore** — pgvector-on-Postgres on both deploys. May not need an abstraction interface at all (single SQL primitive). Confirm during implementation.

**Why:** The dual-deploy story collapses if Macronome code couples to a single backend. Specifying interfaces *before* the implementation lands prevents retrofitting pain. Each interface is the explicit contract the deploy abstraction promises.

**Pros:**
- Forces clean separation between "what code does" and "where it runs."
- Both deploys testable from the same code paths.
- Strong portfolio signal (architecture diagram clear-eyed).

**Cons:**
- More upfront design work before implementation; risk of over-engineering interfaces no one uses.

**Concrete deliverable:**
- `src/macronome/backend/queue/` — interface + CeleryRunner + StepFunctionsRunner stubs
- `src/macronome/backend/storage/` — already has the interface pattern; extend with R2Store
- `src/macronome/backend/llm/` — Pydantic AI integration
- ADR-005 documents the abstraction pattern

**Effort:** S (CC handles the scaffolding; ~half-day human time → ~30 min CC).

**Priority:** P1 — land before building any new pipeline that calls these subsystems.

**Depends on / blocked by:** Pydantic AI choice (TODO #2). Free-tier stack lock (done). AWS deploy stack (Step Functions + S3 chosen).

**Source:** /plan-eng-review on 2026-05-10.

---

## P2 — Trained personalization model (when traffic justifies it)

**What:** Replace the v1 affinity reranker (cosine similarity + popularity prior + diet/cuisine affinity) with a trained implicit-feedback model — matrix factorization or two-tower — fit nightly on accept/skip/reject signals from logged meals. Add the offline training pipeline back into `Diagram 2` and the model artifact back as a load step in the live recommender.

**Why:** A trained personalization model is the right answer at scale. It captures non-obvious user preference patterns (cuisine affinities, ingredient combinations, time-of-day preferences) that hand-crafted affinity scoring misses. It also closes the data flywheel — user logs → model learns → recommendations improve → user logs more.

**Why deferred from v1:** Portfolio-scale traffic (~10–15 testers, ~5 logs/user/week, ~200 interactions/month with almost no overlap) doesn't generate enough data for matrix factorization or two-tower to learn meaningful embeddings. Eval (NDCG@k) would be noise. Shipping a trained model on this much data signals lack of sample-size judgment to a CTO. Affinity rerank is the honest portfolio choice.

**Trigger condition for revisit:** when *any* of:
- Active user count exceeds ~200 with regular logging cadence (multi-week retention).
- Recommendation acceptance-rate eval shows the affinity rerank is consistently outperformed by a trained baseline on synthetic preference data.
- A real opportunity to ship the project beyond portfolio (e.g., an actual product launch).

**Concrete plan when triggered:**
1. Build the offline training pipeline (Diagram 2 addition): pull last N days of (user, recipe, accept/skip/reject) tuples, train MF or two-tower, eval NDCG@k on held-out sessions, persist artifact.
2. Live recommender loads the artifact, replaces affinity rerank with model-based rerank.
3. Keep affinity rerank as fallback for cold-start users.
4. ADR documents the v1 → v2 transition.

**Pros:** Closes the data flywheel; better personalization at scale; standard ML systems pattern.

**Cons:** Premature without traffic; meaningless eval without enough users; signals poor judgment if shipped early.

**Effort:** M (with CC). Mostly the training loop scaffolding + artifact promotion.

**Priority:** P2 — explicitly future work, not blocking v1.

**Depends on / blocked by:** Trigger condition not yet met. Affinity rerank shipped first.

**Source:** Originally scoped in /office-hours; revised to affinity-rerank in /plan-eng-review on 2026-05-10 after sample-size pushback.
