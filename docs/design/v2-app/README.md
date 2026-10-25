# v2 app design

Screen designs for the standalone food-log app that replaces logging through a Claude Code
session (`food-log/`). Made on 2026-10-24.

Live canvas, where the screens can be viewed and clicked through:
https://claude.ai/artifact/52b8KZ1VtiuKVgmFLb2xi7

The files here are copies of that canvas so the designs survive without it. Each
`.dc.html` file is one artboard in the canvas's component format: plain HTML with inline
styles, but it loads `./support.js` from the canvas runtime, so it will not render
correctly opened directly in a browser. Read them as the source of truth for layout,
copy, sizes and colors. `canvas.json` is the canvas index (artboard positions and titles).

## Why the app exists

Two problems with logging through Claude Code (see `food-log/friction.md`):

- No glanceable "calories left" on the phone. A home-screen widget is the fix.
- Logging stops working whenever the Mac session or Remote Control drops. The fix is a
  hosted backend, so the phone never depends on the Mac.

## Direction

**Instrument**, chosen over two alternatives ("Color blocks" and "Night ledger", in
`screens/TodayBlocks.dc.html` and `screens/TodayLedger.dc.html`).

- Today is the home screen: one large calories-left numeral, a ruler-style day strip
  (solid = eaten, hatched = planned, coral = past the target), and three macro columns.
- One command bar at the bottom for both logging and asking, by voice, text or camera.
  Logs never ask first; a confirmation card appears after, with Undo and Edit.
- Questions open the chat as a sheet over Today. Plans from the chat land on Today as
  dashed "planned" entries.
- Usual meals sit above the command bar as one-tap chips.

## Color

Dark mode is the default.

| Token | Hex | Use |
| --- | --- | --- |
| Graphite | `#111210` | Page |
| Surface | `#1A1B19` | Cards, sheets |
| Bar | `#232421` | Command bar, chips |
| Text | `#EDEDE8` | Primary text, net-carbs bar |
| Text 2 / 3 | `#B4B6AE` / `#9A9C95` | Secondary text, labels |
| Hairline / track | `#2A2B28` / `#2C2D2A` | Dividers, empty bars |
| Amber | `#FFB547` | The mic, protein, and nothing else |
| Deep amber | `#2B1F0E` | Only the listening panel, the confirmation card and the row just logged |
| Coral | `#FF7A66` | Over target only |
| Fat | `#7F827A` | Fat bar |

Type: Geist for text, Geist Mono for every number.

`archive/light-orange/` holds the first version of every screen (light paper ground,
signal orange accent) before the switch to dark and amber.

## Screens

| File | Screen |
| --- | --- |
| `Foundations` | Colors, type and components |
| `Welcome`, `Targets`, `PantryScan`, `PantryReview` | Onboarding |
| `Main` | Today |
| `ChatSheet` | Chat sheet planning dinner |
| `TodayPlanned` | Today with planned meals |
| `Listening` | Voice capture with live matching |
| `Logged` | Confirmation card after a log |
| `LoggedEdit` | A misheard log being corrected |
| `LabelScan`, `NewFood` | Label camera and the new-food form |
| `PlatePhoto` | Restaurant plate estimate (logged as a one-off) |
| `EntryDetail` | One logged entry with its micronutrients |
| `Foods`, `FoodDetail`, `MealDetail` | Food library, a food, a usual meal |
| `History` | Week view and the calorie bank |
| `Settings`, `Memory` | Settings, and the notes it has learned about you |
| `Widgets` | Android home-screen widgets |
