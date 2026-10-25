# Macronome

A personal macro tracker you talk to. Say or type what you ate, photograph a label once,
and see what's left for the day from your home screen.

This is v2, being rebuilt from scratch.

## What's here

- `ios/`: the v2 iPhone app (SwiftUI, widgets, Siri). See `ios/README.md`.
- `food-log/`: the current tracker, a stdlib Python CLI over an append-only event log,
  driven by chatting with Claude Code. v2 starts from what this taught (`food-log/friction.md`).
- `docs/design/v2-app/`: screen designs for the v2 app.
- `PRIVACY_POLICY.md`, `ACCOUNT_DELETION.md`: linked from the Google Play listing.

## v1

The first version (Expo app, FastAPI backend, meal-recommendation workflow, pantry
scanner) is on the [Play Store](https://play.google.com/store/apps/details?id=com.macronome.app).
Its code lives on the `legacy/v1` branch and the `v1-legacy` tag.
