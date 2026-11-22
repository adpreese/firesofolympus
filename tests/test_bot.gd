extends "res://tests/test_case.gd"
## CPU levels and personalities. Games are seeded, so these results are fixed, not flaky.

var data := CardData.load_default()


## Seat 0 plays `a`, seat 1 plays `b`; returns [a's score (win 1, tie 0.5), games].
func _match(a: Dictionary, b: Dictionary, seeds: int, first_seed: int) -> Array:
	var score := 0.0
	for s in seeds:
		for swap in 2:
			var seats := [a, b] if swap == 0 else [b, a]
			var g := FoGame.new(data)
			g.setup(["x", "y"], [true, true], first_seed + s)
			while g.phase != FoGame.Phase.GAME_OVER:
				var c: Dictionary = seats[g.current]
				FoBot.step(g, c.get("level", FoBot.Level.NORMAL), c.get("persona", ""))
			var me := swap
			var d: int = g.players[me].total - g.players[1 - me].total
			score += 1.0 if d > 0 else (0.5 if d == 0 else 0.0)
	return [score, seeds * 2]


func test_normal_beats_easy() -> void:
	var r := _match({"level": FoBot.Level.NORMAL}, {"level": FoBot.Level.EASY}, 100, 3000)
	ok(r[0] > r[1] * 0.55, "Normal scored %.1f of %d against Easy" % r)


func test_hard_beats_normal() -> void:
	var r := _match({"level": FoBot.Level.HARD}, {"level": FoBot.Level.NORMAL}, 8, 4000)
	ok(r[0] > r[1] * 0.7, "Hard scored %.1f of %d against Normal" % r)


## Thinking runs on copies: it never moves the real game or its dice.
func test_hard_plan_leaves_game_alone() -> void:
	var g := FoGame.new(data)
	g.setup(["a", "b", "c"], [true, true, true], 5)
	var state := g.rng.state
	var log_size := g.log_lines.size()
	var p := FoBot.plan(g, FoBot.Level.HARD)
	ok(not p.advance(0.0), "Hard needs more than one slice of thinking")
	ok(p.advance(INF), "and finishes")
	eq([g.rng.state, g.moves.size(), g.log_lines.size()], [state, 0, log_size], "game untouched")
	ok(g.play_move(p.move), "the chosen move is legal")


func test_personalities_play_differently() -> void:
	var counts := {}
	for key in ["sharpener", "hoarder", "gambler", "steady"]:
		var c := {"sharpen": 0, "wager": 0, "draft": 0}
		for s in 30:
			var g := FoGame.new(data)
			g.setup(["p", "q", "r"], [true, true, true], 6000 + s)
			while g.phase != FoGame.Phase.GAME_OVER:
				var mine := g.current == 0
				var before := g.moves.size()
				FoBot.step(g, FoBot.Level.NORMAL, key if mine else "")
				if mine and g.moves.size() > before:
					var m: Array = g.moves[-1]
					if m[0] in c and (m[0] != "wager" or m[1]):
						c[m[0]] += 1
		counts[key] = c
	ok(counts.sharpener.sharpen > counts.steady.sharpen, "Brontes sharpens more: %s" % str(counts))
	ok(counts.hoarder.sharpen < counts.steady.sharpen, "Melaina sharpens less: %s" % str(counts))
	ok(counts.hoarder.draft > counts.steady.draft, "Melaina drafts more: %s" % str(counts))
	ok(counts.gambler.wager >= counts.steady.wager, "Tycho wagers at least as often: %s" % str(counts))


func test_every_persona_and_level_finishes() -> void:
	for li in FoBot.LEVELS.size():
		for pd in FoBot.PERSONAS:
			var g := FoGame.new(data)
			g.setup(["a", "b"], [true, true], 77)
			var steps := 0
			while g.phase != FoGame.Phase.GAME_OVER and steps < 3000:
				FoBot.step(g, li if g.current == 0 else FoBot.Level.NORMAL, pd.key)
				steps += 1
			ok(g.phase == FoGame.Phase.GAME_OVER, "%s at %s finished" % [pd.key, FoBot.LEVELS[li]])
