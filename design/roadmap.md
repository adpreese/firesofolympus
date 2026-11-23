# Roadmap to release

Decided in a gap-analysis interview on 2026-11-22. Tick items off as they land.

**Target:** a polished release (web build on itch.io, plus the App Store).
**Play modes:** solo vs CPU, and hotseat on one device. Online play is out of scope.
**Out of scope for now:** telemetry and playtest tooling, stats and achievements, a scripted tutorial,
online multiplayer, and character portraits.

## Milestone 1: Clarity (first)
- [x] Card detail / zoom: tap any card (market, player Ingredients and reserve, Challenges) to see
      large art and full text. Replaces hover tooltips, which never show on touch.
- [x] Dice math breakdown: for each die show rolled value → Effects → Modifiers → Reactions → final,
      and what it contributes (Successes, penalty triggers). Uses the order in `rules_interpretations.md`.
- [x] Challenge results screen: after each Challenge, everyone's final dice, Successes or penalties.
- [x] Quest results screen: per-player Successes this Quest, running totals, and next Quest's turn order.
- [x] Rules engine exposes the breakdown as data (pure, unit-tested) and the UI only displays it.

## Milestone 2: Styled layout, light animation
- [x] Themed panels: player mats with card art, a market area, and Challenge cards as cards rather than text.
- [x] Tweens: cards move market → player, dice tumble before showing values, results fade in.
- [x] Respect a reduced-motion setting (now in Settings).

## Milestone 3: Game flow
- [x] Save / resume: autosave after every action, "Continue" on the title screen; survives a
      browser refresh and the iOS app being killed. Single save slot. Stored as seed + move list
      and replayed on load (`FoGame.replay`), so the bot must never draw from `game.rng`.
- [x] Pause menu: resume, restart, quit to title, rules reference, settings
      (SFX/music volume, CPU speed, text size, reduced motion).
- [x] Hotseat hand-off: a "Pass to <name>" screen only when control moves from one human to a
      *different* human. Never shown for CPU turns or in solo play. Also shown for the first
      human decision of a hotseat game, new or resumed.

## Milestone 4: CPU opponents
- [x] Difficulty levels: Easy (noisy heuristic), Normal (current bot), Hard (Monte Carlo lookahead
      using the deterministic engine on a cloned state). Must not consume the game's `rng`.
      Hard simulates the rest of the Quest 6 times per candidate move (top 4 drafts + sharpen + pass);
      about 80 ms per decision on desktop, spread over frames (`FoBot.Plan`) so the UI never stalls.
- [x] Personalities: named rival blacksmiths with a one-line description and a play-style bias
      (e.g. aggressive sharpener, gambler, hoarder). Names and text only, no portraits yet.
      Kallisto (steady), Brontes (sharpener), Tycho (gambler), Melaina (hoarder), Phaedra (monster hunter).
- [x] Bot-vs-bot test: Hard beats Normal beats Easy over N seeded games (`tests/test_bot.gd`).
      Measured over 2-player games: Normal beats Easy ~65%, Hard beats Normal ~95%.

## Milestone 5: Platform & accessibility
- [x] iOS: safe areas, touch-sized targets (≥ 44 pt), haptics on roll/draft, app icon and launch screen.
      Touch targets are 72 px in the 1920x1080 layout, which is 44 pt on an iPad. iPhone landscape
      shrinks the layout to about 0.36x, too small to play; it needs its own layout, or ship iPad-only
      (`application/targeted_device_family=1`; it is currently 2 = iPhone & iPad). Icon and splash come from `tools/make_art.gd`.
      Not yet tried on a device: safe-area insets and haptics.
- [x] Phone layout (web): portrait windows get a one-column layout at a 640 px design width with
      Table / Blacksmiths tabs (`?layout=phone|desktop` forces either). Landscape phones still get the
      shrunken desktop layout. The iOS app is locked to landscape, so on an iPhone it doesn't use this yet.
      Not yet tried on a real phone browser.
- [x] Colourblind-safe die markers: magic and kept dice get a shape or icon, not just colour.
      Corner symbols: ✓ scores / protects, × triggers the penalty, ◆ magic, ▲ kept (`FoUI.MARK_*`).
- [x] Text size option and reduced-motion option (landed with the Milestone 3 settings).
