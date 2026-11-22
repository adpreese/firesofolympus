extends "res://tests/test_case.gd"

var data := CardData.load_default()


func _new_game(n: int, seed_value: int) -> FoGame:
	var g := FoGame.new(data)
	var names := []
	var bots := []
	for i in n:
		names.append("P%d" % i)
		bots.append(true)
	g.setup(names, bots, seed_value)
	return g


func _card(card_name: String, id: int) -> Dictionary:
	return {"id": 1000 + id, "name": card_name}


func _play_out(g: FoGame, max_steps := 5000) -> int:
	var steps := 0
	while g.phase != FoGame.Phase.GAME_OVER and steps < max_steps:
		FoBot.step(g)
		steps += 1
	return steps


func test_full_bot_games_complete() -> void:
	for s in 300:
		var g := _new_game(2 + s % 3, s)
		var steps := _play_out(g)
		ok(g.phase == FoGame.Phase.GAME_OVER, "seed %d did not finish (%d steps)" % [s, steps])
		for p in g.players:
			eq(p.quest_scores.size(), 3, "seed %d quest count" % s)
			var sum := 0
			for q in p.quest_scores:
				sum += q
			eq(p.total, sum, "seed %d total" % s)
		ok(not g.winners().is_empty(), "seed %d has a winner" % s)


func test_same_seed_same_game() -> void:
	var a := _new_game(3, 42)
	var b := _new_game(3, 42)
	_play_out(a)
	_play_out(b)
	eq(a.log_lines, b.log_lines, "logs differ for same seed")


func test_snake_draft_order() -> void:
	var g := _new_game(4, 7)
	var seen: Array[int] = []
	while g.phase == FoGame.Phase.CRAFT:
		seen.append(g.current)
		g.act_sharpen()
	var o := g.order
	eq(seen, [o[0], o[1], o[2], o[3], o[3], o[2], o[1], o[0], o[0], o[1], o[2], o[3]], "snake order")


func test_rules_example_pool() -> void:
	var g := _new_game(2, 1)
	var p = g.players[0]
	p.ingredients = [_card("Hardened Steel", 1), _card("Gold", 2), _card("Bronze", 3)]
	g.strength_card = {"name": "Kraken", "type": "Giant"}
	g.sharpness_card = {"name": "Ice Dragon", "type": "Elemental"}
	eq(g.pool_size(0, FoGame.STRENGTH), {"normal": 4, "magic": 0}, "Kraken pool (rules example)")
	eq(g.pool_size(0, FoGame.SHARPNESS), {"normal": 5, "magic": 0}, "Gold adds vs Elemental")
	p.penalty = {"dice_loss": 1}
	eq(g.pool_size(0, FoGame.SHARPNESS), {"normal": 4, "magic": 0}, "Kraken penalty")


func test_die_values() -> void:
	var g := _new_game(2, 1)
	var p = g.players[0]
	p.ingredients = [_card("Bronze", 1)]
	eq(g.die_value(0, FoGame.Die.new(1), FoGame.STRENGTH), 2, "bronze 1->2")
	eq(g.die_value(0, FoGame.Die.new(6), FoGame.STRENGTH), 5, "bronze 6->5")
	p.ingredients = [_card("Sphinx's Milk", 1)]
	eq(g.die_value(0, FoGame.Die.new(2, true), FoGame.STRENGTH), 5, "magic low")
	eq(g.die_value(0, FoGame.Die.new(4, true), FoGame.STRENGTH), 6, "magic high")
	p.ingredients = [_card("Leather Grip", 1), _card("Silver Wire", 2)]
	eq(g.die_value(0, FoGame.Die.new(3), FoGame.STRENGTH), 4, "leather +2, silver -1")
	eq(g.die_value(0, FoGame.Die.new(5), FoGame.STRENGTH), 4, "silver -1")
	p.ingredients = [_card("Manticore Poison", 1)]
	p.penalty = {"cap": 4, "die_mod": -1}
	eq(g.die_value(0, FoGame.Die.new(6), FoGame.SHARPNESS), 4, "turtle cap after mods")
	eq(g.die_value(0, FoGame.Die.new(3), FoGame.SHARPNESS), 3, "manticore +1, golem -1")


func test_adamantium_goes_negative_and_ends_turn() -> void:
	var g := _new_game(2, 3)
	var me := g.current
	g.market.append(_card("Adamantium", 1))
	ok(g.act_draft(1001), "draft adamantium")
	eq(g.players[me].ap, -1, "3 - 1 - 3 AP")
	ok(g.is_done(me), "no more actions")


func test_rusty_bauble_swaps() -> void:
	var g := _new_game(2, 5)
	var me := g.current
	var other := 1 - me
	g.players[other].ingredients.append(_card("Gold", 1))
	g.market.append(_card("Rusty Bauble", 2))
	ok(g.act_draft(1002), "draft bauble")
	eq(g.phase, FoGame.Phase.SWAP, "swap phase")
	ok(not g.act_swap(me, 1001), "can't swap with yourself")
	ok(g.act_swap(other, 1001), "swap")
	eq(g.players[me].ingredients.map(func(c): return c.name), ["Gold"], "I get Gold")
	eq(g.players[other].ingredients.map(func(c): return c.name), ["Rusty Bauble"], "they get the Bauble")


func test_golden_apple_skips_strength() -> void:
	var g := _new_game(2, 9)
	g.players[0].ingredients.append(_card("Golden Apple", 1))
	g.players[0].ingredients.append(_card("Hardened Steel", 2))
	while g.phase == FoGame.Phase.CRAFT:
		g.act_pass()
	ok(g.challenge_kind == FoGame.STRENGTH and g.current == 1, "only P1 rolls Strength")
	ok("  P0 skips the Strength Challenge (Golden Apple)" in g.log_lines, "skip logged")


func test_reserve_persists_and_is_private() -> void:
	var g := _new_game(2, 11)
	while g.quest == 0:
		FoBot.step(g)
	for pi in 2:
		var p = g.players[pi]
		ok(p.reserve.size() <= 1, "at most one reserve after Quest 1")
		for c in p.reserve:
			ok(not g.market.has(c), "reserved card not in market")
			ok(not g.deck.has(c), "reserved card not in deck")
			ok(not g.discard.has(c), "reserved card not discarded")
			eq(g.reserve_options(pi).has(c), true, "owner can draft it")
			eq(g.reserve_options(1 - pi).has(c), false, "opponent can't")


func test_scabbard_dice_are_extra() -> void:
	var g := _new_game(2, 13)
	var p = g.players[0]
	p.ingredients = [_card("Hardened Steel", 1)]
	g.sharpness_card = {"name": "Razor Mantis", "type": "Demon"}
	p.penalty = {"dice_loss": 5}
	p.carry_raws = [6, 6]
	eq(g.pool_size(0, FoGame.SHARPNESS), {"normal": 2, "magic": 0}, "penalty can't remove kept dice")
	p.penalty = {}
	eq(g.pool_size(0, FoGame.SHARPNESS), {"normal": 5, "magic": 0}, "3 + 2 kept")


func test_electrum_only_counts_later_sharpening() -> void:
	var g := _new_game(2, 17)
	g.players[0].ap = 99
	g.players[1].ap = 99
	var me := g.current
	g.act_sharpen()                       # 1d6, before Electrum
	var other := g.current
	g.act_pass()
	g.market.append(_card("Electrum", 1))
	ok(g.act_draft(1001), "draft electrum")
	g.act_sharpen()                       # 2d6 + 1
	g.strength_card = {"name": "Kraken", "type": "Giant"}
	eq(g.pool_size(me, FoGame.STRENGTH).normal, 1 + 2 + 1, "only the later sharpening gets +1d6")
	eq(other == me, false, "turns alternate")


func test_bauble_moves_ap_with_card() -> void:
	var g := _new_game(2, 19)
	var me := g.current
	var other := 1 - me
	g.players[other].ingredients.append(_card("Beeswax", 1))
	var my_ap: int = g.players[me].ap
	var their_ap: int = g.players[other].ap
	g.market.append(_card("Rusty Bauble", 2))
	g.act_draft(1002)
	ok(g.act_swap(other, 1001), "swap for Beeswax")
	eq(g.players[me].ap, my_ap - 1 + 2, "taker gains Beeswax's +2")
	eq(g.players[other].ap, their_ap - 2, "previous owner loses it")


func test_reserve_is_required() -> void:
	var g := _new_game(2, 23)
	while g.phase != FoGame.Phase.RESERVE:
		FoBot.step(g)
	ok(not g.act_reserve(-1), "can't skip reserving")
	ok(g.act_reserve(g.reservable(g.current)[0].id), "reserve a card")


func test_breakdown_matches_die_value() -> void:
	# Every die rolled in many bot games: the explanation must end at the real value.
	for s in 40:
		var g := _new_game(2 + s % 3, 500 + s)
		var steps := 0
		while g.phase != FoGame.Phase.GAME_OVER and steps < 5000:
			if g.phase == FoGame.Phase.REACT:
				for d in g.player().dice:
					var b := g.die_breakdown(g.current, d, g.challenge_kind)
					eq(b[-1].value, g.die_value(g.current, d, g.challenge_kind), "seed %d breakdown end" % s)
			FoBot.step(g)
			steps += 1


func test_breakdown_steps() -> void:
	var g := _new_game(2, 1)
	var p = g.players[0]
	p.ingredients = [_card("Leather Grip", 1), _card("Silver Wire", 2), _card("Manticore Poison", 3)]
	g.strength_card = {"name": "Razorback Turtle", "type": "Giant"}
	p.penalty = {"cap": 4}
	var die := FoGame.Die.new(3)
	die.bonus = 1
	var b := g.die_breakdown(0, die, FoGame.SHARPNESS)
	eq(b.map(func(x): return x.value), [3, 2, 3, 5, 6, 4], "roll, silver, manticore, leather, reaction, cap")
	ok(b[-1].text.contains("Razorback Turtle"), "cap names the Challenge")
	p.ingredients = [_card("Bronze", 1)]
	p.penalty = {}
	eq(g.die_breakdown(0, FoGame.Die.new(4), FoGame.STRENGTH).size(), 1, "nothing changes a plain 4")


func test_history_matches_scores() -> void:
	for s in 30:
		var g := _new_game(2 + s % 3, 900 + s)
		_play_out(g)
		eq(g.history.size(), 9, "seed %d: 3 x (Strength, Sharpness, Quest)" % s)
		for q in 3:
			var st: Dictionary = g.history[q * 3]
			var sh: Dictionary = g.history[q * 3 + 1]
			var qr: Dictionary = g.history[q * 3 + 2]
			eq([st.type, st.kind, sh.kind, qr.type, qr.quest], ["challenge", "Strength", "Sharpness", "quest", q], "seed %d order" % s)
			eq(st.rows.size(), g.players.size(), "seed %d strength rows" % s)
			eq(sh.rows.size(), g.players.size(), "seed %d sharpness rows" % s)
			for row in sh.rows:
				var sum := 0
				for part in row.parts:
					sum += part[1]
				eq(sum, row.successes, "seed %d parts add up" % s)
			for row in qr.rows:
				eq(row.score, g.players[row.player].quest_scores[q], "seed %d quest score" % s)
				eq(row.score, row.challenge + row.wager, "seed %d wager adds up" % s)
				var sh_row = sh.rows.filter(func(r): return r.player == row.player)[0]
				eq(row.challenge, sh_row.successes, "seed %d challenge score" % s)
		eq(g.history[-1].final, true, "seed %d last quest is final" % s)


## Saves are seed + move list: replaying the moves (after a JSON round trip) must rebuild
## the same game at every point, mid-game included.
func test_replay_rebuilds_game() -> void:
	for s in 40:
		var g := _new_game(2 + s % 3, 500 + s)
		var stop := 20 + s * 7
		var steps := 0
		while g.phase != FoGame.Phase.GAME_OVER and steps < stop:
			FoBot.step(g)
			steps += 1
		var names := g.players.map(func(p): return p.name)
		var bots := g.players.map(func(p): return p.is_bot)
		var moves = JSON.parse_string(JSON.stringify(g.moves))
		var r := FoGame.replay(data, names, bots, g.seed_value, moves)
		ok(r != null, "seed %d replayed" % s)
		if r == null:
			continue
		eq(r.log_lines, g.log_lines, "seed %d log" % s)
		eq([r.phase, r.current, r.quest, r.rng.state], [g.phase, g.current, g.quest, g.rng.state], "seed %d state" % s)
		eq(r.history.size(), g.history.size(), "seed %d history" % s)
		# and the replayed game plays on exactly like the original
		_play_out(g)
		_play_out(r)
		eq(r.log_lines, g.log_lines, "seed %d continued" % s)


func test_replay_rejects_bad_moves() -> void:
	var g := _new_game(2, 7)
	ok(FoGame.replay(data, ["a", "b"], [true, true], 7, [["reserve", 3]]) == null, "illegal move")
	ok(FoGame.replay(data, ["a", "b"], [true, true], 7, [["nonsense"]]) == null, "unknown move")
	ok(FoGame.replay(data, ["a", "b"], [true, true], 7, ["draft"]) == null, "malformed move")
	ok(g.moves.is_empty(), "no moves before anyone acts")


## A clone with the same rng state plays out exactly like the original, and changing the
## clone never touches the original.
func test_clone_is_independent() -> void:
	for s in 20:
		var g := _new_game(2 + s % 3, 900 + s)
		for i in 15 + s * 9:
			if g.phase == FoGame.Phase.GAME_OVER:
				break
			FoBot.step(g)
		var before := g.log_lines.duplicate()
		var state := g.rng.state
		var c := g.clone()
		_play_out(c)
		eq(g.log_lines, before, "seed %d: original untouched" % s)
		eq(g.rng.state, state, "seed %d: original rng untouched" % s)
		_play_out(g)
		eq(c.players.map(func(p): return p.total), g.players.map(func(p): return p.total), "seed %d: same result" % s)
