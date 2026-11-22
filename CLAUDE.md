# Fires of Olympus

Godot 4.7 card/board game (Catan / King of Tokyo complexity). GDScript only, no C#
(C# can't export to Web in Godot 4). Renderer: GL Compatibility (required for Web, fine on iOS).
Targets: Web (primary for playtesting) and iOS. Landscape 1920x1080 base, `canvas_items` stretch.

## Toolchain
- Godot: `/Applications/Godot.app` (4.7.2-stable), CLI `godot` on PATH
- Export templates: `~/Library/Application Support/Godot/export_templates/4.7.2.stable/`
- Xcode for iOS builds

## Commands
- `tools/build.sh test`   — headless unit tests (`tests/test_*.gd`, includes 300 full bot games); fails on any SCRIPT ERROR
- `tools/build.sh check`  — headless import; catches script parse errors
- `tools/build.sh web`    — static site in `build/web/` (single-threaded: no COOP/COEP headers needed, works on itch.io / GitHub Pages)
- `tools/build.sh serve`  — build web and serve on http://localhost:8060
- `tools/build.sh ios`    — Xcode project in `build/ios/`; open it in Xcode to sign and run
- `tools/build.sh sim`    — build + install + launch on an iPad Simulator (no signing needed; uses the x86_64 sim slice under Rosetta)
- Add `debug` as a 2nd arg for debug builds.
- `godot -- --start` launches straight into a game (seat 1 human); `godot --headless -- --autoplay` plays an all-CPU game and quits (UI smoke test).
- iOS export needs `application/app_store_team_id` set in `export_presets.cfg` (currently blank).

## Layout
- `design/rules.md` — the designer's rules; `design/rules_interpretations.md` — how ambiguous rules are implemented (keep in sync with code)
- `design/roadmap.md` — release milestones and scope decisions; tick items off as they land
- `data/*.csv` — card text exported from the design spreadsheet (imported as "keep" files so they ship as-is)
- `assets/` — art, audio, fonts copied from the earlier React Native prototype (`foo-native-web-test`)
- `scripts/rules/` — pure rules engine, no Nodes:
  - `card_data.gd` (CardData): loads CSVs; `DEFS` holds each Ingredient's behaviour. Tests fail if CSV and DEFS disagree.
  - `scoring.gd` (Scoring): Challenge card rules (Successes / penalties) on final die values
  - `game.gd` (FoGame): seeded state machine. Read `phase` + `current`, call `act_*` / `apply_reaction` / `finish_reactions`.
  - `bot.gd` (FoBot): CPU players. Levels Easy / Normal / Hard and named personas (`PERSONAS`, a bias on the
    heuristic). `step()` makes one decision; the UI uses `plan()` + `Plan.advance(ms)` so Hard's look-ahead
    (rollouts on `FoGame.clone()` with reseeded dice) is spread over frames. Never draws from `g.rng`.
- `scripts/main.gd` — pass-and-play UI built in code; only reads FoGame state and forwards clicks
  (sounds fire by diffing FoGame state between redraws, so CPU moves are audible too)
  Results screens come from `FoGame.history`; CPU turns wait while an overlay (results, zoom, menu, hand-off) is open.
  Die explanations come from `FoGame.die_breakdown` (same code path as `die_value`).
- `scripts/ui_kit.gd` (FoUI) — the look: colours, global Theme, card tiles, dice, chips. No game logic.
  Animations (dice tumble, card flights, overlay fades) live in main.gd, are skipped when
  `FoSettings.reduce_motion`, `--autoplay` or not in the tree, and CPU turns wait for them (`_busy()`).
- `scripts/save.gd` (FoSave) — single save slot `user://save.json`: names, bots, seed and `FoGame.moves`.
  Loading replays the moves (`FoGame.replay`); a save whose moves no longer apply is ignored.
  Anything that draws from `FoGame.rng` outside an `act_*` call (e.g. the bot) would break replay.
- `scripts/settings.gd` (FoSettings) — volumes, CPU speed, text size, reduced motion in `user://settings.cfg`.
  Scale font sizes with `FoUI.fs()` (FoUI.label/heading already do).
- `scripts/rules_text.gd` (FoRulesText) — the in-game "How to play" summary; keep it in step with `design/rules.md`.
- main.gd only writes saves/settings when `persist` (off in tests and `--autoplay`).
- `scripts/assets.gd` (FoAssets) — maps CSV art names / card names / game events to files in `assets/`
  (`ART_ALIASES` for renamed images, `MISSING_ART` for cards with no image yet, `INGREDIENT_SOUNDS`, `SFX`).
  Pixel art is nearest-upscaled at load. Web export excludes the duplicate music `.ogg`.
- `tests/` — tiny built-in runner (`run_tests.gd`), no addons

## Conventions
- Commit `*.import` and `*.uid` files; only `.godot/` and `build/` are ignored.
- Keep game rules (pure logic, no Nodes) separate from presentation so rules can be unit-tested headless.
- New card: add the row to the CSV *and* an entry in `CardData.DEFS` (Ingredient) or `Scoring` (Challenge).
- All randomness goes through `FoGame.rng` so a seed replays a whole game.
