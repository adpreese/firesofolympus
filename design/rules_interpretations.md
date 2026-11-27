# Rules interpretations (v0.4 pre-production)

The rules doc and card text left these points open. The engine (`scripts/rules/`) implements
the reading below. Every item was reviewed with the designer on 2026-11-22.

## Structure
- Ingredient deck is one copy of each of the 36 cards. With 4 players the deck runs out
  (4 players need 12 + 16 + 16 cards), so the discards are reshuffled into a new deck when it is empty.
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
  Sharpness pool as *extra* dice showing the same rolled faces (Modifiers apply again). A kept
  magic die stays magic (1-3 -> 5, 4-6 -> 6); +1 Reaction bonuses don't carry over. Dice-loss
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
- Phoenix Egg: "Keep 1 roll between Challenges" works like Jeweled Scabbard with 1 die instead of 2.
  With both, either card's button can un-keep a die and the use goes back to the card that kept it.
- Dwarven Whetstone: after the Sharpness roll, every freshly rolled 1 is rerolled once, automatically
  (before Cockatrice rerolls). A reroll that comes up 1 again stays. Magic dice, dice kept from
  Strength and the Salamander's free 6 aren't rerolled.
- Magic Mirror: a Sharpness Reaction, once. The copy is an extra die with the same rolled face
  (a magic die's copy is magic; Modifiers apply to it, +1 Reaction bonuses don't copy).
- Orichalcum: 1d6, or 2d6 in total once you've sharpened at least once this Quest (before or after drafting it).
- Blood Ruby: 1 reroll per Challenge for each AP you have left when crafting ends (0 if you're at 0 or below).
  Only passing early leaves AP unused.
- Branch of Yggdrasil: 1 Sharpness reroll per final Strength result of 6 or more. Skipping Strength
  (Golden Apple) gives none.
- Lightning Bolt: "Cannot be Retained" = can't be reserved.
- Kraken Blood: "one penalty" = one more die that triggers the Strength card (one more 1 for Golem,
  Phantasm, Cockatrice and Razorback Turtle; one more odd die for Mimic). Kraken and Giant Crab give
  their penalty even if you meet them, but not twice. Fiery Salamander has no penalty, so it does nothing
  there; skipping Strength (Golden Apple) avoids it too.
- Celestial Ore: 2 magic dice like Sphinx's Milk (1-3 count as 5, 4-6 count as 6). In the Sharpness
  Challenge, any of your final results of 3 or 4 count for nothing (removed before the card scores,
  so they don't add to Ice Dragon's total or form pairs). Strength is unaffected.
- Stygian Oil: 1d6, or 3d6 in total while Shadow Essence is in your weapon this Quest.
- Shadow Essence: its reroll (1 per Challenge) only works while Stygian Oil is in your weapon this Quest.

## Challenges
- Razor Mantis "each 6" counts results of 6 or higher (results can exceed 6).
- Vampire Bat counts pairs per value: four 3s = 2 Successes. Matches the rules example (2,2,6 → 1).
- Killer Bee counts disjoint pairs adding to 7.
- Ice Dragon: floor(total / 10), never below 0. The reveal ticks the die that takes the running total (left to right) past each multiple of 10.
- Kraken: the reveal ticks every die when the total beats 20 and crunches every die when it doesn't (or Kraken Blood forces the penalty).
- Fiery Salamander (a Strength card with a boon instead of a penalty): if your final results include
  three consecutive values (e.g. 3, 4, 5; duplicates don't matter), you get an extra Sharpness die
  showing 6 this Quest. Modifiers apply to it and Reactions can reroll it; dice-loss penalties can't remove it.
- Golem: −1 to every Sharpness die per 1 rolled.
- Cockatrice: the opponent's rerolls are automated. The engine rerolls whichever of your
  dice would hurt you most on average, and skips the reroll if none would hurt.

## Data notes
- Art names `30_Honeycomb` (Beeswax) and `29_phantasm` (Phantasm) are missing `.png`.

## Balance-testing variants
Optional rules in `FoGame.variants`, used only by `tools/simulate.gd --variant` (never in normal play or saves):
- `no_leader_reserve`: after Quest 2, the Blacksmith with the most total Successes doesn't reserve an
  Ingredient for Quest 3 (every tied leader skips). Ingredients reserved after Quest 1 stay available.
- `no_leader_reserve_always`: the leader in total Successes skips the reserve after Quest 1 *and*
  after Quest 2 (so a player who leads both times reserves nothing all game).
- `q3_extra_draw`: Quest 3 draws 5 Ingredients per Blacksmith into the market instead of 4 (AP unchanged).
  This was added when the deck had 25 cards (reserved ones never return to it); at 4 players a second Gold,
  Holy Water and Beeswax (average win rate in simulation) are shuffled in when Quest 3 starts:
  28 cards, 20 left after 8 reserves, enough for the full 5 per player.
- `q3_trailer_ap`: in Quest 3 everyone except the leader in total Successes starts with +1 AP
  (6 instead of 5); every tied leader goes without.
- `olive_bough`: adds a trial Ingredient, Olive Bough ("+1D6. If you're tied for the most Successes at
  the end of the game, you win"), as a 26th card. It only counts if it's in your Quest 3 weapon
  (drafted from the market or your reserve that Quest); it never breaks ties mid-game.
Variants can be combined (`--variant no_leader_reserve,q3_extra_draw`).
