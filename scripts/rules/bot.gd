class_name FoBot
extends RefCounted
## Simple heuristic opponent. `step` makes exactly one decision for game.current,
## so the UI can show bot moves one at a time.


static func step(g: FoGame) -> void:
	match g.phase:
		FoGame.Phase.CRAFT:
			_craft(g)
		FoGame.Phase.SWAP:
			_swap(g)
		FoGame.Phase.WAGER:
			g.act_wager(_should_wager(g))
		FoGame.Phase.REACT:
			_react(g)
		FoGame.Phase.RESERVE:
			_reserve(g)


## Rough worth of an Ingredient in "dice", given this Quest's Challenges.
static func card_value(g: FoGame, pi: int, card: Dictionary) -> float:
	var d := g.def_of(card)
	var p = g.players[pi]
	var v := float(d.get("dice", 0))
	var vs: Dictionary = d.get("vs", {})
	for t in vs:
		if g.strength_card.type == t:
			v += 0.5 * vs[t]
		if g.sharpness_card.type == t:
			v += 0.5 * vs[t]
	v += 2.5 * d.get("magic", 0)
	v += 1.2 * d.get("ap", 0)
	v += 2.0 * d.get("mod", 0)
	v += 1.5 * d.get("sharp_mod", 0)
	v += 1.5 * d.get("bonus_success", 0)
	if d.get("bronze", false):
		v += 0.3
	if d.get("leather", false):
		v += 1.0
	if d.get("mithril", false):
		v += 1.0
	if d.get("hyacinth", false):
		v += p.ingredients.size() + 1
	if d.get("electrum", false):
		v += maxi(0, mini(3 - p.sharpen, p.ap - 2))  # sharpenings still affordable after drafting
	if d.get("no_sharpen", false):
		v -= 0.8 * (3 - p.sharpen)
	if d.get("skip_strength", false):
		v += 1.5
	if d.get("swap_on_draft", false):
		v += 1.0
	if d.get("gamble", false):
		v += 0.2
	for r in d.get("reactions", []):
		v += 0.6 * r.uses
	return v


static func _craft(g: FoGame) -> void:
	var pi := g.current
	var best := 0.3
	var action := "pass"
	var card_id := -1
	for c in g.market + g.reserve_options(pi):
		var v := card_value(g, pi, c) + _noise(g, c.id) * 0.3
		if v > best:
			best = v
			action = "draft"
			card_id = c.id
	if g.can_sharpen(pi):
		var p = g.players[pi]
		var v: float = FoGame.SHARPEN_DICE[p.sharpen] + g.flag_sum(pi, "electrum")
		if v > best:
			action = "sharpen"
	match action:
		"draft":
			g.act_draft(card_id)
		"sharpen":
			g.act_sharpen()
		_:
			g.act_pass()


## A repeatable 0..1 tie-breaker that leaves g.rng alone, so a game's moves replay exactly
## without the bot (see FoGame.replay).
static func _noise(g: FoGame, salt: int) -> float:
	return float(hash([g.seed_value, g.moves.size(), salt]) & 0xFFFF) / 65535.0


static func _swap(g: FoGame) -> void:
	var best := {}
	var best_v := -INF
	for t in g.swap_targets(g.current):
		var v := card_value(g, g.current, t.card)
		if v > best_v:
			best_v = v
			best = t
	g.act_swap(best.player, best.card.id)


static func _should_wager(g: FoGame) -> bool:
	var mine := 0
	var most_other := 0
	for pi in g.players.size():
		var pool := g.pool_size(pi, FoGame.SHARPNESS)
		var n: int = pool.normal + pool.magic
		if pi == g.current:
			mine = n
		else:
			most_other = maxi(most_other, n)
	return mine > most_other


static func _react(g: FoGame) -> void:
	var pi := g.current
	var p = g.players[pi]
	var kind := g.challenge_kind
	var base := g.outcome_score(pi, kind)
	var best_gain := 0.05
	var best_key := ""
	var best_die := -1
	var reactions := g.available_reactions(pi)
	for r in reactions:
		if r.left <= 0 or r.kind == "keep":
			continue
		for i in p.dice.size():
			var after: float
			if r.kind == "reroll":
				after = g.expected_after_reroll(pi, i, kind)
			else:
				p.dice[i].bonus += 1
				after = g.outcome_score(pi, kind)
				p.dice[i].bonus -= 1
			if after - base > best_gain:
				best_gain = after - base
				best_key = r.key
				best_die = i
	if best_key != "":
		g.apply_reaction(best_key, best_die)
		return
	# Jeweled Scabbard: carry the highest dice into the Sharpness Challenge.
	for r in reactions:
		if r.kind == "keep" and r.left > 0:
			var pick := -1
			for i in p.dice.size():
				if not p.dice[i].carried and (pick < 0 or p.dice[i].raw > p.dice[pick].raw):
					pick = i
			if pick >= 0:
				g.apply_reaction(r.key, pick)
				return
	g.finish_reactions()


static func _reserve(g: FoGame) -> void:
	var best_id := -1
	var best_v := -INF
	for c in g.reservable(g.current):
		var v := card_value(g, g.current, c)
		if v > best_v:
			best_v = v
			best_id = c.id
	g.act_reserve(best_id)
