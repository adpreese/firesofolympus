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
- `tools/simulate.sh [GAMES] [opts]` — parallel all-CPU (Hard) games -> `build/sim/<run>/part*.jsonl` + `report.md`
  (`tools/analyze_sim.py`); resumable. `--variant a,b` tests rule variants (`FoGame.VARIANTS`).
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
  Challenge results show on the mats (`FoGame.quest_rows`); a new Quest gets a banner from `FoGame.history` (`_show_banner`: table fades to black, spaced gold Cinzel title, Dark Souls style).
  No modals for screens or transitions (only card zoom and the menu); keep in-game text terse; square corners.
  CPU turns wait while an overlay (zoom, menu) is open or the banner is up.
  Die explanations come from `FoGame.die_breakdown` (same code path as `die_value`).
- `scripts/ui_kit.gd` (FoUI) — the look: colours, global Theme, card tiles, dice, chips. No game logic.
  Dice counts and AP are never shown as "2d6" / "+1 AP" text: `FoUI.StatMark` (gold die / silver diamond, a Texture2D)
  is the single drawing for both; `stat_chip` (Control), `stat_mark` (Button icon), `rich()` (text with "+2D6" / "-1 AP" swapped for tokens).
  Parchment palette from the prototype (`design/prototype/notes.md` + screenshots): `INK` text/outlines,
  `TAN`/`CREAM` surfaces, `UMBER` buttons, `OXBLOOD` (= `GOLD`, menu headings) Strength only,
  `INK` for "act here" (primaries `FoUI.primary`, the current turn's mat / chip; `FoUI.secondary` = cream, outlined),
  `NAVY` Sharpness, `GOOD` green gains. Cream (`INK_LIGHT`) text on coloured fills.
  Option sets (setup counts, settings, phone tabs, Reactions) use `FoUI.option`: off is quiet tan with a thin
  outline and muted text, on is cream with a heavy outline; never the filled ink CTA. One `primary` per screen;
  `UMBER` is kept lighter than `INK` so the primary stands out. Result lines: `GOOD` for Successes / no penalty, `RED` for a penalty.
  Card text follows the text size setting (`FoUI.card_text()`): the rules well grows, the art gives way.
  Dice clicks and step pops go through `_play_spaced` (`DIE_CLICK_GAP` / `DIE_STEP_GAP`) so bursts don't turn to noise.
  Playmat (`FoUI.background(frame_w)` → `FoUI.Playmat`): `assets/images/table/lattice.png` (barley-twist bars, ray-cast at 2x by
  `godot --headless --script res://tools/make_lattice.gd`) tiled, inside an egg-and-dart nine-slice `frame.svg`
  (regenerate with `python3 tools/make_playmat_frame.py`, imported at 2x). Both have mipmaps and are drawn at half scale. On desktop the lattice and 28 px frame cover only the
  centred table (`_frame_span`) with `INK` bars either side, like the title art; on phone a 14 px frame runs round the screen.
  Dice reveal (`_start_reveal`): the tray has a name bar in the Challenge colour ("Melaina rolls", `_tray_label`).
  A person's full roll waits in the hand: hold Roll (or Space / Enter) to shake, release to throw, harder
  the longer it was held (`_roll_down` / `_roll_up`); CPUs throw at once. The dice are thrown into a tall tray and bounce off its walls and
  each other (`_tumble`, cosmetic physics in `reveal.phys`), land, snap into a centred row, then
  breakdown steps with floating ±N → ✓ dice pop (pitch rising) then × dice crunch (pitch falling, tray shakes) → the result
  line counts up, or a Strength penalty slams down. A Reaction replays only the dice it changed.
  Quest scored (`_tally_quest`, from the "quest" history entry once the last reveal ends): mats tally lowest
  score first (+N rises off the total, a coin per Success), then the top scorer's mat gets sparks and the anvil;
  the church bell rings as each Quest starts.
  Victory (`_treasure_burst`): light beams on `back_layer` (under the board), a spark fountain, and the
  winner's Ingredients thrown out of the podium, then orbiting their card (`_trophies`, on `trophy_layer`,
  kept the last child of `fx_layer` so the treasure is always on top; the far side of the orbit shrinks and dims).
  Animations (dice reveal, card flights, overlay fades) live in main.gd, are skipped when
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
- `tools/make_art.gd` — regenerates `icon.png` (App Store icon, no alpha) and `assets/splash.png`
  (boot splash / iOS launch image): `godot --headless --script res://tools/make_art.gd`
- Desktop mats: the current player's mat is raised by `MAT_LIFT` (animated) with a drop shadow.
- Desktop board: capped at `DESK_BOARD_W` (1320) and centred; Challenge cards (name / portrait / rule)
  in a column left of the action area: both while drafting, the live one large while it's played,
  Strength hidden once Sharpness starts. New game = counts only (people, CPUs, difficulty); CPUs get
  random personas and seats are shuffled with the global RNG (tests call `seed()` first).
- Phone layout: a portrait window switches main.gd to `phone` mode: 640x1136 design size
  (`PHONE_SIZE`, set as the root's content scale size), one column, Table / Blacksmiths tabs.
  It switches live on rotate. Force it with `?layout=phone|desktop` on the web build or
  `--phone` / `--desktop` locally. Anything with a fixed width needs a phone branch
  (`test_phone_layout_fits` checks every screen fits in 608 px).
- Touch: interactive controls are at least `TOUCH` (72 px = 44 pt on iPad) in main.gd; iOS safe-area
  insets go on the board margin (`_apply_safe_area`, mobile only).
- `tests/` — tiny built-in runner (`run_tests.gd`), no addons

## Conventions
- Commit `*.import` and `*.uid` files; only `.godot/` and `build/` are ignored.
- Keep game rules (pure logic, no Nodes) separate from presentation so rules can be unit-tested headless.
- New card: add the row to the CSV *and* an entry in `CardData.DEFS` (Ingredient) or `Scoring` (Challenge).
- All randomness goes through `FoGame.rng` so a seed replays a whole game.
