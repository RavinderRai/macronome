# v2: open decisions

Questions left after the first build of the iOS app (2026-10-25). Each has a
recommendation; nothing below blocks trying the app in the simulator.

## Must decide before it's on your phone

### 1. Apple Developer Program ($99 US a year)

Without it, Xcode can still install the app on your iPhone with a free Apple ID, but:

- The app stops opening after 7 days and has to be reinstalled from Xcode.
- Free (personal team) signing is limited in capabilities and, as far as I know, doesn't
  include App Groups; Xcode will say so when you pick your personal team. The widget reads
  the log through an App Group, so without it the widget would show nothing. The app
  itself still works, because the store falls back to its own folder.
- No TestFlight and no iCloud backup.

**Recommendation:** start free to try it for a week, and pay once you're logging with it
every day. The widget is the main reason the app exists, so you'll want the paid
account soon.

### 2. Which iPhone

Apple's on-device model (free, offline, private) needs an iPhone 15 Pro or newer with
Apple Intelligence on. With it, the fast tier costs nothing. Without it, the fast tier
needs a cheap cloud model.

### 3. Models and who pays

A Claude Pro/Max subscription can't be used from a third-party app; Anthropic only allows
the subscription in its own apps and Claude Code. The app instead takes an API key for the
provider you choose, set in Settings → Models in two tiers:

| Tier | Used for | Suggested |
| --- | --- | --- |
| Fast | Logs the phone's parser couldn't match | On-device if your phone has it, else Gemini Flash-Lite or Groq (both have free tiers) |
| Smart | Chat, meal ideas, plate photos, reading labels with vision | Claude Haiku 5.5 via API (cheap), Sonnet 5.5 if Haiku's answers aren't good enough |

Most logging never reaches a model: usual meals and known foods are matched on the
phone.

Tested in the simulator: Apple's on-device model refused "What's for dinner?" as a
guardrail violation, probably because the prompt is about calorie limits. So the on-device
model is fine for small parsing jobs at best, and the chat needs a cloud model. A chat turn with your full library is about 4k input tokens, so well under a
cent on Haiku 5.5 and around a cent on Sonnet 5.5, less with prompt caching.

**To do:** check whether your Anthropic account has API credits. API billing (console)
and the claude.ai subscription are separate. If there are credits, use Anthropic for
Smart.

The model names in the app's presets are placeholders; check them when you add a key.

### 4. Where the log lives once the app takes over

Right now there are two logs: `food-log/events.jsonl` (Claude Code) and the copy the
app imported on first launch. They'll drift apart as soon as you log in either one.

**Recommendation:** pick a cutover day. Import the latest `events.jsonl` (Settings → Data
→ Import), then log only in the app. Export from Settings when you want Claude Code to
see it again. Both use the same format, and fl.py ignores the app's extra event types.

Backup is the open question. Options, cheapest first:

- Manual export now and then (free, easy to forget)
- iCloud via CloudKit (free, needs the paid developer account)
- A small sync server later (whichever cheap host you pick)

### 5. Personal data in a public repo

The repo is public, so `food-log/events.jsonl` (six weeks of what you ate, plus profile
notes) is already visible, and the app bundles it when building. Before posting on
LinkedIn, decide whether to keep it as a real demo dataset or move it out of the repo
(and its history) and ship a small sample dataset instead.

## Product questions from the build

Smaller calls. Each has a current behaviour, so none blocks using the app.

6. **Calorie bank.** It's a hand-kept note in the profile ("15 - built 10-12 to 10-16…").
   The app reads the number, and History shows each day as saved/spent. Should the app keep
   the bank itself from a start date? And should "Use bank" on a log become a one-day
   override that draws it down? (Now it only mentions the bank.)
7. **"Yesterday" / "last night" in a log.** Should saying it backdate the entry? Now it
   logs to today.
8. **"Potato" alone.** The parser reads it as the Potato bowl (your alias) and only logs
   russet potato when there's an amount ("300 g potato"). Right?
9. **Chips when plans exist.** The TodayPlanned design hides the meal chips. They're kept for
   now. Hide them?
10. **Targets onboarding.** "Work these out for me" (AI-suggested targets) was dropped for
   "Skip the labels for now". Want it back?
11. **Allergies.** Stored under a new `allergies` key next to your existing `dislikes`.
   Merge them?
12. **Label edge cases.** "<1 g" is stored as 0.5 g and flagged. Potassium converts at
   4,700 mg per food-log/CLAUDE.md, though Canada's daily value is 3,400 mg. Which?
13. **Product names.** A nutrition panel never shows the product name, so you type it after
   a scan. Also photograph the front of the package?
14. **Smaller ones:** History "Month" is a calendar month (or last four weeks?); meal
   components can't hold notes like "usually 300–400 g raw"; Memory doesn't record which
   notes were corrections; History draws days over target in coral (the artboard used
   off-white).
15. **Fonts.** The designs use Geist and Geist Mono (free, OFL). The app uses SF Pro and SF
    Mono for now. Bundle Geist?
16. **App name and bundle id.** `com.macronome.app`, display name "Macronome". Fine?

## Not tested yet

- Anything on a real iPhone: the live label scanner, speech, the widgets on a home screen,
  Siri phrases.
- Any real model call (no keys were used).
- Layout of every screen was not checked one by one; Today, Foods, History, Settings, the
  chat sheet, listening and the widget preview were.
