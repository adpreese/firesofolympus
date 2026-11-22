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
	var carried := false   # Strength: marked to keep (Jeweled Scabbard); Sharpness: was kept

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
	var reaction_uses := {}        # "card_id:index" -> uses left
	var penalty := {}              # from the Strength Challenge, applied to Sharpness
	var carry_raws: Array = []     # Jeweled Scabbard dice kept for Sharpness
	var wager := false
	var wager_decided := false
	var dice: Array = []           # Array of Die for the Challenge being rolled
	var quest_score := 0

	func _init(n: String, bot: bool) -> void:
		name = n
		is_bot = bot


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

var _turn_step := -1
var _challenge_pos := -1
var _reserve_pos := -1
var _pending_bauble_id := -1


func _init(card_data: CardData) -> void:
	data = card_data


func setup(names: Array, bots: Array, seed_value: int) -> void:
	rng.seed = seed_value
	players.clear()
	for i in names.size():
		players.append(Player.new(names[i], bots[i]))
	deck.clear()
	discard.clear()
	for i in data.ingredients.size():
		deck.append({"id": i, "name": data.ingredients[i].name})
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
	return data.def(card.name)


func text_of(card: Dictionary) -> String:
	return data.ingredient(card.name).get("text", "")


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
	var electrum := flag_sum(pi, "electrum")
	for i in p.sharpen:
		normal += SHARPEN_DICE[i] + electrum
	if kind == SHARPNESS:
		normal -= int(p.penalty.get("dice_loss", 0))
	if normal < 0:  # penalties eat normal dice first, then magic ones
		magic = maxi(0, magic + normal)
		normal = 0
	return {"normal": normal, "magic": magic}


## Final result of one die: Effects, then Modifiers, then Reaction bonuses, then caps.
func die_value(pi: int, die: Die, kind: String) -> int:
	var v := die.raw
	if die.magic:
		v = 5 if v <= 3 else 6
	if flag_sum(pi, "bronze") > 0:
		if v == 1:
			v = 2
		elif v == 6:
			v = 5
	var m := flag_sum(pi, "mod")
	if flag_sum(pi, "leather") > 0 and (v == 2 or v == 3):
		m += 2
	var penalty: Dictionary = players[pi].penalty
	if kind == SHARPNESS:
		m += flag_sum(pi, "sharp_mod") + int(penalty.get("die_mod", 0))
	v += m + die.bonus
	if kind == SHARPNESS and penalty.has("cap"):
		v = mini(v, penalty.cap)
	return v


func values(pi: int, kind: String) -> Array[int]:
	var out: Array[int] = []
	for d in players[pi].dice:
		out.append(die_value(pi, d, kind))
	return out


## Strength: the penalty dict. Sharpness: {"successes": n}.
func evaluate(pi: int, kind: String) -> Dictionary:
	var vals := values(pi, kind)
	var card := challenge_card(kind)
	if kind == STRENGTH:
		return Scoring.strength_penalty(card.name, vals)
	var s := Scoring.sharpness_successes(card.name, vals)
	var mithril := flag_sum(pi, "mithril")
	for v in vals:
		if v >= 6:
			s += mithril
	s += flag_sum(pi, "bonus_success")
	return {"successes": s}


## Higher is better: Successes for Sharpness, minus penalty cost for Strength.
func outcome_score(pi: int, kind: String) -> float:
	var e := evaluate(pi, kind)
	return float(e.successes) if kind == SHARPNESS else -Scoring.penalty_cost(e)


func expected_after_reroll(pi: int, die_idx: int, kind: String) -> float:
	var d: Die = players[pi].dice[die_idx]
	var old := d.raw
	var total := 0.0
	for r in range(1, 7):
		d.raw = r
		total += outcome_score(pi, kind)
	d.raw = old
	return total / 6.0


func describe_outcome(pi: int) -> String:
	var e := evaluate(pi, challenge_kind)
	if challenge_kind == STRENGTH:
		return Scoring.describe_penalty(e)
	return "%d Successes" % e.successes


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
			var key := "%d:%d" % [c.id, j]
			var left: int = p.reaction_uses.get(key, r.uses)
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
	return players[pi].ingredients.filter(func(c): return not in_reserve(pi, c.id))


func winners() -> Array[int]:
	var best := -1000000
	for p in players:
		best = maxi(best, p.total)
	var out: Array[int] = []
	for i in players.size():
		if players[i].total == best:
			out.append(i)
	return out


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
	p.sharpen += 1
	p.ap -= 1
	_log("%s sharpens (+%dd6, %d AP left)" % [p.name, SHARPEN_DICE[p.sharpen - 1], p.ap])
	_advance_craft()
	return true


func act_pass() -> bool:
	if phase != Phase.CRAFT:
		return false
	player().passed = true
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
	var taken: Dictionary = q.ingredients[ti]
	q.ingredients[ti] = p.ingredients[bi]
	p.ingredients[bi] = taken
	_log("  Rusty Bauble: %s swaps it for %s's %s" % [p.name, q.name, taken.name])
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
	var before := die_value(current, die, challenge_kind)
	match r.kind:
		"reroll":
			die.raw = _d6()
			_log("  %s rerolls a %d -> %d (%s)" % [p.name, before, die_value(current, die, challenge_kind), r.card])
		"plus_one":
			die.bonus += 1
			_log("  %s adds +1 to a %d (%s)" % [p.name, before, r.card])
		"keep":
			if die.carried:
				die.carried = false
				p.reaction_uses[key] = r.left + 1
				return true
			if r.left <= 0:
				return false
			die.carried = true
	p.reaction_uses[key] = r.left - 1
	return true


func finish_reactions() -> bool:
	if phase != Phase.REACT:
		return false
	var p := player()
	var e := evaluate(current, challenge_kind)
	var vals := values(current, challenge_kind)
	if challenge_kind == STRENGTH:
		p.penalty = e
		p.carry_raws.clear()
		for d in p.dice:
			if d.carried:
				p.carry_raws.append(d.raw)
		var keep := "" if p.carry_raws.is_empty() else " (keeps %s for Sharpness)" % str(p.carry_raws)
		_log("  %s: %s -> %s%s" % [p.name, str(vals), Scoring.describe_penalty(e), keep])
	else:
		p.quest_score = e.successes
		_log("  %s: %s -> %d Successes" % [p.name, str(vals), e.successes])
	# "once per Quest" reactions are spent after the Challenge they were first used in.
	for c in p.ingredients:
		var rs: Array = def_of(c).get("reactions", [])
		for j in rs.size():
			var key := "%d:%d" % [c.id, j]
			if rs[j].scope == "quest_once" and p.reaction_uses.get(key, rs[j].uses) < rs[j].uses:
				p.reaction_uses[key] = 0
	_next_challenge_player()
	return true


func _start_challenges() -> void:
	challenge_kind = STRENGTH
	_challenge_pos = -1
	_log("-- Strength Challenge: %s --" % strength_card.name)
	_next_challenge_player()


func _next_challenge_player() -> void:
	while true:
		_challenge_pos += 1
		if _challenge_pos >= players.size():
			if challenge_kind == SHARPNESS:
				_end_challenges()
				return
			challenge_kind = SHARPNESS
			_challenge_pos = 0
			_log("-- Sharpness Challenge: %s --" % sharpness_card.name)
		var pi := order[_challenge_pos]
		var p: Player = players[pi]
		current = pi
		_reset_challenge_reactions(pi)
		if challenge_kind == STRENGTH and flag_sum(pi, "skip_strength") > 0:
			_log("  %s skips the Strength Challenge (Golden Apple)" % p.name)
			p.penalty = {}
			continue
		if challenge_kind == SHARPNESS and flag_sum(pi, "gamble") > 0 and not p.wager_decided:
			phase = Phase.WAGER
			return
		_roll(pi)
		phase = Phase.REACT
		return


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
	var carry: Array = p.carry_raws if challenge_kind == SHARPNESS else []
	p.dice.clear()
	for i in int(pool.normal):
		if i < carry.size():
			var kept := Die.new(carry[i])
			kept.carried = true
			p.dice.append(kept)
		else:
			p.dice.append(Die.new(_d6()))
	for i in int(pool.magic):
		p.dice.append(Die.new(_d6(), true))
	_log("  %s rolls %dd6: %s" % [p.name, p.dice.size(), str(values(pi, challenge_kind))])
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
	for p in players:
		p.quest_scores.append(p.quest_score)
		p.total += p.quest_score
		summary.append("%s %d (total %d)" % [p.name, p.quest_score, p.total])
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
	if card_id >= 0:
		var card := {}
		for c in reservable(current):
			if c.id == card_id:
				card = c
		if card.is_empty():
			return false
		p.reserve.append(card)
		_log("%s reserves %s" % [p.name, card.name])
	_next_reserve()
	return true


func _next_reserve() -> void:
	while true:
		_reserve_pos += 1
		if _reserve_pos >= players.size():
			_end_quest()
			return
		var pi := order[_reserve_pos]
		if reservable(pi).is_empty():
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
	var q: Dictionary = QUESTS[quest]
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
		p.reaction_uses.clear()
		p.penalty.clear()
		p.carry_raws.clear()
		p.wager = false
		p.wager_decided = false
		p.dice.clear()
		p.quest_score = 0
	_set_order()
	_turn_step = -1
	phase = Phase.CRAFT
	_advance_craft()


## Quest 1: highest 2d6 first. Later Quests: fewest Successes last Quest first, ties by 2d6.
func _set_order() -> void:
	var idx := range(players.size())
	var roll := {}
	for i in idx:
		roll[i] = _d6() + _d6() + rng.randf() * 0.5  # fractional part stands in for re-rolls
	if quest == 0:
		idx.sort_custom(func(a, b): return roll[a] > roll[b])
	else:
		idx.sort_custom(func(a, b):
			var sa: int = players[a].quest_scores[-1]
			var sb: int = players[b].quest_scores[-1]
			return sa < sb if sa != sb else roll[a] > roll[b])
	order.assign(idx)
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
	log_lines.append(s)
