extends "res://tests/test_case.gd"
## Renders every human-facing screen (seats marked human, but the bot picks the moves),
## so UI code paths for each phase run without script errors.


func test_render_every_phase() -> void:
	var seen := {}
	for s in 25:
		var ui: Control = load("res://scripts/main.gd").new()
		ui.data = CardData.load_default()
		ui._show_setup()
		ui.count_spin.value = 2 + s % 3
		for row in ui.seat_rows:
			row[2].button_pressed = false
		ui._start_game()
		var g: FoGame = ui.game
		var steps := 0
		while g.phase != FoGame.Phase.GAME_OVER and steps < 5000:
			seen[g.phase] = true
			ok(ui.action_box.get_child_count() > 0, "phase %d rendered nothing" % g.phase)
			FoBot.step(g)
			ui._refresh()
			steps += 1
		ok(g.phase == FoGame.Phase.GAME_OVER, "seed %d finished" % s)
		ui.free()
	for ph in [FoGame.Phase.CRAFT, FoGame.Phase.SWAP, FoGame.Phase.WAGER, FoGame.Phase.REACT, FoGame.Phase.RESERVE]:
		ok(seen.has(ph), "phase %d never rendered" % ph)
