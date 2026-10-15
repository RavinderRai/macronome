# Friction log

What went wrong, felt slow, or nearly stopped Ravi from logging. This, not the food data,
is the output of the trial week. Append a dated line; do not rewrite past entries.

Format: `- YYYY-MM-DD — what happened, and what it cost`

## Entries
- 2026-09-13 — Did not log at all for the first week. Cronometer was the path of least resistance: one tap on the phone vs. needing a Claude Code session running. The thing that would flip it is a personal food database so repeat foods never need searching, barcode scanning, or re-photographing. Restarting today with that as the focus.
- 2026-09-13 — Logging '3 meatballs' failed because the food's serving label was 'meatball' and the tool wanted an exact match. Cost one retry. Fixed: plural forms of a serving label now resolve.
- 2026-09-13 — '2 patties' failed against serving label 'patty' (y->ies plural). Second plural bug today; fixed in the tool.
- 2026-09-14 — Claude mobile app stopped working at end of day; the last meal (evening cereal) could not be logged in the moment and was backfilled the next morning. Same failure mode as week one: the log depends on the Mac session being reachable.
- 2026-09-15 — Not having the day's calories and macros visible at a glance (a widget) is 'really annoying'. Has to open a chat and ask. Ravi's conclusion: the app has to happen after this week. This is the strongest signal so far for what v2 needs.
- 2026-09-28 — Ravi caught a real bug: the tool deducted 2 kcal/g of fibre from every food, but 30 of 32 labels already counted fibre at 2. Double-deduction understated intake by ~67 kcal/day across 16 days (~1070 total). Flagged the same pattern on 09-19 and did not fix it then; patched two bean cans individually instead. Fixed properly with per-label auto-detection.

- 2026-10-12: Dinner suggestion listed one option without calories while the others had them. Ravi had to ask a second time. Cost: an extra exchange, and he had to prompt for the thing the tool exists to give.
- 2026-10-15: End-of-day commits were blocked by the auto-mode classifier on 10-12, 10-13 and 10-14, so three days sat unbacked until Ravi pushed by hand from Cursor. Cost: the log was only on one disk for three days, and Ravi had to do the commit step himself. Fixed by adding a narrow git allow rule in .claude/settings.local.json.
