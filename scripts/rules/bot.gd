class_name FoBot
extends RefCounted
## CPU opponents. `step` makes exactly one decision for g.current, so the UI can show bot
## moves one at a time.
##
## Levels: Easy is the heuristic with lots of noise and missed small gains; Normal is the
## heuristic; Hard picks crafting moves by simulating the rest of the Quest on clones
## (FoGame.clone) with fresh dice. Personalities bias how the heuristic values things.
## Nothing here draws from g.rng: saves replay the move list without the bot.

enum Level { EASY, NORMAL, HARD }
const LEVELS := ["Easy", "Normal", "Hard"]

## Rival blacksmiths. `bias` keys: dice, vs, magic, reactions, gamble, sharpen (added to a
## sharpening's worth), pass (added to the worth a draft must beat), bold_wager.
const PERSONAS := [
	{"key": "steady", "name": "Kallisto", "blurb": "Steady and sensible: takes the best card on the table.", "bias": {}},
	{"key": "sharpener", "name": "Brontes", "blurb": "Lives at the whetstone: sharpens early and often.",
		"bias": {"sharpen": 1.2, "dice": -0.2}},
	{"key": "gambler", "name": "Tycho", "blurb": "A gambler: loves rerolls, magic dice and a risky wager.",
		"bias": {"reactions": 1.0, "magic": 1.5, "gamble": 2.0, "bold_wager": true}},
	{"key": "hoarder", "name": "Melaina", "blurb": "A hoarder: grabs every Ingredient she can and rarely sharpens.",
		"bias": {"dice": 0.3, "sharpen": -1.0, "pass": -0.3}},
	{"key": "hunter", "name": "Phaedra", "blurb": "A monster hunter: chases cards that counter this Quest's Challenges.",
		"bias": {"vs": 1.2}},
]

const HARD_ROLLOUTS := 6       # simulated finishes of the Quest per candidate move
const HARD_CANDIDATES := 4      # drafts considered (best by heuristic), plus sharpen and pass


static func persona(key: String) -> Dictionary:
	for p in PERSONAS:
		if p.key == key:
			return p
	return PERSONAS[0]


## Make one decision for g.current and play it.
static func step(g: FoGame, level := Level.NORMAL, persona_key := "") -> void:
	var p := plan(g, level, persona_key)
	p.advance(INF)
	g.play_move(p.move)


## Start deciding for g.current. Only Hard crafting needs thinking time: call
## `advance(ms)` each frame until it returns true, then play `move`.
static func plan(g: FoGame, level := Level.NORMAL, persona_key := "") -> Plan:
	var bias: Dictionary = persona(persona_key).bias if persona_key != "" else {}
	var p := Plan.new()
	p.g = g
	p.pi = g.current
	p.moves_at = g.moves.size()
	var easy := level == Level.EASY
	match g.phase:
		FoGame.Phase.CRAFT:
			if level == Level.HARD:
				p.options = _hard_craft_options(g, bias)
			else:
				p.move = _craft_options(g, bias, 2.5 if easy else 0.3)[0].move
		FoGame.Phase.SWAP:
			if level == Level.HARD:
				p.options = _swap_options(g, bias, 0.0).slice(0, HARD_CANDIDATES)
			else:
				p.move = _swap_options(g, bias, 2.0 if easy else 0.0)[0].move
		FoGame.Phase.WAGER:
			p.move = ["wager", _should_wager(g, bias)]
		FoGame.Phase.REACT:
			p.move = _react(g, 0.6 if easy else 0.05)
		FoGame.Phase.RESERVE:
			p.move = _reserve(g, bias, 2.0 if easy else 0.0)
		_:
			p.move = ["pass"]
	if p.move.is_empty() and p.options.size() == 1:
		p.move = p.options[0].move
	return p


## A decision in progress. Hard compares candidate moves by simulating the rest of the Quest
## HARD_ROLLOUTS times each; every candidate sees the same dice sequences (seeded from the
## game, never from g.rng), so differences come from the move rather than luck.
class Plan:
	extends RefCounted
	var g: FoGame
	var pi := 0
	var moves_at := 0        # g.moves.size() when planned: the plan is stale once a move is made
	var options: Array = []  # [{move, value}] for Hard, best heuristic first
	var move: Array = []     # the decision; empty while still thinking
	var _totals: Array = []
	var _oi := 0
	var _k := 0

	func stale() -> bool:
		return g.moves.size() != moves_at

	## Think for up to budget_ms. True once `move` is decided.
	func advance(budget_ms: float) -> bool:
		var start := Time.get_ticks_usec()
		while move.is_empty():
			if _oi >= options.size():
				_decide()
				break
			if _totals.size() <= _oi:
				_totals.append(0.0)
			var c := g.clone()
			c.rng.seed = hash([g.seed_value, g.moves.size(), _k])
			if c.play_move(options[_oi].move):
				_totals[_oi] += FoBot._rollout(c, pi)
			else:
				_totals[_oi] = -INF
			_k += 1
			if _k >= FoBot.HARD_ROLLOUTS:
				_k = 0
				_oi += 1
			if (Time.get_ticks_usec() - start) / 1000.0 >= budget_ms:
				break
		return not move.is_empty()

	## Best average lead, with the heuristic value breaking near-ties.
	func _decide() -> void:
		var best_v := -INF
		for i in options.size():
			var v: float = _totals[i] / FoBot.HARD_ROLLOUTS + 0.05 * options[i].value
			if v > best_v:
				best_v = v
				move = options[i].move


## Rough worth of an Ingredient in "dice", given this Quest's Challenges.
static func card_value(g: FoGame, pi: int, card: Dictionary, bias := {}) -> float:
	var d := g.def_of(card)
	var p = g.players[pi]
	var v: float = float(d.get("dice", 0)) * (1.0 + bias.get("dice", 0.0))
	var vs: Dictionary = d.get("vs", {})
	for t in vs:
		if g.strength_card.type == t:
			v += (0.5 + bias.get("vs", 0.0)) * vs[t]
		if g.sharpness_card.type == t:
			v += (0.5 + bias.get("vs", 0.0)) * vs[t]
	v += (2.5 + bias.get("magic", 0.0)) * d.get("magic", 0)
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
		v += 0.2 + bias.get("gamble", 0.0)
	for r in d.get("reactions", []):
		v += (0.6 + 0.6 * bias.get("reactions", 0.0)) * r.uses
	return v


## A repeatable 0..1 tie-breaker that leaves g.rng alone, so a game's moves replay exactly
## without the bot (see FoGame.replay).
static func _noise(g: FoGame, salt: int) -> float:
	return float(hash([g.seed_value, g.moves.size(), salt]) & 0xFFFF) / 65535.0


## Heuristic crafting choices, best first: [{move, value}] where move is a FoGame move.
static func _craft_options(g: FoGame, bias: Dictionary, noise: float) -> Array:
	var pi := g.current
	var out := [{"move": ["pass"], "value": 0.3 + bias.get("pass", 0.0)}]
	for c in g.market + g.reserve_options(pi):
		out.append({"move": ["draft", c.id], "value": card_value(g, pi, c, bias) + _noise(g, c.id) * noise})
	if g.can_sharpen(pi):
		var p = g.players[pi]
		var v: float = FoGame.SHARPEN_DICE[p.sharpen] + g.flag_sum(pi, "electrum") + bias.get("sharpen", 0.0)
		out.append({"move": ["sharpen"], "value": v + _noise(g, -1) * noise})
	out.sort_custom(func(a, b): return a.value > b.value)
	return out


static func _swap_options(g: FoGame, bias: Dictionary, noise: float) -> Array:
	var out := []
	for t in g.swap_targets(g.current):
		var v := card_value(g, g.current, t.card, bias) + _noise(g, t.card.id) * noise
		out.append({"move": ["swap", t.player, t.card.id], "value": v})
	out.sort_custom(func(a, b): return a.value > b.value)
	return out


static func _should_wager(g: FoGame, bias: Dictionary) -> bool:
	var mine := 0
	var most_other := 0
	for pi in g.players.size():
		var pool := g.pool_size(pi, FoGame.SHARPNESS)
		var n: int = pool.normal + pool.magic
		if pi == g.current:
			mine = n
		else:
			most_other = maxi(most_other, n)
	return mine >= most_other - 1 if bias.get("bold_wager", false) else mine > most_other


## min_gain: smallest improvement worth a Reaction (Easy misses small ones).
static func _react(g: FoGame, min_gain: float) -> Array:
	var pi := g.current
	var p = g.players[pi]
	var kind := g.challenge_kind
	var vals := g.values(pi, kind)
	var base := g.outcome_of(pi, kind, vals)
	var best_gain := min_gain
	var best_key := ""
	var best_die := -1
	var reactions := g.available_reactions(pi)
	var gains := {}  # reaction kind -> gain per die, worked out once per kind
	for r in reactions:
		if r.left <= 0 or r.kind == "keep":
			continue
		if not gains.has(r.kind):
			var per_die := []
			for i in p.dice.size():
				var after: float
				if r.kind == "reroll":
					after = g.expected_after_reroll(pi, i, kind, vals)
				else:
					var old: int = vals[i]
					p.dice[i].bonus += 1
					vals[i] = g.die_value(pi, p.dice[i], kind)
					after = g.outcome_of(pi, kind, vals)
					p.dice[i].bonus -= 1
					vals[i] = old
				per_die.append(after - base)
			gains[r.kind] = per_die
		for i in p.dice.size():
			if gains[r.kind][i] > best_gain:
				best_gain = gains[r.kind][i]
				best_key = r.key
				best_die = i
	if best_key != "":
		return ["react", best_key, best_die]
	# Jeweled Scabbard: carry the highest dice into the Sharpness Challenge.
	for r in reactions:
		if r.kind == "keep" and r.left > 0:
			var pick := -1
			for i in p.dice.size():
				if not p.dice[i].carried and (pick < 0 or p.dice[i].raw > p.dice[pick].raw):
					pick = i
			if pick >= 0:
				return ["react", r.key, pick]
	return ["finish"]


static func _reserve(g: FoGame, bias: Dictionary, noise: float) -> Array:
	var best_id := -1
	var best_v := -INF
	for c in g.reservable(g.current):
		var v := card_value(g, g.current, c, bias) + _noise(g, c.id) * noise
		if v > best_v:
			best_v = v
			best_id = c.id
	return ["reserve", best_id]


# ------------------------------------------------------------------ Hard: look-ahead

## The heuristic's top HARD_CANDIDATES drafts, plus sharpening and passing.
static func _hard_craft_options(g: FoGame, bias: Dictionary) -> Array:
	var out := []
	var drafts := 0
	for o in _craft_options(g, bias, 0.0):
		if o.move[0] == "draft":
			drafts += 1
			if drafts > HARD_CANDIDATES:
				continue
		out.append(o)
	return out


## Play `c` to the end of its Quest's Challenges with Normal bots; pi's lead in total Successes.
static func _rollout(c: FoGame, pi: int) -> float:
	var scored: int = c.players[pi].quest_scores.size()
	var guard := 0
	while c.players[pi].quest_scores.size() == scored and c.phase != FoGame.Phase.GAME_OVER and guard < 2000:
		step(c)
		guard += 1
	var best_other := -1000000
	for qi in c.players.size():
		if qi != pi:
			best_other = maxi(best_other, c.players[qi].total)
	return float(c.players[pi].total - best_other)
