extends "res://tests/test_case.gd"
## Renders every human-facing screen (seats marked human, but the bot picks the moves),
## so UI code paths for each phase run without script errors. Odd seeds seat one human
## and CPUs (no hand-off screens); even seeds are all-human hotseat.


func test_render_every_phase() -> void:
	var seen := {}
	for s in 25:
		var ui: Control = load("res://scripts/main.gd").new()
		ui.data = CardData.load_default()
		ui._show_setup()
		ui._set_player_count(2 + s % 3)
		var hotseat := s % 2 == 0
		for i in ui.seat_rows.size():
			ui.seat_rows[i][2].button_pressed = not hotseat and i > 0
		ui._start_game()
		var g: FoGame = ui.game
		var steps := 0
		var shown := {}
		var handoffs := 0
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
				ui._refresh()
			if ui.handoff >= 0:
				eq(ui.handoff, g.current, "hand-off to whoever decides next")
				ok(not g.player().is_bot and ui.overlay.visible, "hand-off shown for a human")
				handoffs += 1
				ui._dismiss_handoff()
				ui._refresh()
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
		eq([ui.flights, ui.tumble_left], [0, 0.0], "seed %d: no animation runs outside the tree" % s)
		eq(ui.history_seen, 9, "seed %d: every Challenge and Quest reached the UI" % s)
		ok(shown.has("challenge") and shown.has("quest"), "seed %d: both results screens rendered" % s)
		if hotseat:
			ok(handoffs > 3, "seed %d: hotseat hands off (%d)" % [s, handoffs])
		else:
			eq(handoffs, 0, "seed %d: no hand-off with one human" % s)
		ui.free()
	for ph in [FoGame.Phase.CRAFT, FoGame.Phase.SWAP, FoGame.Phase.WAGER, FoGame.Phase.REACT, FoGame.Phase.RESERVE]:
		ok(seen.has(ph), "phase %d never rendered" % ph)


func test_menu_pages() -> void:
	var ui: Control = load("res://scripts/main.gd").new()
	ui.data = CardData.load_default()
	ui._show_setup()
	for page in ["settings", "rules"]:  # from the title screen
		ui._open_menu(page)
		ok(ui.overlay.visible and ui.overlay.get_child_count() > 0, "title %s shown" % page)
		ui._close_menu()
		ok(not ui.overlay.visible, "title %s closed" % page)
	ui._start_game()
	ui._dismiss_handoff()
	ui._refresh()
	ok(not ui._blocking(), "game starts unblocked")
	ui._open_menu("pause")
	ok(ui._busy() and ui.overlay.visible, "pause blocks CPU turns")
	for page in ["settings", "rules"]:
		ui._open_menu(page)
		ok(ui.overlay.visible, "%s shown" % page)
		ui._close_menu()
		eq(ui.menu, "pause", "%s returns to the pause menu" % page)
	ui._open_menu("restart")
	ui._open_menu("pause")
	ui._close_menu()
	ok(not ui._blocking(), "resumed")
	ui.free()


## Continue: a game rebuilt from a save shows its board without replaying old results.
func test_enter_saved_game() -> void:
	var data := CardData.load_default()
	var g := FoGame.new(data)
	g.setup(["Ann", "Bea", "Cpu"], [false, false, true], 99)
	for i in 30:
		FoBot.step(g)
	var r := FoGame.replay(data, ["Ann", "Bea", "Cpu"], [false, false, true], 99, g.moves)
	var ui: Control = load("res://scripts/main.gd").new()
	ui.data = data
	ui._show_setup()
	ui._enter_game(r, r.history.size())
	ok(ui.results_queue.is_empty(), "seen results stay dismissed")
	if not r.player().is_bot:
		eq(ui.handoff, r.current, "resuming a hotseat game asks for the right player")
	ui.free()
