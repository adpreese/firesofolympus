# Rules interpretations (v0.4 pre-production)

The rules doc and card text left these points open. The engine (`scripts/rules/`) implements
the reading below. Every item was reviewed with the designer on 2026-11-22.

## Structure
- Ingredient deck is one copy of each of the 25 cards. With 3+ players the deck runs out
  (3 players need 9 + 12 + 12 cards), so the discards are reshuffled into a new deck when it is empty.
- Quest 1 turn order: everyone rolls 2d6, highest first; ties are broken at random (stands in for re-rolls).
- Quest 2/3 order: fewest Successes *in the previous Quest* first, ties by 2d6.
- Pass ends your crafting for the rest of the Quest. A player with no legal action (empty
  table, empty reserve, can't sharpen) passes automatically.
- Challenges run as: every Blacksmith does the Strength Challenge in turn order, then every
  Blacksmith does the Sharpness Challenge.
- Reserving is required: one Ingredient per Quest, chosen from your Ingredients that aren't already
  reserved (skipped if you have none). Reserves accumulate. Drafting from your reserve costs 1 AP
  and the card stays in your reserve. There is no reserve step after Quest 3.
- A tie for most total Successes is a shared win.

## Dice
- "+XD6 against <type>" adds dice only to the Challenge whose monster has that type.
- Die result order: Effects (Sphinx's Milk magic conversion, Bronze) → Modifiers (Leather Grip
  checks the post-Effect value, Silver Wire, Manticore Poison, Golem penalty) → Reaction +1s →
  Razorback Turtle cap last.
- "Each rolled 1" on Strength Challenges uses **final** results, per "Final results are used to
  determine penalties".
- Dice-loss penalties remove normal dice first, then magic dice. Pools can't go below 0 dice.
- A rerolled die keeps any +1 Reaction bonus already put on it.

## Ingredients
- Manticore Poison: "+1 on Sharpness Test" = +1 to every die in the Sharpness Challenge.
- Gambler's Charm: "Wager a Success" = before rolling Sharpness you may wager. If you then
  have strictly the most Sharpness Successes this Quest you gain 1, otherwise you lose 1.
- Holy Water: up to 2 rerolls, all inside the Challenge where you first use it; leftovers are lost.
- Jeweled Scabbard: after rolling Strength you may mark up to 2 dice. They are added to your
  Sharpness pool as *extra* dice showing the same rolled faces (Modifiers apply again). Dice-loss
  penalties can't remove them.
- Rusty Bauble: the swap is mandatory if any opponent holds a non-reserved Ingredient
  (reserved ones can't be taken). A Bauble drafted from your own reserve doesn't swap.
  AP effects move with the card: you gain the taken card's AP change and the opponent loses it
  (e.g. taking their Beeswax: you +2 AP, they -2 AP; taking their Adamantium: you -3, they +3).
- Emerald's reroll only works in a Giant Challenge, once per Quest.
- Mithril's bonus Successes only count in the Sharpness Challenge.
- Aluminum stops *further* sharpening; sharpening done before drafting it still counts.
- Electrum gives +1d6 only for sharpenings done *after* drafting it. Those extra dice stay
  with the sharpening even if Electrum is later swapped away.
- Hyacinth counts your other Ingredients at the time you roll.

## Challenges
- Razor Mantis "each 6" counts results of 6 or higher (results can exceed 6).
- Vampire Bat counts pairs per value: four 3s = 2 Successes. Matches the rules example (2,2,6 → 1).
- Killer Bee counts disjoint pairs adding to 7.
- Ice Dragon: floor(total / 10), never below 0.
- Golem: −1 to every Sharpness die per 1 rolled.
- Cockatrice: the opponent's rerolls are automated. The engine rerolls whichever of your
  dice would hurt you most on average, and skips the reroll if none would hurt.

## Data notes
- Art names `30_Honeycomb` (Beeswax) and `29_phantasm` (Phantasm) are missing `.png`.
