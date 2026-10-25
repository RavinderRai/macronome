# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Macronome v2: a personal macro tracker driven by voice, text and photos, with a home-screen
widget for what's left today. It is being rebuilt from scratch on `main`.

The v1 app (Expo + FastAPI, still on Google Play) lives on the `legacy/v1` branch and the
`v1-legacy` tag. Don't bring v1 code back onto main; read it from that branch if needed.

## food-log

`food-log/` is the tracker in daily use until v2 replaces it (SQLite + a stdlib CLI). If
the user talks about logging food, macros eaten, or what is left for the day, read
`food-log/CLAUDE.md` and use that tool.

## Design

`docs/design/v2-app/` holds the v2 screen designs and color tokens. Follow them when
building the app.

## Keep on main

`PRIVACY_POLICY.md` and `ACCOUNT_DELETION.md` are linked from the Play Store listing.

## Code Conventions

Keep Python imports at the top of the file.
