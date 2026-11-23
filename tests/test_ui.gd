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


## The main menu builds (with and without a save) and New game leads to the seat setup.
func test_title_screen() -> void:
	var ui: Control = load("res://scripts/main.gd").new()
	ui.data = CardData.load_default()
	ui._show_title()
	ok(ui.on_title and ui.get_child_count() > 0, "title shown")
	ui._apply_text_size()
	ok(ui.on_title, "text size change keeps the title")
	var g := FoGame.new(ui.data)
	g.setup(["Ann", "Cpu"], [false, true], 3)
	ui.resume = [g, 0, []]
	ui._show_setup()
	ok(not ui.on_title and ui.seat_rows.size() == 4, "seat setup shown")
	ui._show_title()
	ui.free()


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


## The phone layout (portrait, 640 px design width): every screen and overlay a game shows
## fits across without sideways scrolling, and the Table tab comes back for a human's turn.
func test_phone_layout_fits() -> void:
	var limit: float = 640 - 32  # PHONE_SIZE.x less the board margins
	for s in 6:
		var ui: Control = load("res://scripts/main.gd").new()
		ui.phone = true
		ui.theme = FoUI.make_theme()
		ui.data = CardData.load_default()
		ui._show_title()
		_fits(ui, ui.get_child(ui.get_child_count() - 2), limit, "title")
		ui._show_setup()
		ui._set_player_count(2 + s % 3)
		var hotseat := s % 2 == 0
		for i in ui.seat_rows.size():
			ui.seat_rows[i][2].button_pressed = not hotseat and i > 0
		_fits(ui, ui.get_child(1).get_child(0).get_child(0), limit, "setup")
		for page in ["settings", "rules"]:
			ui._open_menu(page)
			_fits(ui, ui.overlay.get_child(1).get_child(0), limit, "title " + page)
			ui._close_menu()
		ui._start_game()
		var g: FoGame = ui.game
		ok(ui.phone_pages.size() == 2 and ui.top_bar != null, "seed %d: phone board built" % s)
		var steps := 0
		while g.phase != FoGame.Phase.GAME_OVER and steps < 5000:
			if not ui.results_queue.is_empty():
				_fits(ui, ui.overlay.get_child(1).get_child(0), limit, "%s results" % ui.results_queue[0].type)
				ui._dismiss_results()
				ui._refresh()
			if ui.handoff >= 0:
				_fits(ui, ui.overlay.get_child(1).get_child(0), limit, "hand-off")
				ui._dismiss_handoff()
				ui._refresh()
			if not g.player().is_bot:
				eq(ui.phone_tab, "table", "seed %d: a human's turn shows the Table" % s)
				ui._show_tab("players")  # look at the mats; the next decision brings the Table back
				_fits(ui, ui.board_margin.get_child(0), limit, "Blacksmiths tab")
				ui._show_tab("table")
			if g.phase == FoGame.Phase.REACT and not g.player().dice.is_empty():
				ui.selected_die = 0
				ui._refresh()
			_fits(ui, ui.board_margin.get_child(0), limit, "board, phase %d" % g.phase)
			if steps == 3:
				ui._open_zoom(g.strength_card, true)
				_fits(ui, ui.overlay.get_child(1).get_child(0), limit, "challenge zoom")
				for page in ["pause", "settings", "rules", "restart"]:
					ui._open_menu(page)
					_fits(ui, ui.overlay.get_child(1).get_child(0), limit, page)
				ui.menu = ""
				ui._close_zoom()
			FoBot.step(g)
			ui._refresh()
			steps += 1
		ok(g.phase == FoGame.Phase.GAME_OVER, "seed %d finished on a phone" % s)
		_fits(ui, ui.board_margin.get_child(0), limit, "game over")
		ui.phone = false  # rotating to landscape rebuilds the desktop board mid-game
		ui._rebuild_screen()
		ok(ui.phone_pages.is_empty() and ui.top_bar == null, "seed %d: desktop board after rotating" % s)
		ui.free()


func _fits(_ui: Control, c: Control, limit: float, what: String) -> void:
	var w := c.get_combined_minimum_size().x
	ok(w <= limit, "%s is %d px wide on a phone (max %d)" % [what, w, limit])
