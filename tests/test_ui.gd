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
		var shown := {}
		while g.phase != FoGame.Phase.GAME_OVER and steps < 5000:
			seen[g.phase] = true
			ok(ui.action_box.get_child_count() > 0, "phase %d rendered nothing" % g.phase)
			if g.phase == FoGame.Phase.REACT and not g.player().dice.is_empty():
				ui.selected_die = 0  # the die-breakdown label
				ui._refresh()
			if not ui.results_queue.is_empty():
				ok(ui.overlay.visible and ui.overlay.get_child_count() > 0, "results overlay shown")
				shown[ui.results_queue[0].type] = true
				ui._dismiss_results()
			if steps == 3:
				if not g.market.is_empty():
					ui._open_zoom(g.market[0], false)
				ok(ui._blocking() and ui.overlay.visible, "ingredient zoom shown")
				ui._open_zoom(g.strength_card, true)
				ui._close_zoom()
				ok(not ui.overlay.visible, "zoom closed")
			FoBot.step(g)
			ui._refresh()
			steps += 1
		ok(g.phase == FoGame.Phase.GAME_OVER, "seed %d finished" % s)
		eq(ui.history_seen, 9, "seed %d: every Challenge and Quest reached the UI" % s)
		ok(shown.has("challenge") and shown.has("quest"), "seed %d: both results screens rendered" % s)
		ui.free()
	for ph in [FoGame.Phase.CRAFT, FoGame.Phase.SWAP, FoGame.Phase.WAGER, FoGame.Phase.REACT, FoGame.Phase.RESERVE]:
		ok(seen.has(ph), "phase %d never rendered" % ph)
