class_name FoGame
extends RefCounted
## Rules engine for Fires of Olympus. Pure logic, no Nodes; deterministic for a given seed.
##
## Whoever drives the game (UI or bot) reads `phase` and `current` to see whose decision
## it is, then calls one act_* / apply_reaction / finish_reactions method. Every method
## returns false (and changes nothing) if the move isn't legal right now.
## Rule interpretations are documented in design/rules_interpretations.md.

enum Phase { CRAFT, SWAP, WAGER, REACT, RESERVE, GAME_OVER }

const QUESTS := [{"draw": 3, "ap": 3}, {"draw": 4, "ap": 4}, {"draw": 4, "ap": 5}]
const SHARPEN_DICE := [1, 2, 2]
const STRENGTH := "Strength"
const SHARPNESS := "Sharpness"


class Die:
	var raw: int
	var magic: bool
	var bonus := 0         # from +1 Reactions
	var carried := false   # Strength: marked to keep (Jeweled Scabbard, Phoenix Egg); Sharpness: was kept
	var kept_by := ""      # Strength: the reaction key that marked it, refunded if un-kept
	var origin := ""       # breakdown label when not a plain roll, e.g. "Copied (Magic Mirror)"

	func _init(r: int, m := false) -> void:
		raw = r
		magic = m


class Player:
	var name: String
	var is_bot: bool
	var total := 0
	var quest_scores: Array[int] = []
	var reserve: Array = []        # card dicts kept for future Quests
	# --- reset every Quest ---
	var ap := 0
	var passed := false
	var ingredients: Array = []    # card dicts {id, name}
	var sharpen := 0
	var electrum_dice := 0         # extra dice from sharpening while holding Electrum
	var reaction_uses := {}        # "card_id:index" -> uses left
	var penalty := {}              # from the Strength Challenge, applied to Sharpness
	var kept_dice: Array = []      # Jeweled Scabbard dice kept for Sharpness: [raw, magic]
	var strength_sixes := 0        # final results >= 6 in this Quest's Strength (Branch of Yggdrasil)
	var wager := false
	var wager_decided := false
	var dice: Array = []           # Array of Die for the Challenge being rolled
	var quest_score := 0

	func _init(n: String, bot: bool) -> void:
		name = n
		is_bot = bot

	func copy() -> Player:
		var p := Player.new(name, is_bot)
		p.total = total
		p.quest_scores = quest_scores.duplicate()
		p.reserve = reserve.duplicate()
		p.ap = ap
		p.passed = passed
		p.ingredients = ingredients.duplicate()
		p.sharpen = sharpen
		p.electrum_dice = electrum_dice
		p.reaction_uses = reaction_uses.duplicate()
		p.penalty = penalty.duplicate()
		p.kept_dice = kept_dice.duplicate()
		p.strength_sixes = strength_sixes
		p.wager = wager
		p.wager_decided = wager_decided
		for d in dice:
			var c := Die.new(d.raw, d.magic)
			c.bonus = d.bonus
			c.carried = d.carried
			c.kept_by = d.kept_by
			c.origin = d.origin
			p.dice.append(c)
		p.quest_score = quest_score
		return p


var data: CardData
var rng := RandomNumberGenerator.new()
var players: Array = []
var quest := 0
var phase: Phase = Phase.CRAFT
var current := 0
var order: Array[int] = []
var market: Array = []
var deck: Array = []
var discard: Array = []
var strength_deck: Array = []
var sharpness_deck: Array = []
var strength_card: Dictionary = {}
var sharpness_card: Dictionary = {}
var challenge_kind := STRENGTH
var log_lines: PackedStringArray = []
## Finished Challenges and Quests, oldest first (the UI shows them on the mats). Each entry:
##   {type: "challenge", quest, kind, card, rows: [{player, skipped, dice: [{value, mark, magic,
##     carried, steps}], result, successes | penalty, parts, note}]}
##   {type: "quest", quest, final, rows: [{player, challenge, wager, score, total}]}
##   {type: "order", quest, rows: [{player, dice: [a, b], successes, tiebreak}]} in draft order;
##     successes is last Quest's (-1 in Quest 1), tiebreak: they shared a total with a neighbour
##     and the re-roll decided it. Added when each Quest's order is set, before its draft.
var history: Array = []
## Every successful move, in order, as [method, args...]. With the seed this replays the
## whole game (see `replay`), which is how saves work.
var moves: Array = []
var seed_value := 0
## Simulation copies (see `clone`) skip the log and results-screen bookkeeping.
var quiet := false
## Optional rule variants for balance testing (tools/simulate.gd --variant), off in normal play
## and not saved. Set before `setup`. Keys:
##   no_leader_reserve: whoever leads in total Successes after Quest 2 (every tied leader)
##     doesn't reserve an Ingredient for Quest 3.
##   no_leader_reserve_always: the same after Quest 1 too, so the leader at each reserve skips it.
##   q3_extra_draw: Quest 3 draws 5 Ingredients per Blacksmith instead of 4. At 4 players the
##     original 25-card deck couldn't cover that once 8 cards were reserved, so Q3_DUPES (average cards by
##     simulated win rate) get a second copy shuffled into the deck when Quest 3 starts.
##   q3_trailer_ap: in Quest 3, everyone except the leader in total Successes (every tied
##     leader) starts with +1 AP.
##   olive_bough: adds Olive Bough (VARIANT_CARDS) to the deck.
## Variants combine: --variant no_leader_reserve,q3_extra_draw.
const VARIANTS := ["no_leader_reserve", "no_leader_reserve_always", "q3_extra_draw", "q3_trailer_ap", "olive_bough"]
var variants := {}
const Q3_DUPES := ["Gold", "Holy Water", "Beeswax"]
## Trial Ingredients that aren't in the CSV yet. `tiebreak`: if tied for the most Successes when
## the game ends while it's in your Quest 3 weapon, you win.
const VARIANT_CARDS := {
	"Olive Bough": {"text": "+1D6\nIf you're tied for the most Successes at the end of the game, you win.",
		"def": {"dice": 1, "tiebreak": true}},
}

var _turn_step := -1
var _challenge_pos := -1
var _reserve_pos := -1
var _pending_bauble_id := -1
var _result := {}  # the Challenge being played, moved to history when everyone is done


func _init(card_data: CardData) -> void:
	data = card_data


func setup(names: Array, bots: Array, seed_in: int) -> void:
	seed_value = seed_in
	rng.seed = seed_in
	moves.clear()
	players.clear()
	for i in names.size():
		players.append(Player.new(names[i], bots[i]))
	deck.clear()
	discard.clear()
	for i in data.ingredients.size():
		deck.append({"id": i, "name": data.ingredients[i].name})
	if variants.has("olive_bough"):
		var id := data.ingredients.size() + Q3_DUPES.size() + VARIANT_CARDS.keys().find("Olive Bough")
		deck.append({"id": id, "name": "Olive Bough"})
	_shuffle(deck)
	strength_deck = data.challenges.filter(func(c): return c.kind == STRENGTH)
	sharpness_deck = data.challenges.filter(func(c): return c.kind == SHARPNESS)
	_shuffle(strength_deck)
	_shuffle(sharpness_deck)
	quest = 0
	_start_quest()


# ------------------------------------------------------------------ queries

func player() -> Player:
	return players[current]


func def_of(card: Dictionary) -> Dictionary:
	if VARIANT_CARDS.has(card.name):
		return VARIANT_CARDS[card.name].def
	return data.def(card.name)


func text_of(card: Dictionary) -> String:
	if VARIANT_CARDS.has(card.name):
		return VARIANT_CARDS[card.name].text
	return data.ingredient(card.name).get("text", "")


## Name for a card id. Ids past the CSV rows are variant cards: Q3_DUPES, then VARIANT_CARDS.
func card_name(id: int) -> String:
	var n := data.ingredients.size()
	if id < n:
		return data.ingredients[id].name
	if id < n + Q3_DUPES.size():
		return Q3_DUPES[id - n]
	return VARIANT_CARDS.keys()[id - n - Q3_DUPES.size()]


## Sum of a definition key over a player's current Ingredients (bools count as 1).
func flag_sum(pi: int, key: String) -> int:
	var n := 0
	for c in players[pi].ingredients:
		n += int(def_of(c).get(key, 0))
	return n


func challenge_card(kind: String) -> Dictionary:
	return strength_card if kind == STRENGTH else sharpness_card


func in_reserve(pi: int, card_id: int) -> bool:
	for c in players[pi].reserve:
		if c.id == card_id:
			return true
	return false


## Whether the player has an Ingredient with this name in this Quest's weapon.
func holds_name(pi: int, card_name: String) -> bool:
	for c in players[pi].ingredients:
		if c.name == card_name:
			return true
	return false


## Uses a Reaction starts each Challenge (or Quest) with. Most are printed on the card;
## Blood Ruby counts unused AP and Branch of Yggdrasil counts Strength results of 6+.
func reaction_max(pi: int, r: Dictionary) -> int:
	match r.get("uses_from", ""):
		"unused_ap":
			return maxi(0, players[pi].ap)
		"strength_sixes":
			return players[pi].strength_sixes
	return int(r.get("uses", 0))


func _holds(pi: int, card_id: int) -> bool:
	for c in players[pi].ingredients:
		if c.id == card_id:
			return true
	return false


func is_done(pi: int) -> bool:
	return players[pi].passed or players[pi].ap <= 0


func can_sharpen(pi: int) -> bool:
	return players[pi].sharpen < SHARPEN_DICE.size() and flag_sum(pi, "no_sharpen") == 0


## Reserved Ingredients this player can still draft this Quest.
func reserve_options(pi: int) -> Array:
	return players[pi].reserve.filter(func(c): return not _holds(pi, c.id))


## The crafting turns coming up, current player first: [{player, round}] for at most `count`
## turns. Follows the snake draft and each player's remaining AP (every action costs 1), so
## it's the longest the queue can be: passing early shortens it. Empty outside crafting.
func craft_queue(count: int) -> Array:
	var out := []
	if not phase in [Phase.CRAFT, Phase.SWAP] or order.is_empty():
		return out
	var n := players.size()
	var ap := {}
	for pi in n:
		ap[pi] = 0 if players[pi].passed else players[pi].ap
	@warning_ignore("integer_division")
	out.append({"player": current, "round": _turn_step / n})
	if phase == Phase.CRAFT:
		ap[current] -= 1  # the turn being taken (a SWAP's AP is already spent)
	var step := _turn_step
	while out.size() < count:
		if ap.values().all(func(a): return a <= 0):
			break
		step += 1
		@warning_ignore("integer_division")
		var rnd := step / n
		var pos := step % n
		var pi: int = order[pos] if rnd % 2 == 0 else order[n - 1 - pos]
		if ap[pi] <= 0:
			continue
		ap[pi] -= 1
		out.append({"player": pi, "round": rnd})
	return out


## "reroll", "plus_one", "keep" or "copy" for a Reaction key from `available_reactions`.
func reaction_kind(key: String) -> String:
	var parts := key.split(":")
	if parts.size() != 2:
		return ""
	for p in players:
		for c in p.ingredients:
			if str(c.id) == parts[0]:
				var rs: Array = def_of(c).get("reactions", [])
				var j := int(parts[1])
				return rs[j].kind if j < rs.size() else ""
	return ""


func has_craft_options(pi: int) -> bool:
	return not market.is_empty() or not reserve_options(pi).is_empty() or can_sharpen(pi)


## Dice a player would roll for a Challenge: {normal, magic}.
func pool_size(pi: int, kind: String) -> Dictionary:
	var p: Player = players[pi]
	var ctype: String = challenge_card(kind).get("type", "")
	var normal := 0
	var magic := 0
	for c in p.ingredients:
		var d := def_of(c)
		normal += int(d.get("dice", 0))
		normal += int(d.get("vs", {}).get(ctype, 0))
		magic += int(d.get("magic", 0))
		if d.get("hyacinth", false):
			normal += p.ingredients.size() - 1
		if p.sharpen > 0:
			normal += int(d.get("sharpened_dice", 0))
		if d.has("combo") and holds_name(pi, d.combo):
			normal += int(d.combo_dice)
	for i in p.sharpen:
		normal += SHARPEN_DICE[i]
	normal += p.electrum_dice
	if kind == SHARPNESS:
		normal -= int(p.penalty.get("dice_loss", 0))
	if normal < 0:  # penalties eat normal dice first, then magic ones
		magic = maxi(0, magic + normal)
		normal = 0
	if kind == SHARPNESS:  # kept dice and the Salamander's 6 are extra, after penalties
		normal += p.kept_dice.size() + int(p.penalty.get("free_six", 0))
	return {"normal": normal, "magic": magic}


## Final result of one die: Effects, then Modifiers, then Reaction bonuses, then caps.
func die_value(pi: int, die: Die, kind: String) -> int:
	return _die_calc(pi, die, kind, null)


## How a die reached its final value: [{text, value}], starting with the roll.
## Each later entry is one change; the last entry's value equals die_value().
func die_breakdown(pi: int, die: Die, kind: String) -> Array:
	var steps := []
	_die_calc(pi, die, kind, steps)
	return steps


## Shared by die_value and die_breakdown so the explanation can't drift from the rules.
## `steps` is null on the hot path (bot lookahead) so no strings are built.
func _die_calc(pi: int, die: Die, kind: String, steps) -> int:
	var p: Player = players[pi]
	var v := die.raw
	if steps != null:
		var src := "Rolled"
		if die.origin != "":
			src = die.origin
		elif die.carried and kind == SHARPNESS:
			src = "Kept from Strength, rolled"
		steps.append({"text": "%s %d" % [src, v], "value": v})
	if die.magic:
		v = 5 if v <= 3 else 6
		if steps != null:
			steps.append({"text": "Magic die (Sphinx's Milk): 1-3 -> 5, 4-6 -> 6", "value": v})
	var bronze := false
	var leather := false
	var mods := []  # [label, delta], applied together after Effects
	for c in p.ingredients:
		var d := def_of(c)
		if d.get("bronze", false):
			bronze = true
		if d.get("leather", false):
			leather = true
		if d.has("mod"):
			mods.append([c.name, int(d.mod)])
		if kind == SHARPNESS and d.has("sharp_mod"):
			mods.append([c.name, int(d.sharp_mod)])
	if bronze and (v == 1 or v == 6):
		v = 2 if v == 1 else 5
		if steps != null:
			steps.append({"text": "Bronze: 1 -> 2, 6 -> 5", "value": v})
	if leather and (v == 2 or v == 3):  # checks the post-Effect value
		mods.append(["Leather Grip (on a 2 or 3)", 2])
	var penalty: Dictionary = p.penalty
	if kind == SHARPNESS and int(penalty.get("die_mod", 0)) != 0:
		mods.append(["%s penalty" % strength_card.get("name", "Strength"), int(penalty.die_mod)])
	for m in mods:
		v += m[1]
		if steps != null and m[1] != 0:
			steps.append({"text": "%s %+d" % m, "value": v})
	if die.bonus != 0:
		v += die.bonus
		if steps != null:
			steps.append({"text": "Reactions %+d" % die.bonus, "value": v})
	if kind == SHARPNESS and penalty.has("cap") and v > penalty.cap:
		v = penalty.cap
		if steps != null:
			steps.append({"text": "Capped at %d (%s penalty)" % [penalty.cap, strength_card.get("name", "Strength")], "value": v})
	if steps != null and kind == SHARPNESS and (v == 3 or v == 4) and flag_sum(pi, "ignore_34") > 0:
		steps.append({"text": "Doesn't count for Successes (Celestial Ore ignores 3s and 4s)", "value": v})
	return v


func values(pi: int, kind: String) -> Array[int]:
	var out: Array[int] = []
	for d in players[pi].dice:
		out.append(die_value(pi, d, kind))
	return out


## Strength: the penalty dict. Sharpness: {"successes": n}.
func evaluate(pi: int, kind: String) -> Dictionary:
	return evaluate_values(pi, kind, values(pi, kind))


## `evaluate` for final die values already worked out (lets callers try one die at a time).
func evaluate_values(pi: int, kind: String, vals: Array) -> Dictionary:
	var card := challenge_card(kind)
	if kind == STRENGTH:
		return Scoring.strength_penalty(card.name, vals, flag_sum(pi, "auto_penalty"))
	var s := 0
	for part in success_parts(pi, vals):
		s += part[1]
	return {"successes": s}


## Where Sharpness Successes come from: [[source, n]] (before any Gambler's Charm wager).
## The Challenge card is always listed first, even at 0.
func success_parts(pi: int, vals: Array) -> Array:
	vals = counted(pi, vals)
	var card := challenge_card(SHARPNESS)
	var out := [[card.name, Scoring.sharpness_successes(card.name, vals)]]
	var sixes := 0
	for v in vals:
		if v >= 6:
			sixes += 1
	for c in players[pi].ingredients:
		var d := def_of(c)
		if d.get("mithril", false) and sixes > 0:
			out.append([c.name, sixes])
		if d.has("bonus_success"):
			out.append([c.name, int(d.bonus_success)])
	return out


## Sharpness results that count for Successes: all of them, unless Celestial Ore drops 3s and 4s.
func counted(pi: int, vals: Array) -> Array:
	if flag_sum(pi, "ignore_34") == 0:
		return vals
	return vals.filter(func(v): return v != 3 and v != 4)


## Per die, for the UI: 1 = scores (or saves you from a penalty), -1 = triggers a penalty, 0 = neither.
func die_marks(pi: int, kind: String) -> Array[int]:
	var vals := values(pi, kind)
	var marks: Array[int]
	if kind == SHARPNESS and flag_sum(pi, "ignore_34") > 0:  # mark only the dice that count
		var idx := []
		var kept := []
		for i in vals.size():
			if vals[i] != 3 and vals[i] != 4:
				idx.append(i)
				kept.append(vals[i])
		var sub := Scoring.die_marks(challenge_card(kind).name, kept)
		marks.resize(vals.size())
		for j in idx.size():
			marks[idx[j]] = sub[j]
	else:
		marks = Scoring.die_marks(challenge_card(kind).name, vals)
	if kind == STRENGTH and challenge_card(kind).name == "Kraken" and flag_sum(pi, "auto_penalty") > 0:
		marks.fill(-1)  # Kraken Blood: the penalty comes whatever the total
	if kind == SHARPNESS and flag_sum(pi, "mithril") > 0:
		for i in vals.size():
			if vals[i] >= 6:
				marks[i] = 1
	return marks


## Higher is better: Successes for Sharpness, minus penalty cost for Strength.
func outcome_score(pi: int, kind: String) -> float:
	return outcome_of(pi, kind, values(pi, kind))


func outcome_of(pi: int, kind: String, vals: Array) -> float:
	var e := evaluate_values(pi, kind, vals)
	return float(e.successes) if kind == SHARPNESS else -Scoring.penalty_cost(e)


## Average outcome_score if this die were rerolled. `vals`: current values(pi, kind), if known.
func expected_after_reroll(pi: int, die_idx: int, kind: String, vals: Array = []) -> float:
	if vals.is_empty():
		vals = values(pi, kind)
	var d: Die = players[pi].dice[die_idx]
	var old := d.raw
	var old_val: int = vals[die_idx]
	var total := 0.0
	for r in range(1, 7):
		d.raw = r
		vals[die_idx] = die_value(pi, d, kind)
		total += outcome_of(pi, kind, vals)
	d.raw = old
	vals[die_idx] = old_val
	return total / 6.0


func describe_outcome(pi: int) -> String:
	var e := evaluate(pi, challenge_kind)
	if challenge_kind == STRENGTH:
		return Scoring.describe_penalty(e)
	return successes_text(e.successes)


static func successes_text(n: int) -> String:
	return "%d Success%s" % [n, "" if n == 1 else "es"]


## Reactions usable right now: [{key, card, kind, left}].
func available_reactions(pi: int) -> Array:
	var out := []
	var p: Player = players[pi]
	var ctype: String = challenge_card(challenge_kind).type
	for c in p.ingredients:
		var rs: Array = def_of(c).get("reactions", [])
		for j in rs.size():
			var r: Dictionary = rs[j]
			if r.has("challenge") and r.challenge != challenge_kind:
				continue
			if r.has("vs") and r.vs != ctype:
				continue
			if r.has("needs") and not holds_name(pi, r.needs):
				continue
			var key := "%d:%d" % [c.id, j]
			var left: int = p.reaction_uses.get(key, reaction_max(pi, r))
			if left <= 0 and r.kind != "keep":  # keep stays listed so dice can be un-kept
				continue
			out.append({"key": key, "card": c.name, "kind": r.kind, "left": left})
	return out


func swap_targets(pi: int) -> Array:
	var out := []
	for qi in players.size():
		if qi == pi:
			continue
		for c in players[qi].ingredients:
			if not in_reserve(qi, c.id):
				out.append({"player": qi, "card": c})
	return out


func reservable(pi: int) -> Array:
	if _leader_skips_reserve(pi):
		return []
	return players[pi].ingredients.filter(func(c):
		return not in_reserve(pi, c.id) and not def_of(c).get("no_reserve", false))


func winners() -> Array[int]:
	var best := -1000000
	for p in players:
		best = maxi(best, p.total)
	var out: Array[int] = []
	for i in players.size():
		if players[i].total == best:
			out.append(i)
	if phase == Phase.GAME_OVER and out.size() > 1:  # Olive Bough breaks a final tie
		var holders: Array[int] = []
		for i in out:
			if flag_sum(i, "tiebreak") > 0:
				holders.append(i)
		if holders.size() == 1:
			return holders
	return out


# ------------------------------------------------------------------ copies

## An independent copy for look-ahead (FoBot's Hard level). Shares the read-only card data;
## the copy is `quiet` and starts with an empty log. Its rng starts in the same state, so
## reseed it unless you want the real future dice.
func clone() -> FoGame:
	var g := FoGame.new(data)
	g.quiet = true
	g.variants = variants
	g.rng.seed = rng.seed
	g.rng.state = rng.state
	for p in players:
		g.players.append(p.copy())
	g.quest = quest
	g.phase = phase
	g.current = current
	g.order = order.duplicate()
	g.market = market.duplicate()
	g.deck = deck.duplicate()
	g.discard = discard.duplicate()
	g.strength_deck = strength_deck.duplicate()
	g.sharpness_deck = sharpness_deck.duplicate()
	g.strength_card = strength_card
	g.sharpness_card = sharpness_card
	g.challenge_kind = challenge_kind
	g.history = history.duplicate()
	g.moves = moves.duplicate()
	g.seed_value = seed_value
	g._turn_step = _turn_step
	g._challenge_pos = _challenge_pos
	g._reserve_pos = _reserve_pos
	g._pending_bauble_id = _pending_bauble_id
	g._result = _result.duplicate(true)
	return g


# ------------------------------------------------------------------ moves & replay

## Apply one entry of `moves` (also accepts JSON-decoded ones, where numbers are floats).
func play_move(m: Array) -> bool:
	if m.is_empty():
		return false
	match str(m[0]):
		"draft":
			return m.size() == 2 and act_draft(int(m[1]))
		"sharpen":
			return act_sharpen()
		"pass":
			return act_pass()
		"swap":
			return m.size() == 3 and act_swap(int(m[1]), int(m[2]))
		"wager":
			return m.size() == 2 and act_wager(bool(m[1]))
		"react":
			return m.size() == 3 and apply_reaction(str(m[1]), int(m[2]))
		"finish":
			return finish_reactions()
		"reserve":
			return m.size() == 2 and act_reserve(int(m[1]))
	return false


## A new game rebuilt from its setup and move list, or null if any move no longer applies
## (e.g. a save from an older version of the rules).
static func replay(card_data: CardData, names: Array, bots: Array, seed_in: int, move_list: Array) -> FoGame:
	var g := FoGame.new(card_data)
	g.setup(names, bots, seed_in)
	for m in move_list:
		if not (m is Array and g.play_move(m)):
			return null
	return g


# ------------------------------------------------------------------ craft phase

func act_draft(card_id: int) -> bool:
	if phase != Phase.CRAFT:
		return false
	var p := player()
	var card := {}
	for i in market.size():
		if market[i].id == card_id:
			card = market[i]
			market.remove_at(i)
			break
	if card.is_empty():
		for c in reserve_options(current):
			if c.id == card_id:
				card = c
	if card.is_empty():
		return false
	var d := def_of(card)
	p.ap += -1 + int(d.get("ap", 0))
	p.ingredients.append(card)
	_log("%s takes %s (%d AP left)" % [p.name, card.name, p.ap])
	moves.append(["draft", card_id])
	if d.get("swap_on_draft", false) and not in_reserve(current, card.id) and not swap_targets(current).is_empty():
		_pending_bauble_id = card.id
		phase = Phase.SWAP
		return true
	_advance_craft()
	return true


func act_sharpen() -> bool:
	if phase != Phase.CRAFT or not can_sharpen(current):
		return false
	var p := player()
	var electrum := flag_sum(current, "electrum")
	p.sharpen += 1
	p.electrum_dice += electrum
	p.ap -= 1
	moves.append(["sharpen"])
	_log("%s sharpens (+%dd6, %d AP left)" % [p.name, SHARPEN_DICE[p.sharpen - 1] + electrum, p.ap])
	_advance_craft()
	return true


func act_pass() -> bool:
	if phase != Phase.CRAFT:
		return false
	player().passed = true
	moves.append(["pass"])
	_log("%s passes" % player().name)
	_advance_craft()
	return true


func act_swap(target_player: int, card_id: int) -> bool:
	if phase != Phase.SWAP or target_player == current or target_player < 0 or target_player >= players.size():
		return false
	var p := player()
	var q: Player = players[target_player]
	var ti := -1
	for i in q.ingredients.size():
		if q.ingredients[i].id == card_id and not in_reserve(target_player, card_id):
			ti = i
	var bi := -1
	for i in p.ingredients.size():
		if p.ingredients[i].id == _pending_bauble_id:
			bi = i
	if ti < 0 or bi < 0:
		return false
	moves.append(["swap", target_player, card_id])
	var taken: Dictionary = q.ingredients[ti]
	q.ingredients[ti] = p.ingredients[bi]
	p.ingredients[bi] = taken
	# AP effects move with the card: the taker gains it, the previous owner loses it.
	var ap_shift := int(def_of(taken).get("ap", 0))
	p.ap += ap_shift
	q.ap -= ap_shift
	var ap_note := "" if ap_shift == 0 else " (AP %+d for %s, %+d for %s)" % [ap_shift, p.name, -ap_shift, q.name]
	_log("  Rusty Bauble: %s swaps it for %s's %s%s" % [p.name, q.name, taken.name, ap_note])
	_pending_bauble_id = -1
	_advance_craft()
	return true


func _advance_craft() -> void:
	var n := players.size()
	while true:
		var all_done := true
		for pi in n:
			if not is_done(pi):
				all_done = false
		if all_done:
			_start_challenges()
			return
		_turn_step += 1
		@warning_ignore("integer_division")
		var rnd := _turn_step / n
		var pos := _turn_step % n
		var pi: int = order[pos] if rnd % 2 == 0 else order[n - 1 - pos]  # snake draft
		if is_done(pi):
			continue
		if not has_craft_options(pi):
			players[pi].passed = true
			_log("%s has no actions left and passes" % players[pi].name)
			continue
		current = pi
		phase = Phase.CRAFT
		return


# ------------------------------------------------------------------ challenges

func act_wager(yes: bool) -> bool:
	if phase != Phase.WAGER:
		return false
	var p := player()
	p.wager = yes
	moves.append(["wager", yes])
	p.wager_decided = true
	if yes:
		_log("  %s wagers a Success (Gambler's Charm)" % p.name)
	_roll(current)
	phase = Phase.REACT
	return true


func apply_reaction(key: String, die_idx: int) -> bool:
	if phase != Phase.REACT:
		return false
	var p := player()
	if die_idx < 0 or die_idx >= p.dice.size():
		return false
	var r := {}
	for a in available_reactions(current):
		if a.key == key:
			r = a
	if r.is_empty():
		return false
	var die: Die = p.dice[die_idx]
	if r.kind == "keep" and not die.carried and r.left <= 0:
		return false
	moves.append(["react", key, die_idx])
	var before := die_value(current, die, challenge_kind)
	match r.kind:
		"reroll":
			die.raw = _d6()
			if not die.origin.begins_with("Copied"):
				die.origin = ""  # it's an ordinary roll now
			_log("  %s rerolls a %d -> %d (%s)" % [p.name, before, die_value(current, die, challenge_kind), r.card])
		"plus_one":
			die.bonus += 1
			_log("  %s adds +1 to a %d (%s)" % [p.name, before, r.card])
		"copy":
			var twin := Die.new(die.raw, die.magic)  # same face; +1 bonuses don't copy
			twin.origin = "Copied (%s), showing" % r.card
			p.dice.append(twin)
			_log("  %s copies a %d (%s)" % [p.name, before, r.card])
		"keep":
			if die.carried:  # un-keep: refund whichever card kept it
				var by := die.kept_by if die.kept_by != "" else key
				p.reaction_uses[by] = int(p.reaction_uses.get(by, 0)) + 1
				die.carried = false
				die.kept_by = ""
				return true
			die.carried = true
			die.kept_by = key
	p.reaction_uses[key] = r.left - 1
	return true


func finish_reactions() -> bool:
	if phase != Phase.REACT:
		return false
	var p := player()
	moves.append(["finish"])
	var e := evaluate(current, challenge_kind)
	var vals := values(current, challenge_kind)
	if challenge_kind == STRENGTH:
		p.penalty = e
		p.strength_sixes = vals.filter(func(v): return v >= 6).size()
		p.kept_dice.clear()
		var kept_vals := []
		for d in p.dice:
			if d.carried:
				p.kept_dice.append([d.raw, d.magic])  # a magic die stays magic
				kept_vals.append(d.raw)
		var keep := "" if kept_vals.is_empty() else " (keeps %s for Sharpness)" % str(kept_vals)
		_log("  %s: %s -> %s%s" % [p.name, str(vals), Scoring.describe_penalty(e), keep])
	else:
		p.quest_score = e.successes
		_log("  %s: %s -> %s" % [p.name, str(vals), successes_text(e.successes)])
	_record_row(current, e)
	# "once per Quest" reactions are spent after the Challenge they were first used in.
	for c in p.ingredients:
		var rs: Array = def_of(c).get("reactions", [])
		for j in rs.size():
			var key := "%d:%d" % [c.id, j]
			var full := reaction_max(current, rs[j])
			if rs[j].scope == "quest_once" and p.reaction_uses.get(key, full) < full:
				p.reaction_uses[key] = 0
	_next_challenge_player()
	return true


func _start_challenges() -> void:
	challenge_kind = STRENGTH
	_challenge_pos = -1
	_open_result(STRENGTH)
	_log("-- Strength Challenge: %s --" % strength_card.name)
	_next_challenge_player()


func _next_challenge_player() -> void:
	while true:
		_challenge_pos += 1
		if _challenge_pos >= players.size():
			history.append(_result)
			if challenge_kind == SHARPNESS:
				_end_challenges()
				return
			challenge_kind = SHARPNESS
			_challenge_pos = 0
			_open_result(SHARPNESS)
			_log("-- Sharpness Challenge: %s --" % sharpness_card.name)
		var pi := order[_challenge_pos]
		var p: Player = players[pi]
		current = pi
		_reset_challenge_reactions(pi)
		if challenge_kind == STRENGTH and flag_sum(pi, "skip_strength") > 0:
			_log("  %s skips the Strength Challenge (Golden Apple)" % p.name)
			p.penalty = {}
			p.strength_sixes = 0
			_result.rows.append({"player": pi, "skipped": true, "dice": [], "result": "Skipped (Golden Apple)",
				"penalty": {}, "parts": [], "note": ""})
			continue
		if challenge_kind == SHARPNESS and flag_sum(pi, "gamble") > 0 and not p.wager_decided:
			phase = Phase.WAGER
			return
		_roll(pi)
		phase = Phase.REACT
		return


## This Quest's Challenge results so far for seat `pi`, Strength first: history rows
## (see `history`), including the Challenge being played. Empty in simulation copies.
func quest_rows(pi: int) -> Array:
	var entries := history.filter(func(e): return e.type == "challenge" and e.quest == quest)
	if _result.get("quest", -1) == quest and not entries.any(func(e): return is_same(e, _result)):
		entries.append(_result)
	var out := []
	for e in entries:
		for r in e.rows:
			if r.player == pi:
				out.append(r.merged({"kind": e.kind}))
	return out


func _open_result(kind: String) -> void:
	_result = {"type": "challenge", "quest": quest, "kind": kind, "card": challenge_card(kind), "rows": []}


func _record_row(pi: int, e: Dictionary) -> void:
	if quiet:
		return
	var p: Player = players[pi]
	var vals := values(pi, challenge_kind)
	var marks := die_marks(pi, challenge_kind)
	var dice := []
	for i in p.dice.size():
		var d: Die = p.dice[i]
		dice.append({"value": vals[i], "mark": marks[i], "magic": d.magic,
			"carried": d.carried, "steps": die_breakdown(pi, d, challenge_kind)})
	var row := {"player": pi, "skipped": false, "dice": dice, "result": describe_outcome(pi),
		"note": Scoring.total_note(challenge_card(challenge_kind).name, vals), "parts": []}
	if challenge_kind == STRENGTH:
		row.penalty = e.duplicate()
		var auto := flag_sum(pi, "auto_penalty")
		if auto > 0 and challenge_card(STRENGTH).name != "Fiery Salamander":
			var line := "Kraken Blood: takes %d penalty automatically" % auto
			row.note = line if row.note == "" else row.note + "\n" + line
	else:
		row.successes = e.successes
		row.parts = success_parts(pi, vals)
	_result.rows.append(row)


func _reset_challenge_reactions(pi: int) -> void:
	var p: Player = players[pi]
	for c in p.ingredients:
		var rs: Array = def_of(c).get("reactions", [])
		for j in rs.size():
			if rs[j].scope == "challenge":
				p.reaction_uses.erase("%d:%d" % [c.id, j])


func _roll(pi: int) -> void:
	var p: Player = players[pi]
	var pool := pool_size(pi, challenge_kind)
	var carry: Array = p.kept_dice if challenge_kind == SHARPNESS else []
	var free := int(p.penalty.get("free_six", 0)) if challenge_kind == SHARPNESS else 0
	p.dice.clear()
	for i in int(pool.normal):
		if i < carry.size():
			var kept := Die.new(carry[i][0], carry[i][1])
			kept.carried = true
			p.dice.append(kept)
		elif i < carry.size() + free:
			var six := Die.new(6)
			six.origin = "Free die (%s boon), showing" % strength_card.get("name", "Strength")
			p.dice.append(six)
		else:
			p.dice.append(Die.new(_d6()))
	for i in int(pool.magic):
		p.dice.append(Die.new(_d6(), true))
	_log("  %s rolls %dd6: %s" % [p.name, p.dice.size(), str(values(pi, challenge_kind))])
	if challenge_kind == SHARPNESS and flag_sum(pi, "whetstone") > 0:
		var n := 0
		for d in p.dice:  # freshly rolled 1s only: kept, free and magic dice keep their faces
			if d.raw == 1 and not d.magic and not d.carried and d.origin == "":
				d.raw = _d6()
				d.origin = "Rolled 1, rerolled (Dwarven Whetstone) to"
				n += 1
		if n > 0:
			_log("  Dwarven Whetstone rerolls %d one%s: %s" % [n, "" if n == 1 else "s", str(values(pi, challenge_kind))])
	if challenge_kind == SHARPNESS:
		for k in int(p.penalty.get("opp_rerolls", 0)):
			_opponent_reroll(pi)


## Cockatrice: an opponent rerolls the die whose reroll hurts the most (if any does).
func _opponent_reroll(pi: int) -> void:
	var p: Player = players[pi]
	var base := outcome_score(pi, SHARPNESS)
	var best := -1
	var best_drop := 0.0
	for i in p.dice.size():
		var drop := base - expected_after_reroll(pi, i, SHARPNESS)
		if drop > best_drop:
			best_drop = drop
			best = i
	if best < 0:
		return
	var before := die_value(pi, p.dice[best], SHARPNESS)
	p.dice[best].raw = _d6()
	_log("  Cockatrice: an opponent rerolls %s's %d -> %d" % [p.name, before, die_value(pi, p.dice[best], SHARPNESS)])


func _end_challenges() -> void:
	var adjust := {}
	for pi in players.size():
		var p: Player = players[pi]
		if not p.wager:
			continue
		var best_other := -1000000
		for qi in players.size():
			if qi != pi:
				best_other = maxi(best_other, players[qi].quest_score)
		adjust[pi] = 1 if p.quest_score > best_other else -1
	for pi in adjust:
		var p: Player = players[pi]
		p.quest_score += adjust[pi]
		_log("  %s %s the wager (%+d)" % [p.name, "wins" if adjust[pi] > 0 else "loses", adjust[pi]])
	var summary := PackedStringArray()
	var rows := []
	for pi in players.size():
		var p: Player = players[pi]
		var challenge_score: int = p.quest_score - adjust.get(pi, 0)
		p.quest_scores.append(p.quest_score)
		p.total += p.quest_score
		summary.append("%s %d (total %d)" % [p.name, p.quest_score, p.total])
		rows.append({"player": pi, "challenge": challenge_score, "wager": adjust.get(pi, 0),
			"score": p.quest_score, "total": p.total})
	history.append({"type": "quest", "quest": quest, "final": quest == QUESTS.size() - 1, "rows": rows})
	_log("Quest %d Successes: %s" % [quest + 1, ", ".join(summary)])
	if quest == QUESTS.size() - 1:  # nothing to reserve for after the last Quest
		_end_quest()
		return
	phase = Phase.RESERVE
	_reserve_pos = -1
	_next_reserve()


# ------------------------------------------------------------------ reserve & quests

func act_reserve(card_id: int) -> bool:
	if phase != Phase.RESERVE:
		return false
	var p := player()
	var card := {}
	for c in reservable(current):  # reserving is required; _next_reserve skips players with no options
		if c.id == card_id:
			card = c
	if card.is_empty():
		return false
	p.reserve.append(card)
	moves.append(["reserve", card_id])
	_log("%s reserves %s" % [p.name, card.name])
	_next_reserve()
	return true


## Rule variants that take the reserve away from the leader (see VARIANTS).
func _leader_skips_reserve(pi: int) -> bool:
	var after_q2 := variants.has("no_leader_reserve") and quest == 1
	var always := variants.has("no_leader_reserve_always")
	return (after_q2 or always) and pi in winners()


func _next_reserve() -> void:
	while true:
		_reserve_pos += 1
		if _reserve_pos >= players.size():
			_end_quest()
			return
		var pi := order[_reserve_pos]
		if reservable(pi).is_empty():
			if _leader_skips_reserve(pi):
				_log("%s leads and reserves nothing (variant)" % players[pi].name)
			continue
		current = pi
		phase = Phase.RESERVE
		return


func _end_quest() -> void:
	for pi in players.size():
		for c in players[pi].ingredients:
			if not in_reserve(pi, c.id):
				discard.append(c)
	discard.append_array(market)
	market.clear()
	quest += 1
	if quest >= QUESTS.size():
		phase = Phase.GAME_OVER
		var names := PackedStringArray()
		for i in winners():
			names.append(players[i].name)
		_log("=== Game over: %s win%s! ===" % [" & ".join(names), "" if names.size() > 1 else "s"])
		return
	_start_quest()


func _start_quest() -> void:
	var q: Dictionary = QUESTS[quest].duplicate()
	if variants.has("q3_extra_draw") and quest == 2:
		q.draw += 1
		if players.size() == 4:
			for name in Q3_DUPES:  # new ids (see card_name): behaviour is looked up by name
				deck.append({"id": data.ingredients.size() + Q3_DUPES.find(name), "name": name})
			_shuffle(deck)
			_log("(Quest 3: a second %s shuffled into the deck)" % ", ".join(Q3_DUPES))
	_log("=== Quest %d ===" % (quest + 1))
	strength_card = strength_deck.pop_back()
	sharpness_card = sharpness_deck.pop_back()
	_log("Strength: %s (%s). Sharpness: %s (%s)" % [strength_card.name, strength_card.type, sharpness_card.name, sharpness_card.type])
	market.clear()
	for i in int(q.draw) * players.size():
		var c := _draw()
		if c.is_empty():
			break
		market.append(c)
	for p in players:
		p.ap = q.ap
		p.passed = false
		p.ingredients.clear()
		p.sharpen = 0
		p.electrum_dice = 0
		p.reaction_uses.clear()
		p.penalty.clear()
		p.kept_dice.clear()
		p.strength_sixes = 0
		p.wager = false
		p.wager_decided = false
		p.dice.clear()
		p.quest_score = 0
	if variants.has("q3_trailer_ap") and quest == 2:
		var leaders := winners()
		for pi in players.size():
			if not pi in leaders:
				players[pi].ap += 1
				_log("%s trails and gets +1 AP (variant)" % players[pi].name)
	_set_order()
	_turn_step = -1
	phase = Phase.CRAFT
	_advance_craft()


## Quest 1: highest 2d6 first. Later Quests: fewest Successes last Quest first, ties by 2d6.
func _set_order() -> void:
	var idx := range(players.size())
	var roll := {}
	var dice := {}
	for i in idx:
		dice[i] = [_d6(), _d6()]
		roll[i] = dice[i][0] + dice[i][1] + rng.randf() * 0.5  # fractional part stands in for re-rolls
	if quest == 0:
		idx.sort_custom(func(a, b): return roll[a] > roll[b])
	else:
		idx.sort_custom(func(a, b):
			var sa: int = players[a].quest_scores[-1]
			var sb: int = players[b].quest_scores[-1]
			return sa < sb if sa != sb else roll[a] > roll[b])
	order.assign(idx)
	var rows := []
	for i in order:
		var tied := false
		for j in order:
			if j != i and int(roll[j]) == int(roll[i]) \
					and (quest == 0 or players[j].quest_scores[-1] == players[i].quest_scores[-1]):
				tied = true
		rows.append({"player": i, "dice": dice[i], "tiebreak": tied,
			"successes": -1 if quest == 0 else players[i].quest_scores[-1]})
	history.append({"type": "order", "quest": quest, "rows": rows})
	var names := PackedStringArray()
	for i in order:
		names.append(players[i].name)
	_log("Turn order: " + ", ".join(names))


func _draw() -> Dictionary:
	if deck.is_empty():
		if discard.is_empty():
			return {}
		deck = discard
		discard = []
		_shuffle(deck)
		_log("(Ingredient deck reshuffled from the discards)")
	return deck.pop_back()


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


func _d6() -> int:
	return rng.randi_range(1, 6)


func _log(s: String) -> void:
	if quiet:
		return
	log_lines.append(s)
