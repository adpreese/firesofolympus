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
	g.order.assign([0, 1])  # P0 faces the Challenges first
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
	p.kept_dice = [[6, false], [6, false]]
	eq(g.pool_size(0, FoGame.SHARPNESS), {"normal": 2, "magic": 0}, "penalty can't remove kept dice")
	p.penalty = {}
	eq(g.pool_size(0, FoGame.SHARPNESS), {"normal": 5, "magic": 0}, "3 + 2 kept")


func test_scabbard_keeps_magic_dice_magic() -> void:
	var g := _new_game(2, 13)
	var p = g.players[0]
	p.ingredients = [_card("Jeweled Scabbard", 1), _card("Sphinx's Milk", 2)]
	g.strength_card = {"name": "Kraken", "type": "Giant"}
	g.sharpness_card = {"name": "Razor Mantis", "type": "Demon"}
	g.phase = FoGame.Phase.REACT
	g.current = 0
	g.challenge_kind = FoGame.STRENGTH
	g._result = {"rows": []}
	var d := FoGame.Die.new(1, true)
	d.carried = true
	p.dice = [d, FoGame.Die.new(4)]
	ok(g.finish_reactions(), "finish Strength")
	eq(p.kept_dice, [[1, true]], "kept die remembers it was magic")
	g.challenge_kind = FoGame.SHARPNESS
	g._roll(0)
	var back = p.dice[0]
	eq([back.raw, back.magic, back.carried], [1, true, true], "comes back magic and kept")
	eq(g.die_breakdown(0, back, FoGame.SHARPNESS)[1].value, 5, "still converts 1 -> 5")


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


## Variant no_leader_reserve: the leader(s) after Quest 2 skip the reserve; everyone else reserves.
func test_variant_no_leader_reserve() -> void:
	var checked := 0
	for s in 40:
		var g := FoGame.new(data)
		g.variants = {"no_leader_reserve": true}
		g.setup(["a", "b", "c"], [true, true, true], 7100 + s)
		var leaders: Array[int] = []
		var reserves_q1 := []
		while g.phase != FoGame.Phase.GAME_OVER:
			if g.phase == FoGame.Phase.RESERVE and g.quest == 1 and leaders.is_empty():
				leaders = g.winners()
				reserves_q1 = g.players.map(func(p): return p.reserve.size())
			if g.phase == FoGame.Phase.RESERVE and g.quest == 1:
				ok(not g.current in leaders, "seed %d: leader %d asked to reserve" % [s, g.current])
			FoBot.step(g)
		if leaders.is_empty():
			continue
		checked += 1
		for i in 3:
			var gained: int = g.players[i].reserve.size() - reserves_q1[i]
			if i in leaders:
				eq(gained, 0, "seed %d: leader %d reserved after Quest 2" % [s, i])
		var clone := g.clone()
		eq(clone.variants, g.variants, "clones play the same variant")
	ok(checked > 30, "Quest 2 reserve phase reached in %d games" % checked)


func test_variant_off_by_default() -> void:
	var g := _new_game(3, 7200)
	eq(g.variants, {}, "standard rules")
	while g.phase != FoGame.Phase.GAME_OVER:
		if g.phase == FoGame.Phase.RESERVE and g.quest == 1:
			ok(not g.reservable(g.current).is_empty(), "a leader may reserve under standard rules")
		FoBot.step(g)


## Variant no_leader_reserve_always: the leader skips the reserve after Quest 1 and after Quest 2.
func test_variant_no_leader_reserve_always() -> void:
	var skipped := [0, 0]
	for s in 40:
		var g := FoGame.new(data)
		g.variants = {"no_leader_reserve_always": true}
		g.setup(["a", "b", "c"], [true, true, true], 7300 + s)
		var before := {}
		while g.phase != FoGame.Phase.GAME_OVER:
			if g.phase == FoGame.Phase.RESERVE and not before.has(g.quest):
				before[g.quest] = [g.winners(), g.players.map(func(p): return p.reserve.size())]
			if g.phase == FoGame.Phase.RESERVE:
				ok(not g.current in before[g.quest][0], "seed %d Q%d: leader %d asked to reserve" % [s, g.quest + 1, g.current])
			var q := g.quest
			FoBot.step(g)
			if g.quest != q and before.has(q):
				for i in before[q][0]:
					eq(g.players[i].reserve.size(), before[q][1][i], "seed %d Q%d: leader %d reserved" % [s, q + 1, i])
					skipped[q] += 1
	ok(skipped[0] > 30 and skipped[1] > 30, "leaders skipped after Q1 and Q2: %s" % str(skipped))


func test_variant_q3_extra_draw() -> void:
	for n in [2, 3, 4]:
		var sizes := {}
		for extra in [false, true]:
			var g := _new_game(n, 7400 + n) if not extra else FoGame.new(data)
			if extra:
				g.variants = {"q3_extra_draw": true}
				g.setup(["a", "b", "c", "d"].slice(0, n), [true, true, true, true].slice(0, n), 7400 + n)
			var seen := []
			var free := 0  # cards not held in anyone's reserve when Quest 3 starts
			while g.phase != FoGame.Phase.GAME_OVER:
				if seen.size() == g.quest and g.phase == FoGame.Phase.CRAFT:
					var drafted := 0
					var reserved := 0
					for pi in n:
						var p: FoGame.Player = g.players[pi]
						drafted += p.ingredients.filter(func(c): return not g.in_reserve(pi, c.id)).size()
						reserved += p.reserve.size()
					seen.append(g.market.size() + drafted)
					free = data.ingredients.size() + (FoGame.Q3_DUPES.size() if extra and n == 4 else 0) - reserved
				FoBot.step(g)
			sizes[extra] = [seen, free]
		eq(sizes[false][0], [3 * n, 4 * n, 4 * n], "%d players, standard draws" % n)
		# One more per player, unless the deck runs dry: reserved cards never return to it.
		eq(sizes[true][0], [3 * n, 4 * n, mini(5 * n, sizes[true][1])], "%d players, Quest 3 draws" % n)
		eq(sizes[true][0][2], 5 * n, "%d players: the full 5 per player" % n)


func test_variant_q3_trailer_ap() -> void:
	var checked := 0
	for s in 30:
		for on in [false, true]:
			var g := FoGame.new(data)
			if on:
				g.variants = {"q3_trailer_ap": true}
			g.setup(["a", "b", "c"], [true, true, true], 7500 + s)
			while g.phase != FoGame.Phase.GAME_OVER and g.quest < 2:
				FoBot.step(g)
			# Quest 3 has just been set up: nobody has acted in it yet.
			var leaders := g.winners()
			for pi in 3:
				var want := 5 + (1 if on and not pi in leaders else 0)
				eq(g.players[pi].ap, want, "seed %d %s: P%d (leader: %s)" % [s, "variant" if on else "standard", pi, pi in leaders])
			checked += 1
	eq(checked, 60, "every game reached Quest 3")


func test_variant_olive_bough() -> void:
	var g := FoGame.new(data)
	g.variants = {"olive_bough": true}
	g.setup(["a", "b", "c"], [true, true, true], 7600)
	var all := g.deck + g.market
	for p in g.players:
		all += p.ingredients
	var bough := all.filter(func(c): return c.name == "Olive Bough")
	eq(bough.size(), 1, "one Olive Bough in the game")
	eq(g.card_name(bough[0].id), "Olive Bough", "its id maps back to its name")
	eq(g.def_of(bough[0]).get("dice", 0), 1, "+1D6")
	eq(_new_game(3, 7600).deck.filter(func(c): return c.name == "Olive Bough").size(), 0, "not in standard games")
	# Final tie: the holder wins alone; mid-game it changes nothing.
	for p in g.players:
		p.total = 10
		p.ingredients = []
	g.players[2].total = 7
	g.players[1].ingredients = [bough[0]]
	eq(g.winners(), [0, 1] as Array[int], "mid-game ties stand")
	g.phase = FoGame.Phase.GAME_OVER
	eq(g.winners(), [1] as Array[int], "the holder wins a final tie")
	g.players[1].total = 9
	eq(g.winners(), [0] as Array[int], "no help when behind")
	g.players[1].total = 10
	g.players[1].ingredients = []
	g.players[2].ingredients = [bough[0]]
	eq(g.winners(), [0, 1] as Array[int], "no help to someone not tied")
	# Full games still finish with the card in the deck.
	for s in 20:
		var h := FoGame.new(data)
		h.variants = {"olive_bough": true}
		h.setup(["a", "b", "c", "d"], [true, true, true, true], 7700 + s)
		_play_out(h)
		ok(h.phase == FoGame.Phase.GAME_OVER, "seed %d finished" % s)


## Put player 0 mid-Challenge with these dice, as if just rolled.
func _reacting(g: FoGame, kind: String, dice: Array) -> void:
	g.phase = FoGame.Phase.REACT
	g.current = 0
	g.challenge_kind = kind
	g._result = {"rows": []}
	g.players[0].dice = dice


func test_phoenix_egg_keeps_one_and_shares_with_scabbard() -> void:
	var g := _new_game(2, 31)
	var p = g.players[0]
	p.ingredients = [_card("Phoenix Egg", 1), _card("Jeweled Scabbard", 2)]
	g.strength_card = {"name": "Kraken", "type": "Giant"}
	g.sharpness_card = {"name": "Razor Mantis", "type": "Demon"}
	eq(g.pool_size(0, FoGame.STRENGTH).normal, 3, "+2d6 +1d6")
	_reacting(g, FoGame.STRENGTH, [FoGame.Die.new(6), FoGame.Die.new(5), FoGame.Die.new(4), FoGame.Die.new(3)])
	var egg := "1001:0"
	ok(g.apply_reaction(egg, 0), "egg keeps a die")
	ok(not g.apply_reaction(egg, 1), "egg has only 1 keep")
	ok(g.apply_reaction("1002:0", 0), "un-keep with the Scabbard's button")
	ok(g.apply_reaction(egg, 1), "the egg's keep was refunded")
	ok(g.apply_reaction("1002:0", 2) and g.apply_reaction("1002:0", 3), "scabbard still has both")
	ok(g.finish_reactions(), "finish")
	eq(p.kept_dice.size(), 3, "three dice kept")


func test_dwarven_whetstone_rerolls_ones() -> void:
	var g := _new_game(2, 32)
	var p = g.players[0]
	p.ingredients = [_card("Dwarven Whetstone", 1), _card("Adamantium", 2), _card("Adamantium", 3)]
	g.sharpness_card = {"name": "Razor Mantis", "type": "Demon"}
	g.current = 0
	g.challenge_kind = FoGame.SHARPNESS
	var saw_reroll := false
	for k in 30:
		g._roll(0)
		for d in p.dice:
			if d.origin != "":
				saw_reroll = true
				eq(g.die_breakdown(0, d, FoGame.SHARPNESS)[0].text.begins_with("Rolled 1, rerolled"), true, "explained")
			elif not d.carried:
				ok(d.raw != 1, "a fresh 1 survived")
	ok(saw_reroll, "rerolled some 1s in 30 rolls of 8 dice")
	g.challenge_kind = FoGame.STRENGTH
	var ones := 0
	for k in 30:
		g._roll(0)
		ones += p.dice.filter(func(d): return d.raw == 1).size()
	ok(ones > 0, "Strength 1s are left alone")


func test_magic_mirror_copies_in_sharpness() -> void:
	var g := _new_game(2, 33)
	var p = g.players[0]
	p.ingredients = [_card("Magic Mirror", 1), _card("Sphinx's Milk", 2)]
	g.sharpness_card = {"name": "Razor Mantis", "type": "Demon"}
	_reacting(g, FoGame.STRENGTH, [FoGame.Die.new(6)])
	eq(g.available_reactions(0), [], "not in Strength")
	_reacting(g, FoGame.SHARPNESS, [FoGame.Die.new(2, true), FoGame.Die.new(3)])
	ok(g.apply_reaction("1001:0", 0), "copy the magic die")
	eq(p.dice.size(), 3, "a third die")
	eq([p.dice[2].raw, p.dice[2].magic], [2, true], "same face, still magic")
	eq(g.values(0, FoGame.SHARPNESS), [5, 3, 5] as Array[int], "both count as 5")
	ok(not g.apply_reaction("1001:0", 1), "one copy only")


func test_orichalcum_needs_a_sharpening() -> void:
	var g := _new_game(2, 34)
	var p = g.players[0]
	p.ingredients = [_card("Orichalcum", 1)]
	eq(g.pool_size(0, FoGame.STRENGTH).normal, 1, "1d6 unsharpened")
	p.sharpen = 1
	eq(g.pool_size(0, FoGame.STRENGTH).normal, 2 + 1, "2d6 + the sharpening's 1d6")


func test_blood_ruby_rerolls_from_unused_ap() -> void:
	var g := _new_game(2, 35)
	var p = g.players[0]
	p.ingredients = [_card("Blood Ruby", 1)]
	g.strength_card = {"name": "Kraken", "type": "Giant"}
	p.ap = 2
	_reacting(g, FoGame.STRENGTH, [FoGame.Die.new(1), FoGame.Die.new(1), FoGame.Die.new(1)])
	eq(g.available_reactions(0)[0].left, 2, "2 AP left = 2 rerolls")
	ok(g.apply_reaction("1001:0", 0) and g.apply_reaction("1001:0", 1), "two rerolls")
	ok(not g.apply_reaction("1001:0", 2), "no third")
	g._reset_challenge_reactions(0)
	eq(g.available_reactions(0)[0].left, 2, "again next Challenge")
	p.ap = -1
	g._reset_challenge_reactions(0)
	eq(g.available_reactions(0), [], "negative AP gives none")


func test_branch_of_yggdrasil_counts_strength_sixes() -> void:
	var g := _new_game(2, 36)
	var p = g.players[0]
	p.ingredients = [_card("Branch of Yggdrasil", 1)]
	g.strength_card = {"name": "Kraken", "type": "Giant"}
	g.sharpness_card = {"name": "Razor Mantis", "type": "Demon"}
	_reacting(g, FoGame.STRENGTH, [FoGame.Die.new(6), FoGame.Die.new(6), FoGame.Die.new(2)])
	eq(g.available_reactions(0), [], "no rerolls in Strength")
	ok(g.finish_reactions(), "finish Strength")
	eq(p.strength_sixes, 2, "two 6s")
	_reacting(g, FoGame.SHARPNESS, [FoGame.Die.new(1)])
	eq(g.available_reactions(0)[0].left, 2, "two Sharpness rerolls")


func test_lightning_bolt_cannot_be_reserved() -> void:
	var g := _new_game(2, 37)
	var p = g.players[0]
	p.ingredients = [_card("Lightning Bolt", 1), _card("Gold", 2)]
	eq(g.pool_size(0, FoGame.STRENGTH).normal, 3, "+3d6")
	eq(g.reservable(0).map(func(c): return c.name), ["Gold"], "only Gold")
	p.ingredients = [_card("Lightning Bolt", 1)]
	eq(g.reservable(0), [], "nothing to reserve")


func test_kraken_blood_takes_a_penalty() -> void:
	var g := _new_game(2, 38)
	var p = g.players[0]
	p.ingredients = [_card("Kraken Blood", 1)]
	g.strength_card = {"name": "Phantasm", "type": "Demon"}
	_reacting(g, FoGame.STRENGTH, [FoGame.Die.new(4), FoGame.Die.new(5), FoGame.Die.new(1)])
	eq(g.evaluate(0, FoGame.STRENGTH).dice_loss, 2, "one rolled 1 + one automatic")
	ok(g.finish_reactions(), "finish")
	eq(p.penalty.dice_loss, 2, "penalty stored")


func test_celestial_ore_ignores_threes_and_fours() -> void:
	var g := _new_game(2, 39)
	var p = g.players[0]
	p.ingredients = [_card("Celestial Ore", 1)]
	g.sharpness_card = {"name": "Animated Flytrap", "type": "Giant"}
	eq(g.pool_size(0, FoGame.SHARPNESS), {"normal": 0, "magic": 2}, "2 magic dice")
	_reacting(g, FoGame.SHARPNESS, [FoGame.Die.new(4), FoGame.Die.new(5), FoGame.Die.new(3), FoGame.Die.new(6, true)])
	eq(g.evaluate(0, FoGame.SHARPNESS).successes, 2, "the 4 doesn't count")
	eq(g.die_marks(0, FoGame.SHARPNESS), [0, 1, 0, 1] as Array[int], "ignored dice unmarked")
	var steps := g.die_breakdown(0, p.dice[0], FoGame.SHARPNESS)
	ok(steps[-1].text.contains("Celestial Ore"), "explained")
	g.strength_card = {"name": "Kraken", "type": "Giant"}
	_reacting(g, FoGame.STRENGTH, [FoGame.Die.new(4)])
	eq(g.values(0, FoGame.STRENGTH), [4] as Array[int], "Strength unaffected")


func test_stygian_oil_and_shadow_essence_combo() -> void:
	var g := _new_game(2, 40)
	var p = g.players[0]
	g.strength_card = {"name": "Kraken", "type": "Giant"}
	p.ingredients = [_card("Stygian Oil", 1)]
	eq(g.pool_size(0, FoGame.STRENGTH).normal, 1, "oil alone: 1d6")
	p.ingredients = [_card("Shadow Essence", 2)]
	_reacting(g, FoGame.STRENGTH, [FoGame.Die.new(1)])
	eq(g.available_reactions(0), [], "essence alone: no reroll")
	p.ingredients = [_card("Stygian Oil", 1), _card("Shadow Essence", 2)]
	eq(g.pool_size(0, FoGame.STRENGTH).normal, 3 + 1, "oil 3d6 + essence 1d6")
	eq(g.available_reactions(0).size(), 1, "essence reroll with oil")


func test_fiery_salamander_gives_a_six() -> void:
	var g := _new_game(2, 41)
	var p = g.players[0]
	p.ingredients = [_card("Lotus Bloom", 1)]
	g.strength_card = {"name": "Fiery Salamander", "type": "Elemental"}
	g.sharpness_card = {"name": "Razor Mantis", "type": "Demon"}
	_reacting(g, FoGame.STRENGTH, [FoGame.Die.new(2), FoGame.Die.new(3), FoGame.Die.new(4)])
	ok(g.finish_reactions(), "finish Strength")
	eq(p.penalty.get("free_six", 0), 1, "boon earned")
	eq(g.pool_size(0, FoGame.SHARPNESS).normal, 3, "2d6 + the free die")
	g.challenge_kind = FoGame.SHARPNESS
	g._roll(0)
	eq(p.dice[0].raw, 6, "free die shows 6")
	ok(g.die_breakdown(0, p.dice[0], FoGame.SHARPNESS)[0].text.contains("Fiery Salamander"), "explained")



## The draft-order strip: current first, snake order, and no more turns than AP allows.
func test_craft_queue_follows_snake_and_ap() -> void:
	for s in 20:
		var g := _new_game(3, 500 + s)
		var steps := 0
		while g.phase != FoGame.Phase.GAME_OVER and steps < 5000:
			if g.phase == FoGame.Phase.CRAFT:
				var q := g.craft_queue(100)
				eq(q[0].player, g.current, "seed %d: current player first" % s)
				var ap_left := 0
				for p in g.players:
					ap_left += 0 if p.passed else p.ap
				eq(q.size(), ap_left, "seed %d: one queued turn per AP left" % s)
				if q.size() > 1 and q[1].player != g.current and q[1].round == q[0].round:
					var pos0: int = g.order.find(q[0].player)
					var pos1: int = g.order.find(q[1].player)
					ok(pos1 > pos0 if q[0].round % 2 == 0 else pos1 < pos0, "seed %d: snake direction" % s)
				# the queue's next player is who actually moves next, unless someone passes
				var next: int = q[1].player if q.size() > 1 else -1
				var move_before := g.moves.size()
				FoBot.step(g)
				if next >= 0 and g.phase == FoGame.Phase.CRAFT and g.moves[move_before][0] != "pass" \
						and g.players.all(func(p): return not p.passed):
					eq(g.current, next, "seed %d: queue predicts the next turn" % s)
			else:
				if g.phase == FoGame.Phase.SWAP:
					eq(g.craft_queue(5)[0].player, g.current, "seed %d: swapping player first" % s)
				else:
					eq(g.craft_queue(5), [], "empty outside crafting")
				FoBot.step(g)
			steps += 1


func test_reaction_kind() -> void:
	var g := _new_game(2, 7)
	var c := _card("Hardened Steel", 1)
	g.players[0].ingredients.append(c)
	var rs: Array = g.def_of(c).get("reactions", [])
	if not rs.is_empty():
		eq(g.reaction_kind("%d:0" % c.id), rs[0].kind)
	eq(g.reaction_kind("nonsense"), "")
