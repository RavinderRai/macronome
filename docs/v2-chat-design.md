# v2: chat flow, memory and tools

How the app's chat should work so it feels like the last seven weeks of logging through
Claude Code. The screens are on the design canvas, in the row "Logging and asking in one
place" (https://claude.ai/artifact/52b8KZ1VtiuKVgmFLb2xi7). 

Built (2026-11-01): the agent loop, the tools, the cards in the chat sheet, memory items
and the numbers check (`ios/Macronome/Services/AI/Core/ChatAgent.swift`, `ChatTools.swift`,
`ChatCards.swift`, `Agent.swift`). Not built yet: routing from the Today bar to the agent
(the bar still uses the local parser, then the fast model), the computed bank and
`bank_override`, the snack-day size of the evening bowl, deferred amounts as a pending
part, hands-free mode, and the memory screen's tabs.

## Principles (from how Ravi logs today)

1. **Work it out, say what was assumed.** Speech-to-text mishears ("full bowl" comes out
   as "pull a ball"). The model reads each message against the foods, meals and routine
   and resolves it fresh; mishearings are one-off noise and are never stored. The reply
   says what it assumed in one line ("I took X to mean Y; tell me if not") and logs anyway.
   The only question asked before logging is an implausible number. To cut mishearings at
   the source, the speech recognizer is given the food and meal names as contextual
   strings (`SFSpeechRecognitionRequest.contextualStrings`).
2. **Logs don't need confirming.** Every log lands at once, on a card with Undo and Edit.
3. **Every number is computed by the app, never by the model.** The model chooses foods
   and amounts; the ledger does the arithmetic, and cards render the ledger's numbers.
4. **The evening bowl is held back in every budget.** It can shrink (¾ cup, or the snack-day
   size), never be dropped or swapped.
5. **Every log ends with a status:** what was logged, what's left (kcal, P, C, F), and
   dinner with the bowl held back.
6. **Short.** Small tables, one-line answers to one-line questions, no repeating the plan.

## One bar, one thread

There is one input: the bar on Today (text, mic, camera) and the same bar inside chat.
Both write to the same day thread, so chat always knows what was logged from Today.

```
input ─► local parser (on the phone, free, offline)
           │ every part matched a known meal/food, no question in it
           ├────────────► log ─► card on Today   (no model call)
           │
           └─ otherwise ─► agent turn (model + tools)
                             │ only logs/corrections
                             ├─► card on Today
                             │ anything else (plan, what-if, question, targets)
                             └─► chat sheet opens with the answer
```

A message can do several things at once ("for today, standard breakfast and poutine…
what's for dinner?"): it logs first, then answers in chat.

## Intents

| Intent | Example | What happens | Card |
| --- | --- | --- | --- |
| Log a usual meal | "log standard breakfast" | Expands into its parts | Logged |
| Usual meal with amounts | "standard poutine, 310 g potatoes, 230 g cauliflower" | Fixed parts from the meal, given amounts for the variable ones | Logged |
| Deviation | "standard breakfast but 35 g cereal" | Meal with one part changed | Logged |
| Several meals or days | "last night the full bowl, today breakfast and nachos" | Each item on its own date and slot | Logged, grouped by date |
| Pre-log | "log the bowl now, I'll have it later" | Logged now, slot evening | Logged |
| Estimate | "forgot to weigh the lettuce, use 165" | Entry marked as an estimate | Logged, with Estimate tag |
| Deferred amount | "cauliflower isn't cooked yet" … later "300 grams" | Placeholder entry, filled by the next bare amount | Logged (pending part) |
| Correction | "actually 13 g of seasoning", "I said full bowl" | Edits the last matching entry | The earlier card updates in place |
| Plan | "what should I have for dinner?" | 3–5 options against the budget with the bowl held back | Options table |
| What-if | "with 2 slices, or none?", "how much potato and cauliflower can I have?" | Computes variants, or solves for amounts | Small table |
| Close the loop | "had it, one slice, 160 g lettuce" | Logs the option being discussed, with changes | Logged |
| Targets | "week nine: 1550, protein 155, rest from carbs" | Works out the macros, applies from today | Old → new |
| Remember | "I can't taste the nutritional yeast" | Writes a memory item | Remembered, with Undo |
| Side question | "no russets, white or yellow?" | Plain answer | None |
| Label photo | camera | New food from the panel | New food (existing screen) |

## Cards

- **Logged** (deep amber): items grouped by date, an assumption line when one was made,
  Estimate tags, then the status block and Undo / Edit. On Today it floats above the bar;
  in chat it sits in the thread.
- **Implausible amount**: the one pre-log question. Two buttons: the likely amount
  (with its kcal) and the amount as heard.
- **Options table**: columns dinner / kcal / P / spare-or-over. Protein in amber when it
  hits the target. Rows that don't fit are greyed with "N over" in coral. The held-back
  bowl is the last, hatched row. One trade-off line underneath. Tapping a row starts a
  what-if on it.
- **What-if table**: same columns, one row per variant, then one line naming the answer.
- **Targets**: was → now for kcal, protein, net carbs, fat, and where the cut came from.
  Applied at once, with Undo.
- **Remembered**: kind and the remembered sentence, with Undo. Links to the memory screen.
- **Bank line** (inside Logged): offered only when the day lands just over. "Don't bank
  today" turns today's surplus or overage into a no-op for the bank.

## Agent turn

One loop on the phone (`Services/AI`), the same for every provider: send the context and
tools, run any tool calls locally, send results back, repeat until the model answers.
OpenAI-style tool calling covers OpenRouter, Gemini, DeepSeek, Groq and Ollama; the
Anthropic adapter translates. No server.

**Context sent every turn** (small, cacheable, most stable first):

1. System prompt: the principles above, tone, card rules.
2. Profile: diet, targets for today.
3. Memory: all items (rules, meals with their parts, likes, facts). It's a few kilobytes.
4. Today: entries so far, what's left, the bowl budget, the bank.
5. The day's thread.

History, frequencies and older days are **not** in the context; the model calls tools for
them.

**Numbers rule, enforced in code:** a reply may only show numbers that came from a tool
result in this turn or the context. Cards are built from tool results, never from the
model's text. If the model writes a number a tool didn't produce, the app reruns the turn
with a correction ("use preview for every total"). This is what made the Claude Code flow
trustworthy.

## Tools

All run on the phone over the `Ledger`.

| Tool | Does | Writes? |
| --- | --- | --- |
| `log(items, date, slot)` | Logs foods or meals with amounts; marks estimates, pending parts | Yes, Logged card |
| `edit_entry(id, changes)` / `delete_entry(id)` | Corrections | Yes |
| `preview(items, date)` | Totals and what's left if these were eaten, bowl held back | No |
| `solve(meal, free_parts, budget)` | Amounts of the variable parts that fit a budget | No |
| `budget(date)` | What's left, the bowl hold-back, dinner budget, bank | No |
| `find_food(query)` / `get_meal(name)` | Library lookup, with aliases | No |
| `frequent(slot?, days=30)` | Most-eaten meals and foods, typical amounts | No |
| `history(start, end)` / `search_entries(query, days)` | Day totals; when something was eaten | No |
| `set_targets(targets, from)` | Applies new targets | Yes, Targets card |
| `remember(kind, text, data)` / `forget(id)` | Memory | Yes, Remembered card |
| `bank_override(date, mode)` | "Don't bank today" | Yes |
| `add_food(fields)` | From a label or a description | Yes |

`preview` and `solve` are the what-if engine: the model proposes, they compute.

## Memory

Stored as events in the same `events.jsonl` (`memory_set`, `memory_delete`), so it syncs,
backs up and replays like everything else. Today's free-text `profile_set` notes are
imported once as items; fl.py ignores the new event types.

```json
{"type": "memory_set", "id": "m-…", "kind": "like",
 "text": "Salads come without bread",
 "data": {"applies_to": "salad"},
 "source": {"thread": "2026-11-01", "message": "…"}, "ts": "…"}
```

| Kind | Holds | Used for |
| --- | --- | --- |
| `rule` | Constraints applied to every plan: bowl hold-back, snack-day bowl, bank tone, "always show kcal and protein", what to cut first | Budgets, options |
| `meal` | Usual meals: fixed parts, variable parts with range and default, aliases, slot, prep time, verdict | Expansion, planning |
| `like` | Preferences and verdicts: cinnamon for breakfast, hoops in the evening, pancakes not filling | Choosing options |
| `fact` | Diet, allergies, equipment | Everything |

Meals are already structured (`meal_set` events with components); `meal` memory adds
ranges, defaults and aliases to them.

**How memory gets written:** the model calls `remember` when Ravi states a preference or
corrects something, and a Remembered card shows it with Undo. Nothing is remembered
silently, and a correction to a mishearing ("I said full bowl") fixes the entry without
writing memory.

**What is not memory:** how often things are eaten and typical amounts. That is worked out
from the log by `frequent`, so it never goes stale. When the log drifts from a meal's
default (the last 15 potato bowls averaged 308 g potato and 207 g cauliflower against a
350 / 80 default), the memory screen offers to update the default.

## How it connects

- **Ledger:** every write is an event; Today, History, the widget and the chat all replay
  the same log.
- **Widget:** reloads after every write, so a log from chat shows on the home screen at
  once.
- **Bank:** computed from the log from a start date, plus `bank_override` days, instead of
  the hand-kept note. A day closes at midnight (decided 2026-11-01); there is no explicit
  "close the day". Until then a log that lands over says what the bank will be at
  midnight.
- **Memory screen:** Settings → What it remembers, tabs Rules, Meals, Likes, Usuals.

## Open questions

1. **Bank start.** Start the computed bank from 6.3 on 1 Nov, or recompute it from day one?
2. **Read replies aloud.** Wanted in hands-free mode, or text only?
3. **Thread length.** One thread per day (a fresh chat every morning, older days in
   History), or one running thread?
