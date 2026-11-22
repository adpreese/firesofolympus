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
