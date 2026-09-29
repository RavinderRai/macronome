# Food log

Personal food tracking for Ravi. Append-only event log at `food-log/events.jsonl`, driven
by `food-log/fl.py` (stdlib only, no install). SQLite is built in memory on each run to
answer queries, so there is no database file. This is a v2 experiment and is deliberately
independent of `src/macronome/` — do not wire them together.

Run everything as `.venv/bin/python food-log/fl.py <command>` from the repo root. The
system `python3` is an Xcode shim that can block on a licence prompt after Xcode updates;
the venv interpreter never does. The script is stdlib-only, so any Python 3.9+ works.

## How to behave when Ravi logs food

**Known food, stated in text or voice.** Just log it. No questions, no confirmation step.

```bash
.venv/bin/python food-log/fl.py log "chicken breast" 150g
.venv/bin/python food-log/fl.py log "whey protein" "2 scoops"
```

Names resolve loosely, so `log "chicken" 150g` finds `chicken breast`. If the CLI reports an
ambiguous match, ask which one rather than guessing.

**Photo of a nutrition label.** Read the label, add the food to the library once, then log
what was eaten. Enter the numbers exactly as printed and set `--basis` to match whichever
the label is stated per. Say which numbers you read off so mistakes are visible.

```bash
.venv/bin/python food-log/fl.py food add --name "Oikos triple zero vanilla" \
  --basis serving --serving-grams 150 --serving-label cup \
  --kcal 120 --protein 15 --carbs 14 --fat 0 --fiber 3 \
  --aliases "oikos,greek yogurt" --source label_photo \
  --micros '{"sodium_mg": 65, "calcium_mg": 150}'
```

## Record every nutrient on the label

Macros are the required flags. Everything else the label prints goes into `--micros` as
JSON, so micronutrients sum across the day the same way calories do. **Use exactly these
keys**, because totals only add up when the spelling matches across foods:

```
sat_fat_g  trans_fat_g  sugar_g  added_sugar_g  cholesterol_mg
sodium_mg  potassium_mg  calcium_mg  iron_mg  magnesium_mg  zinc_mg  phosphorus_mg
vitamin_a_ug  vitamin_c_mg  vitamin_d_ug  vitamin_e_mg  vitamin_k_ug
thiamin_mg  riboflavin_mg  niacin_mg  vitamin_b6_mg  folate_ug  vitamin_b12_ug
omega3_g  caffeine_mg
```

Units are fixed per key. If a label gives a %DV with no absolute amount, convert using the
Canadian/US daily values (e.g. calcium 1300mg, iron 18mg, potassium 4700mg, vitamin D 20ug)
and say that you converted. If the label lists something not on this list, add it with the
same `name_unit` pattern and keep using that spelling.

Always set `--serving-grams` when the label gives it. That is what allows the same food to
be logged later as either `1 cup` or `170g`.

## Fiber and calories

How much of fiber's energy counts is a setting, not a decision to make per food. Ravi is
figuring out which convention matches the Cronometer history he already has, so do not
change the mode unless he asks.

```bash
.venv/bin/python food-log/fl.py fiber                 # same day scored under all four conventions
.venv/bin/python food-log/fl.py fiber --mode half     # switch, re-scoring every day already logged
```

The default is `auto`, and it should stay there. Most Canadian labels already count fiber
at ~2 kcal/g themselves -- their printed calories match `P*4 + (C-fiber)*4 + fiber*2 + F*9`
-- so deducting again double counts. `auto` compares each food's stated calories against
both conventions and deducts only when the label used 4 kcal/g. The fixed modes (`label`,
`half`, `net`, `split`) exist for comparing a day against another tracker. Switching is
retroactive because the deduction is applied when the log is replayed.

**When adding a food, check the label's own arithmetic**: if the printed calories are far
from both `P*4+C*4+F*9` and that minus twice the fiber, the label is wrong. Say so, and
store the 4 kcal/g figure so `auto` lands on the honest number (this is what was done for
the two canned beans).

**Always record `--fiber` when a food has any.** Also set `--fiber-soluble` and
`--fiber-insoluble` when the label breaks them out, or when the food is a clear case: bran,
wheat, nuts, and seeds are mostly insoluble, while oats, barley, beans, lentils, psyllium
and citrus carry a large soluble share. Do not agonize over it, and do not ask Ravi. The
split only affects `split` mode, but it has to be recorded as you go or that mode is not
available to him later.

The tool cannot tell when a label has already excluded insoluble fiber from its own calorie
figure, which would make the deduction count twice. Rare. Mention it only if an adjusted
number comes out obviously too low.

**Photo of packaged items with no label shown.** Identify each item, then ask for the label
photo, or add it from a reliable reference and mark `--source estimate`.

**Restaurant meal or a plated photo.** Estimate and log it as a one-off. Never add
restaurant guesses to the food library.

```bash
.venv/bin/python food-log/fl.py logx "chipotle chicken bowl" \
  --kcal 850 --protein 45 --carbs 90 --fat 32 --meal lunch --source photo
```

**Unlabelled whole foods** (chicken breast, eggs, rice, produce). Use a reliable per-100g
reference, add it with `--source usda`, and state the reference values you used.

## The widget

When Ravi asks how many calories or macros he has left, or what he has eaten so far, render
the picture and send it to him rather than only quoting numbers. He reads this on his phone.

```bash
.venv/bin/python food-log/widget.py            # writes food-log/widget.png for today
.venv/bin/python food-log/widget.py --date yesterday --out /tmp/w.png
```

Then call `SendUserFile` with the PNG path, `display: "render"`, `status: "normal"`. Add the
one-line summary in text as well so it survives if the image does not load. Regenerate every
time; never resend a stale image after a log.

## Checking state

```bash
.venv/bin/python food-log/fl.py today               # entries, totals, distance from target
.venv/bin/python food-log/fl.py remaining           # just the gap to targets
.venv/bin/python food-log/fl.py range --days 7      # per-day totals and averages
.venv/bin/python food-log/fl.py today --json        # when you need to reason over the numbers
.venv/bin/python food-log/fl.py food list yogurt    # search the library
```

Anything the CLI does not cover, query directly. Reads only:

```bash
.venv/bin/python food-log/fl.py sql "SELECT eaten_on, SUM(protein) p FROM entries GROUP BY 1"
```

## Constraints and targets

Daily targets drive `remaining` and the "vs target" line:

```bash
.venv/bin/python food-log/fl.py targets set --kcal 2600 --protein 180 --carbs 260 --fat 80
```

Carbs are shown as **net carbs** (total minus fibre) and fibre has its own row; this is
`carb_mode = net` in the profile. The net-carb target shrinks slightly as fibre is eaten,
so that hitting protein, fat, and net carbs exactly means hitting calories exactly. Fibre
is a floor, not a budget: exceeding it is good and is never shown as "over". Do not switch
back to `total` unless Ravi asks.

A target that applies to one day only (making up for going over, a planned refeed) is an
override, not a change. Ravi does not lower targets just because a day is a rest day: `targets set --date today --kcal 1500 --carbs 120`. Keep protein and fat, take the
difference out of carbs unless Ravi says otherwise. Other days keep the standing targets.

Standing constraints (diet type, allergies, dislikes) go in the profile so they survive
across chats. Constraints that apply to a single day go in a day note.

```bash
.venv/bin/python food-log/fl.py profile set diet "vegan"
.venv/bin/python food-log/fl.py note "fasting until 2pm"
```

Run `profile show` before making any food recommendation.

## Staple meals

Ravi eats on a rotation. Meals he has described are stored in the profile under `meal_*`
keys (e.g. `meal_potato_bowl`) with the components and default amounts. When he names one
("had the potato bowl", "usual post-gym lunch"), read the profile entry and log each
component as its own `log` line, using his stated amounts where given and the defaults
otherwise. Do not add the meal itself to the food library as one item, because the amounts
vary and he wants each ingredient's numbers to stay honest.

## Rules

- **Never do the arithmetic yourself.** Run the command and report what it prints. The
  entire point of this tool is that the numbers are computed rather than estimated.
- **Entries snapshot their macros.** Correcting a food with `food update` does not rewrite
  past entries, which is intentional. To fix a past entry, `rm` it and log it again.
- **Confirm before deleting.** `undo` removes the last logged entry, `rm <id>` removes a
  specific one (id prefixes work). Show what will go before removing it.
- **Adding a food is a commitment.** Check `food list` first so the library does not
  accumulate three spellings of the same yogurt.
- Batch the work: if Ravi lists five things he ate, run five `log` commands, then `today`
  once at the end.
- Backfill with `--date yesterday` or `--date 2026-09-05` rather than editing history.

## Record the friction

This is a trial. The point is to find out where logging hurts, so append a line to
`food-log/friction.md` whenever any of these happen, without being asked and without making
a fuss about it:

- a log took more than one exchange to get right
- Ravi says something was annoying, slow, or not worth it
- a meal got logged late or not at all, and he says why
- the tool gave a wrong number, a confusing error, or could not express what he ate

Note what it cost, not just what happened. "Had to walk to the desk to log lunch" is the
useful version. Do not log routine successes.

## Persistence

`events.jsonl` is the source of truth and is committed to git, which is the only backup.
Nothing is lost if a session dies, but nothing is backed up until it is committed either.

```bash
.venv/bin/python food-log/fl.py sync -m "food log"     # pull, commit only events.jsonl, push
```

Run `sync` at the end of a logging session, or whenever Ravi asks. It touches no file other
than the event log. The log is set to `merge=union` in `.gitattributes`, so if two machines
ever append at the same time, git keeps both sets of lines and duplicate events are
de-duplicated by id when read.
