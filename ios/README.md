# Macronome for iOS

Native SwiftUI app plus home-screen widgets. All data stays on the phone: the app keeps
the same append-only `events.jsonl` as `food-log/`, replays it into foods, entries and
targets, and the widgets read that same file.

## Run it

```bash
brew install xcodegen
cd ios
xcodegen generate
open Macronome.xcodeproj
```

Pick the `Macronome` scheme and an iPhone simulator, then run. To install on a phone, set
your team under Signing & Capabilities for both the `Macronome` and `MacronomeWidget`
targets.

The Xcode project is generated from `project.yml`, so edit that file (not the project)
when adding targets or settings. New Swift files under `Macronome/`, `Shared/` or
`MacronomeWidget/` are picked up on the next `xcodegen generate`.

When `food-log/events.jsonl` and `food-log/meals.jsonl` exist, they are bundled and
imported on first launch, so the app opens with the full history. A fresh clone without
them starts at onboarding.

## Layout

| Folder | What's in it |
| --- | --- |
| `Shared/Core` | The ledger (a port of `food-log/fl.py`), event codec, store, formatting. Compiled into the app, the widget and the tests. |
| `Shared/Design` | Colors and type from `docs/design/v2-app`. |
| `Shared/Intents` | Intents the widget buttons and Control Center use to open the app. |
| `Macronome/App` | App entry, router, root view. |
| `Macronome/Components` | Shared views: command bar, day strip, macro columns, rows, buttons. |
| `Macronome/Screens` | One folder per area, one file per design artboard. |
| `Macronome/Services` | Log parsing, speech, label reading, the model layer. |
| `Macronome/Intents` | Siri and Shortcuts: log a usual meal, calories left. |
| `MacronomeWidget` | Home-screen, Lock Screen and Control Center widgets. |
| `MacronomeTests` | Parity tests against `fl.py`, parser tests. |

## Tests

```bash
xcodebuild test -project Macronome.xcodeproj -scheme Macronome \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

`ParityTests` replays `food-log/events.jsonl` and checks every day's totals against
`MacronomeTests/fl-range.json`, which is `fl.py range --json` over the whole log.
Regenerate the fixture after logging more with food-log:

```bash
.venv/bin/python food-log/fl.py range --start 2026-09-01 --end 2026-12-31 --json > ios/MacronomeTests/fl-range.json
```

## Models

Nothing needs a model to log a known food or a usual meal: the parser runs on the phone.
Models are optional and configured in Settings → Models, in two tiers:

- **Fast** (parsing what the local parser missed): Apple's on-device model when the
  phone supports it, which is free, or any cheap cloud model.
- **Smart** (chat, plate photos, reading a label with vision): an OpenAI-compatible
  endpoint (OpenRouter, Groq, Gemini, OpenAI, Ollama…) or Anthropic, with your own key.

Keys are stored in the Keychain on the phone and requests go straight to the provider.
