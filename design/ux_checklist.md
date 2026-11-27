# UX checklist

What's left from the 10-Quest playtest review (2026-11-27). Tick an item when it's fixed, or delete it
if we decide against it. Some items came from an earlier build, so check they still happen before fixing.
Items marked *(phone)* are phone layout only.

## Top priorities
- [ ] Reserved Ingredient is hard to find in Quests 2–3: the Reserve row sits below the market fold, and tapping
      the card on your mat only zooms it (the zoom has no Draft button). Show it at the top of the market, or make the mat card draftable.
- [ ] Action buttons go off-screen: Rematch / New game on the desktop victory screen (y≈1064), Done under 3+ Reactions *(phone)*,
      and Sharpen / Pass under 12 market cards *(phone)*. Pin them so they're always visible.
- [ ] Pass-and-play has no handoff: Player 2's turn looks the same as Player 1's, and the scroll position carries over *(phone)*.
- [ ] No turn prompt while crafting: the "Quest 1 of 3" header bar is otherwise empty. Use it for "Your turn: draft, sharpen or pass".
- [ ] Mats change order every Quest (turn order), so you lose track of your own. Keep seats fixed and let the order strip show turn order.
- [ ] Mats overflow from Quest 2 on: 5+ Ingredients or 10+ result dice get scrollbars and are cut off by the frame, and "3 Successes" is clipped to "es".

## Is it clear what to do next?
- [ ] Done is needed after every roll, even with no Reactions. Continue automatically, or label it "Continue".
- [ ] Penalties don't name their source (e.g. Kraken Blood gives "-1 on Sharpness" with no 1s rolled).
- [ ] Wager screen ("Gambler's Charm": Wager / No wager) shows no stakes.
- [ ] The "Reserve" heading isn't explained, and a forced single choice still needs a click.
- [ ] Ingredient cards are the main crafting action but look passive next to the filled Sharpen button.
- [ ] AP meter always shows 5 boxes, even in Quest 1 when you have 3 AP.
- [ ] On Ice Dragon ("every 10 points"), the ✓ lands on whichever die crosses each 10, which looks random.
- [ ] Mat dice count can differ from the tray (Kallisto: 2 on the mat, rolled 3 for Sharpness).
- [ ] Setup row "Blacksmiths" means people, but CPUs are Blacksmiths too. Call it "People" or "Players".
- [ ] Grammar: "In You's reserve" (`_card_location`, main.gd).

## Flow
- [ ] Market reflows at once while a drafted card is still flying, so the card you aim at next moves.
- [ ] Strength results disappear from the mats once Sharpness starts.
- [ ] A stray "…" shows in the action area during the Quest tally.
- [ ] Victory: "Kallisto & Melaina WIN" wraps to two lines, and the header still says "Quest 3 of 3".
- [ ] Other players' drafts fly off-screen, and your own mat is on another tab *(phone)*.
- [ ] Fewer animations plus Fast CPU makes CPU turns flash by in about 0.45 s.
- [ ] Continue is shown but disabled after a game ends.
- [ ] The first click after closing Settings was ignored once (Rematch).

## Layout and spacing
- [ ] Larger text: 4-player mat names truncate ("K", "Me", "B"; "Kallist" next to "CPU 4 Successes").
- [ ] Empty gap between the market and the Sharpen / Pass row; empty mat trays in Quest 1.
- [ ] Mat widths change with their content.
- [ ] The Successes total is shown twice (mat header and result row).
- [ ] Challenge portraits are small inside large panels.
- [ ] Art scale varies between cards (Lotus Bloom fills its card, Soul is tiny).
- [ ] Settings panel is wider than its controls.
- [ ] The title screen puts the menu above the title.
- [ ] Zoom panel has empty space, and Close sits mid-panel.
- [ ] Market grid isn't centred (gap on the right) *(phone)*.
- [ ] Victory: trophies overlap the score numbers, and the per-Quest scores look like dice.
- [ ] Victory sparks and light beams spill past the frame onto the dark side bars.
- [ ] While tumbling, dice show readable faces that don't match where they land.

## Colour and icons
- [ ] Sphinx's Milk has no die badge in its card bar.
- [ ] The Strength count on the mats is `RED` while the card uses `OXBLOOD` (allowed by the palette; decide whether to unify).

## Sound
- [ ] The coin sound is used for both a wager and each Success.
- [ ] Only one music track, which loops about every 7 minutes.
- [ ] `click_in_to_place.wav` is still used for collisions, landings, the hand rattle and Keep. Consider a separate dice sample (`Roll_8d6_rattle.wav` is unused).
