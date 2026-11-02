# v2: open decisions

Questions left after the first build of the iOS app (2026-10-25). Each has a
recommendation; nothing below blocks trying the app in the simulator.

## Must decide before it's on your phone

### 1. Apple Developer Program ($99 US a year): probably not needed

Checked 2026-10-26 against Apple's capability table
(developer.apple.com/help/account/reference/supported-capabilities-ios). A free Apple ID
("Apple Developer" column) **does** include App Groups, Keychain sharing and background
modes, so the app, the widget sharing its log, the Lock Screen and Control Center widgets,
and the Keychain-stored API keys all work. App Shortcuts (Siri phrases) use App Intents,
which need no entitlement; the "Siri" capability is only for the older SiriKit intents.

What a free Apple ID costs you:

| Limit | Effect |
| --- | --- |
| Install expires after 7 days | Run from Xcode again (Mac and phone on the same Wi-Fi or a cable). Your data stays. |
| 3 free-signed apps per phone, 10 new app ids per week | Fine for this app; don't keep changing the bundle id. |
| No iCloud / CloudKit, no push | Backup has to be export or a sync server (decision 4). |
| No TestFlight, no App Store | Others build it from source, which fits "clone the repo". |

**Decided (2026-11-01):** a new personal Apple ID, free tier. Set your team and bundle id in
`ios/Config/Signing.local.xcconfig` (see `ios/README.md`), install, and renew weekly. Pay
only if the weekly renewal gets annoying or you want iCloud backup.

Not verified: an actual install on your phone. Xcode only shows whether the free team
accepts the App Group once you pick it.

### 2. Which iPhone: iPhone Air (settled)

The iPhone Air supports Apple Intelligence, so the on-device model works for the fast tier
at no cost. It refused the diet chat in testing, so it stays limited to small parsing jobs.

### 3. Models and who pays

A Claude Pro/Max subscription can't be used from a third-party app. Its "extra usage"
balance only covers Claude's own apps and Claude Code; API calls bill a separate Console
balance. So any Console credits you got are what the app can spend, and they don't refill
from the subscription. The app takes a key for whichever provider you pick, in Settings →
Models, in two tiers: Fast (logs the phone's parser missed) and Smart (chat, plate photos,
reading labels).

**Prices, checked 2026-10-26** (OpenRouter's live model list, Anthropic's and Google's
pricing pages), per million tokens, input / output. All of these do tool calling.

| Model | In / out | Photos | Notes |
| --- | --- | --- | --- |
| Qwen 3.7 Flash | $0.03 / $0.13 | yes | Cheapest capable option |
| DeepSeek V4 Flash | $0.09 / $0.18 | no | Text only |
| Gemini 2.5 Flash-Lite | $0.10 / $0.40 | yes | **Free tier** in Google AI Studio; free-tier requests may be used for training |
| Gemini 3.1 Flash-Lite | $0.25 / $1.50 | yes | Free tier too, newer |
| Claude Haiku 5.5 | $0.10 / $0.50 | yes | Same price as the others; prompt caching cuts repeat context to a tenth |
| GPT-6 Luna (OpenAI) | $0.10 / $0.50 | yes | |
| GLM 5.3 Flash | $0.15 / $0.50 | yes | |
| Gemma 4 31B | free on OpenRouter and Google | no | Free models are rate-limited and come and go |
| Claude Sonnet 5.5 | $2 / $10 | yes | The step up if the cheap ones aren't good enough |

What a chat turn costs: about 4k tokens in and 300 out with your library in the prompt.
That's under a tenth of a cent on Haiku 5.5, Luna or Flash-Lite, and roughly 1¢ on Sonnet
5.5. At 20 messages a day, the cheap tier is about 30¢ a month and Sonnet about $7. At
these prices quality decides, not cost.

On-device (your iPhone Air has it): free, but it refused "What's for dinner?" as a
guardrail violation, so it only does small parsing jobs.

**Recommendation:** get one OpenRouter key (one balance, every model above). Try Haiku 5.5,
GPT-6 Luna, Qwen 3.7 Flash and Gemini 3.1 Flash-Lite on the same questions and keep
whichever answers best. A Gemini AI Studio key is the free fallback. The app's presets now
point at these models.

#### Chat harness: do we need to build our own?

Yes, but it's small, and most of it already exists. The Claude Agent SDK is Claude Code
packaged as a Python/TypeScript library: it runs on a server, not on an iPhone, and
it's built for Claude. So it doesn't fit here whichever model we pick. The claude.ai app's
harness isn't something an app can borrow either.

What the app has today (`Services/AI/Core`): one request per chat turn. Your targets,
today's totals, foods and usual meals go in the system prompt, and the model answers with
meal options as JSON. The app then shows Plan / Log buttons under them. That's a workflow,
not an agent. It works with every provider through two adapters: OpenAI-compatible (which
covers OpenRouter, Gemini, DeepSeek, Groq, Qwen, Mistral, Ollama) and Anthropic's own API.

An agent loop (the model calls tools like "search my history" or "what did I eat last
Tuesday", the app runs them on the phone, and the model continues) is the next step once a
question needs data that doesn't fit in the prompt. All these providers accept tools in the
same OpenAI-style format, so it's one loop of about 200 lines on top of the existing
adapters. Logging would still go through the confirm card. Cross-provider frameworks
(Vercel AI SDK, LiteLLM, OpenAI's Agents SDK) are Python or TypeScript, so they only make
sense if a server is added later.

**No backend needed for chat.** The loop runs on the phone, its tools read the log on the
phone, and requests go straight from the phone to the provider with the key from the
Keychain. A server only becomes necessary for: a key you pay for that other people's
installs use (it can't ship inside the app), syncing or backing up the log, or work that
runs while the app is closed.

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

6. **Calorie bank.** Decided 2026-11-01: dropped. The app no longer shows or tracks it, and the
   chat never mentions it. The old `calorie_bank` note stays in the log, unused.
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
