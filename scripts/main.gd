extends Control
## Pass-and-play UI. All rules live in FoGame; this only draws state and forwards clicks.
## CPU seats are driven by FoBot, one decision every FoSettings.cpu_delay() seconds.
## The look (theme, card tiles, dice) lives in FoUI; art, fonts and sounds come from FoAssets.
## Sounds and animations are triggered by diffing game state between redraws, so CPU moves
## look and sound the same as human ones. CPU turns wait while anything is animating or
## an overlay (results screen, zoomed card) is open.
## Smoke test: `godot -- --autoplay` plays an all-CPU game at full speed and quits.

const MAX_PLAYERS := 4
const DEFAULT_NAMES := ["Andrea", "Bob", "Carlos", "Dhivya"]
const SFX_VOICES := 8
const MUSIC_DB := -14.0
const TUMBLE_TIME := 0.6   # dice show random faces this long after a roll
const TUMBLE_TICK := 0.06
const FLIGHT_TIME := 0.35  # a card moving between the table and a mat
const FADE_TIME := 0.22    # overlays fading in

var data: CardData
var game: FoGame
var selected_reaction := ""
var bot_wait := 0.0
var autoplay := "--autoplay" in OS.get_cmdline_user_args()

var seat_rows: Array = []  # [row, LineEdit, CheckBox]
var count_spin: SpinBox
var players_box: VBoxContainer
var header: VBoxContainer
var action_box: VBoxContainer
var log_view: RichTextLabel
var audio_root: Node  # survives _clear(self) so music keeps playing across screens
var music: AudioStreamPlayer
var sfx: Array[AudioStreamPlayer] = []
var sfx_next := 0
var last_snap := {}
var quitting := false

var overlay: Control           # results screens and card zoom, drawn over the board
var fx_layer: Control          # flying cards, above the board and below the overlay
var results_queue: Array = []  # FoGame.history entries the players haven't dismissed yet
var history_seen := 0
var zoom := {}                 # {card, challenge} while a card is zoomed
var selected_die := -1         # die whose breakdown is shown during a Challenge
var die_context := ""          # resets selected_die when the roller or Challenge changes
var results_detail: Label

var overlay_key := ""          # what the overlay showed last, so new content fades in
var dice_nodes: Array = []     # die buttons of the current roll, for the tumble
var tumble_left := 0.0
var tumble_tick := 0.0
var card_nodes := {}           # card id -> [zone, Control, card name] from the latest render
var flights := 0               # cards in the air

var persist := false           # autosave to FoSave (off for tests and --autoplay)
var saved := []                # [moves, seen] last written, to skip identical saves
var resume := []               # [FoGame, seen] from the save file, for the title screen
var menu := ""                 # open menu page: pause, settings, rules, restart ("" = none)
var menu_back := ""            # page that settings / rules return to
var handoff := -1              # human seat the device should be passed to, -1 = none
var last_human := -1           # human seat that last had a decision


func _ready() -> void:
	FoSettings.load_file()
	persist = not autoplay
	theme = FoUI.make_theme()
	_setup_audio()
	data = CardData.load_default()
	_show_setup()
	if autoplay:
		for row in seat_rows:
			row[2].button_pressed = true
	if autoplay or "--start" in OS.get_cmdline_user_args():
		_start_game()


func _exit_tree() -> void:
	_stop_audio()


func _stop_audio() -> void:
	for p in sfx + ([music] if music != null else []):
		p.stop()
		p.stream = null
	FoAssets.clear_cache()


func _process(delta: float) -> void:
	if autoplay and game != null and game.phase == FoGame.Phase.GAME_OVER:
		if not quitting:
			quitting = true
			print(game.log_lines[-1])
			_stop_audio()
			# the AudioServer frees stopped playbacks on its next mix, so give it a moment
			await get_tree().create_timer(0.2).timeout
			get_tree().quit()
		return
	if tumble_left > 0 and not _blocking():
		_tumble(delta)
	if game == null or game.phase == FoGame.Phase.GAME_OVER or not game.player().is_bot or _busy():
		return
	bot_wait -= delta
	if bot_wait > 0:
		return
	bot_wait = 0.0 if autoplay else FoSettings.cpu_delay()
	FoBot.step(game)
	_refresh()


# ------------------------------------------------------------------ setup screen

func _show_setup() -> void:
	game = null
	action_box = null
	overlay = null
	menu = ""
	zoom = {}
	resume = FoSave.read(data) if persist else []
	_clear(self)
	add_child(FoUI.background())
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var pnl := FoUI.panel(FoUI.box(FoUI.PANEL, FoUI.GOLD, 2, 16, 40))
	center.add_child(pnl)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	pnl.add_child(box)
	var title := FoUI.heading("Fires of Olympus", 72, FoUI.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := FoUI.label("Forge a blade from rare Ingredients, then face the monsters of three Quests.", 22, FoUI.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.custom_minimum_size.x = 720
	box.add_child(sub)
	if not resume.is_empty():
		var g: FoGame = resume[0]
		var cont := _title_button("Continue", func(): _enter_game(resume[0], resume[1]))
		cont.add_theme_stylebox_override("normal", FoUI.box(FoUI.PANEL_LIGHT, FoUI.GOLD, 2, 8, 10))
		cont.add_theme_color_override("font_color", FoUI.GOLD)
		box.add_child(cont)
		var who: Array = g.players.map(func(p): return p.name)
		var where := FoUI.label("Quest %d of 3 with %s" % [g.quest + 1, ", ".join(who)], 18, FoUI.MUTED)
		where.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(where)
		var or_new := FoUI.heading("Or a new game", 22, FoUI.MUTED)
		or_new.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(or_new)
	if not data.errors.is_empty():
		box.add_child(FoUI.label("Card data problems:\n" + "\n".join(data.errors), 18, FoUI.RED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.add_child(FoUI.heading("Blacksmiths", 24, FoUI.INK, false))
	count_spin = SpinBox.new()
	count_spin.min_value = 2
	count_spin.max_value = MAX_PLAYERS
	count_spin.value = 3
	count_spin.value_changed.connect(func(_v): _update_seats())
	row.add_child(count_spin)
	box.add_child(row)
	seat_rows.clear()
	for i in MAX_PLAYERS:
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 16)
		var name_edit := LineEdit.new()
		name_edit.text = DEFAULT_NAMES[i]
		name_edit.custom_minimum_size.x = 360
		var cpu := CheckBox.new()
		cpu.text = "CPU"
		cpu.button_pressed = i > 0
		r.add_child(name_edit)
		r.add_child(cpu)
		box.add_child(r)
		seat_rows.append([r, name_edit, cpu])
	var options := HBoxContainer.new()
	options.add_theme_constant_override("separation", 12)
	options.add_child(_button("Settings", func(): _open_menu("settings")))
	options.add_child(_button("How to play", func(): _open_menu("rules")))
	box.add_child(options)
	box.add_child(_title_button("Begin the Quests", _start_game))
	if not resume.is_empty():
		var note := FoUI.label("Beginning a new game replaces the saved one.", 18, FoUI.MUTED)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(note)
	_update_seats()
	_add_overlay()


func _title_button(text: String, f: Callable) -> Button:
	var b := _button(text, f)
	b.custom_minimum_size.y = 64
	b.add_theme_font_override("font", FoAssets.font(FoUI.HEADING_FONT))
	b.add_theme_font_size_override("font_size", FoUI.fs(28))
	return b


func _update_seats() -> void:
	for i in seat_rows.size():
		seat_rows[i][0].visible = i < int(count_spin.value)


func _start_game() -> void:
	var names := []
	var bots := []
	for i in int(count_spin.value):
		var n: String = seat_rows[i][1].text.strip_edges()
		names.append(n if n != "" else "Player %d" % (i + 1))
		bots.append(seat_rows[i][2].button_pressed)
	_new_game(names, bots)


func _new_game(names: Array, bots: Array) -> void:
	var g := FoGame.new(data)
	g.setup(names, bots, randi())
	_enter_game(g, 0)
	_play("start")


## Show `g` on the board. `seen`: history entries already dismissed (from a save).
func _enter_game(g: FoGame, seen: int) -> void:
	game = g
	resume = []
	last_snap = {}
	results_queue.clear()
	history_seen = seen
	saved = []
	menu = ""
	handoff = -1
	last_human = -1
	zoom = {}
	selected_die = -1
	tumble_left = 0.0
	card_nodes = {}
	flights = 0
	overlay_key = ""
	_build_board()


# ------------------------------------------------------------------ board

func _build_board() -> void:
	_clear(self)
	add_child(FoUI.background())
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 18)
	margin.add_child(root)

	var left := ScrollContainer.new()
	left.custom_minimum_size.x = 480
	left.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	players_box = VBoxContainer.new()
	players_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	players_box.add_theme_constant_override("separation", 12)
	left.add_child(players_box)
	root.add_child(left)

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 12)
	header = VBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	mid.add_child(header)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	action_box = VBoxContainer.new()
	action_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_box.add_theme_constant_override("separation", 12)
	scroll.add_child(action_box)
	mid.add_child(scroll)
	root.add_child(mid)

	var log_panel := FoUI.panel(FoUI.box(Color(FoUI.PANEL, 0.7), FoUI.EDGE, 1, 12, 12))
	log_panel.custom_minimum_size.x = 340
	var log_box := VBoxContainer.new()
	log_panel.add_child(log_box)
	log_box.add_child(FoUI.heading("Chronicle", 20, FoUI.GOLD))
	log_view = RichTextLabel.new()
	log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_view.scroll_following = true
	log_view.add_theme_font_size_override("normal_font_size", FoUI.fs(15))
	log_view.add_theme_color_override("default_color", FoUI.MUTED)
	log_box.add_child(log_view)
	root.add_child(log_panel)

	fx_layer = Control.new()
	fx_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fx_layer)
	_add_overlay()
	_refresh()


func _add_overlay() -> void:
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	_render_overlay()


func _refresh() -> void:
	if game == null or action_box == null:
		return
	var old_cards := _card_rects()
	_play_events()
	_sync_history()
	_autosave()
	_check_handoff()
	card_nodes = {}
	_render_players()
	_render_header()
	_render_actions()
	log_view.text = "\n".join(game.log_lines)
	_render_overlay()
	_queue_flights(old_cards)


func _render_header() -> void:
	_clear(header)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	var title := FoUI.heading("Quest %d of 3" % mini(game.quest + 1, 3), 34, FoUI.GOLD, false)
	top.add_child(title)
	var phase_name := _phase_name()
	if phase_name != "":
		var c := FoUI.chip(phase_name, FoUI.INK, 18)
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(c)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(gap)
	var menu_button := Button.new()
	menu_button.text = "Menu"
	menu_button.custom_minimum_size = Vector2(120, 48)
	menu_button.pressed.connect(func():
		_play("click")
		_open_menu("pause"))
	top.add_child(menu_button)
	header.add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	for kind in [FoGame.STRENGTH, FoGame.SHARPNESS]:
		var active: bool = game.phase == FoGame.Phase.REACT and game.challenge_kind == kind
		row.add_child(_challenge_panel(game.challenge_card(kind), active))
	header.add_child(row)


func _phase_name() -> String:
	match game.phase:
		FoGame.Phase.CRAFT, FoGame.Phase.SWAP:
			return "Crafting"
		FoGame.Phase.WAGER, FoGame.Phase.REACT:
			return "%s Challenge" % game.challenge_kind
		FoGame.Phase.RESERVE:
			return "Reserving"
	return ""


func _challenge_panel(card: Dictionary, active: bool) -> Control:
	var accent := FoUI.RED if card.kind == FoGame.STRENGTH else FoUI.MAGIC
	var style := FoUI.box(FoUI.PANEL_LIGHT if active else FoUI.PANEL, FoUI.GOLD if active else FoUI.EDGE, 3 if active else 1, 12, 12)
	var pnl := FoUI.panel(style)
	pnl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	pnl.add_child(row)
	var tex := FoAssets.challenge_art(card)
	if tex != null:
		row.add_child(FoUI.picture(tex, 120, true))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 4)
	text.add_child(FoUI.label("%s Challenge  ·  %s" % [card.kind, card.type], 16, accent))
	text.add_child(FoUI.heading(card.name, 26, FoUI.GOLD if active else FoUI.INK))
	text.add_child(FoUI.label(card.rule, 18))
	row.add_child(text)
	_zoomable(pnl, card, true)
	return pnl


# ------------------------------------------------------------------ player mats

func _render_players() -> void:
	_clear(players_box)
	for pi in game.players.size():
		players_box.add_child(_player_mat(pi))


func _player_mat(pi: int) -> Control:
	var p = game.players[pi]
	var active: bool = pi == game.current and game.phase != FoGame.Phase.GAME_OVER
	var mat := FoUI.panel(FoUI.box(FoUI.PANEL_LIGHT if active else FoUI.PANEL,
		FoUI.GOLD if active else FoUI.EDGE, 3 if active else 1, 12, 12))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	mat.add_child(v)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	var name_label := FoUI.heading(p.name, 24, FoUI.GOLD if active else FoUI.INK, false)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	top.add_child(name_label)
	if p.is_bot:
		top.add_child(FoUI.chip("CPU", FoUI.MUTED, 14))
	top.add_child(FoUI.heading(FoGame.successes_text(p.total), 20, FoUI.GOLD, false))
	v.add_child(top)

	var stats := HFlowContainer.new()
	stats.add_theme_constant_override("h_separation", 8)
	stats.add_theme_constant_override("v_separation", 6)
	stats.add_child(FoUI.chip("AP %d" % p.ap, FoUI.INK if p.ap > 0 else FoUI.MUTED))
	var sharpen := HBoxContainer.new()
	sharpen.add_theme_constant_override("separation", 6)
	sharpen.add_child(FoUI.label("Sharpened", 16, FoUI.MUTED, false))
	sharpen.add_child(FoUI.pips(p.sharpen, FoGame.SHARPEN_DICE.size()))
	stats.add_child(sharpen)
	var a: Dictionary = game.pool_size(pi, FoGame.STRENGTH)
	var b: Dictionary = game.pool_size(pi, FoGame.SHARPNESS)
	stats.add_child(FoUI.chip("Strength %dd6" % (a.normal + a.magic), FoUI.RED.lightened(0.3)))
	stats.add_child(FoUI.chip("Sharpness %dd6" % (b.normal + b.magic), FoUI.MAGIC))
	if not p.quest_scores.is_empty():
		stats.add_child(FoUI.chip("Quests " + " · ".join(p.quest_scores.map(func(s): return str(s))), FoUI.MUTED))
	if p.passed and game.phase == FoGame.Phase.CRAFT:
		stats.add_child(FoUI.chip("Passed", FoUI.MUTED))
	v.add_child(stats)
	if not p.penalty.is_empty() and Scoring.penalty_cost(p.penalty) > 0:
		v.add_child(FoUI.label("Penalty: " + Scoring.describe_penalty(p.penalty), 17, FoUI.RED))

	var cards := HFlowContainer.new()
	cards.add_theme_constant_override("h_separation", 6)
	cards.add_theme_constant_override("v_separation", 6)
	for c in p.ingredients:
		cards.add_child(_mini_card(c, "p%d" % pi, game.in_reserve(pi, c.id)))
	if p.ingredients.is_empty():
		cards.add_child(FoUI.label("No Ingredients yet", 16, FoUI.MUTED, false))
	v.add_child(cards)
	var idle_reserve: Array = game.reserve_options(pi)
	if not idle_reserve.is_empty():
		v.add_child(FoUI.label("Reserve", 15, FoUI.RESERVE))
		var rrow := HFlowContainer.new()
		rrow.add_theme_constant_override("h_separation", 6)
		for c in idle_reserve:
			var m := _mini_card(c, "r%d" % pi, true)
			m.self_modulate = Color(1, 1, 1, 0.8)
			rrow.add_child(m)
		v.add_child(rrow)
	return mat


func _mini_card(c: Dictionary, zone: String, reserved: bool) -> Control:
	var t := FoUI.card_tile(c.name, "", FoAssets.ingredient_art(data.ingredient(c.name)), FoUI.MINI,
		FoUI.RESERVE if reserved else FoUI.EDGE)
	t.pressed.connect(func():
		_play("click")
		_open_zoom(c, false))
	_register_card(c, zone, t)
	return t


# ------------------------------------------------------------------ actions

func _render_actions() -> void:
	_clear(action_box)
	dice_nodes = []
	if game.phase == FoGame.Phase.GAME_OVER:
		_render_game_over()
		return
	var p := game.player()
	if game.phase == FoGame.Phase.CRAFT:
		_render_craft()
		return
	if p.is_bot:
		action_box.add_child(_prompt("%s is thinking..." % p.name))
		if game.phase == FoGame.Phase.REACT:
			_render_dice(false)
		return
	match game.phase:
		FoGame.Phase.SWAP:
			action_box.add_child(_prompt("%s: Rusty Bauble. Choose an opponent's Ingredient to swap it for." % p.name))
			var flow := _tile_flow()
			for t in game.swap_targets(game.current):
				var who: String = game.players[t.player].name
				flow.add_child(_card_tile(t.card, func(): game.act_swap(t.player, t.card.id), "%s's" % who))
		FoGame.Phase.WAGER:
			action_box.add_child(_prompt("%s: Gambler's Charm. Wager a Success?" % p.name))
			action_box.add_child(FoUI.label("If you score the most Sharpness Successes this Quest (no ties) you gain 1, otherwise you lose 1.", 20, FoUI.MUTED))
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 12)
			row.add_child(_big_button("Wager", func(): game.act_wager(true)))
			row.add_child(_big_button("No wager", func(): game.act_wager(false)))
			action_box.add_child(row)
		FoGame.Phase.REACT:
			_render_react()
		FoGame.Phase.RESERVE:
			action_box.add_child(_prompt("%s: reserve one Ingredient for future Quests" % p.name))
			action_box.add_child(FoUI.label("Only you can draft a reserved Ingredient, and it costs 1 AP as usual.", 20, FoUI.MUTED))
			var flow := _tile_flow()
			for c in game.reservable(game.current):
				flow.add_child(_card_tile(c, func(): game.act_reserve(c.id)))


func _render_craft() -> void:
	var p := game.player()
	if p.is_bot:
		action_box.add_child(_prompt("%s is choosing..." % p.name))
	else:
		action_box.add_child(_prompt("%s, your move: %d AP left. Every action costs 1 AP." % [p.name, p.ap]))
	action_box.add_child(FoUI.heading("On the table", 20, FoUI.MUTED))
	var flow := _tile_flow()
	for c in game.market:
		var t := _card_tile(c, func(): game.act_draft(c.id))
		t.disabled = p.is_bot
		_register_card(c, "m", t)
		flow.add_child(t)
	if game.market.is_empty():
		flow.add_child(FoUI.label("The table is empty.", 18, FoUI.MUTED, false))
	if p.is_bot:
		return
	var reserve := game.reserve_options(game.current)
	if not reserve.is_empty():
		action_box.add_child(FoUI.heading("Your reserve", 20, FoUI.RESERVE))
		var rflow := _tile_flow()
		for c in reserve:
			rflow.add_child(_card_tile(c, func(): game.act_draft(c.id), "", FoUI.RESERVE))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var sharpen_text := "Sharpen"
	if p.sharpen < FoGame.SHARPEN_DICE.size():
		sharpen_text += "  (+%dd6)" % (FoGame.SHARPEN_DICE[p.sharpen] + game.flag_sum(game.current, "electrum"))
	var sb := _big_button(sharpen_text, func(): game.act_sharpen())
	sb.disabled = not game.can_sharpen(game.current)
	row.add_child(sb)
	row.add_child(_big_button("Pass (done for this Quest)", func(): game.act_pass()))
	action_box.add_child(row)


func _render_react() -> void:
	var p := game.player()
	var card := game.challenge_card(game.challenge_kind)
	action_box.add_child(_prompt("%s faces %s" % [p.name, card.name]))
	_render_dice(true)
	if tumble_left > 0:
		return
	var vals := game.values(game.current, game.challenge_kind)
	var result := "Current result: " + game.describe_outcome(game.current)
	var note := Scoring.total_note(card.name, vals)
	if note != "":
		result += "   " + note
	if game.challenge_kind == FoGame.SHARPNESS:
		result += _parts_text(game.success_parts(game.current, vals))
	action_box.add_child(FoUI.heading(result, 22, FoUI.GOLD))
	var reactions := game.available_reactions(game.current)
	var still_valid := false
	if not reactions.is_empty():
		action_box.add_child(FoUI.label("Reactions: pick one, then tap a die", 18, FoUI.MUTED))
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 8)
		for r in reactions:
			var verb: String = {"reroll": "Reroll a die", "plus_one": "+1 to a die", "keep": "Keep a die for Sharpness"}[r.kind]
			var b := _button("%s: %s (%d left)" % [r.card, verb, r.left], func(): selected_reaction = r.key)
			b.toggle_mode = true
			b.button_pressed = r.key == selected_reaction
			if r.key == selected_reaction:
				still_valid = true
			row.add_child(b)
		action_box.add_child(row)
	if not still_valid:
		selected_reaction = ""
	action_box.add_child(_big_button("Done", func():
		selected_reaction = ""
		game.finish_reactions()))


## The rolling player's dice. Clicking one applies the selected Reaction, or with
## no Reaction selected shows how that die's value was worked out.
func _render_dice(clickable: bool) -> void:
	var p := game.player()
	var ctx := "%d:%d:%s" % [game.quest, game.current, game.challenge_kind]
	if ctx != die_context:
		die_context = ctx
		selected_die = -1
	var tumbling := tumble_left > 0
	var marks := game.die_marks(game.current, game.challenge_kind)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	row.add_theme_constant_override("v_separation", 10)
	for i in p.dice.size():
		var d = p.dice[i]
		var v := game.die_value(game.current, d, game.challenge_kind)
		var b := FoUI.die_face(v, 0 if tumbling else marks[i], d.magic, d.carried, 84, clickable and i == selected_die)
		if clickable and not tumbling:
			b.pressed.connect(func(): _act(func():
				if selected_reaction != "":
					game.apply_reaction(selected_reaction, i)
				else:
					selected_die = -1 if selected_die == i else i))
		else:
			b.disabled = true
		dice_nodes.append(b)
		row.add_child(b)
	action_box.add_child(row)
	if tumbling:
		return
	var legend := _marks_legend(marks, game.challenge_kind)
	if legend != "":
		action_box.add_child(FoUI.label(legend, 16, FoUI.MUTED))
	if clickable:
		if selected_die >= 0 and selected_die < p.dice.size():
			var steps := game.die_breakdown(game.current, p.dice[selected_die], game.challenge_kind)
			var pnl := FoUI.panel(FoUI.box(FoUI.PANEL, FoUI.EDGE, 1, 8, 10))
			pnl.add_child(FoUI.label(_breakdown_text(steps), 18))
			action_box.add_child(pnl)
		elif selected_reaction == "":
			action_box.add_child(FoUI.label("Tap a die to see how its value was worked out.", 16, FoUI.MUTED))


func _render_game_over() -> void:
	var ranked := range(game.players.size())
	ranked.sort_custom(func(a, b): return game.players[a].total > game.players[b].total)
	var names := PackedStringArray()
	for pi in game.winners():
		names.append(game.players[pi].name)
	action_box.add_child(FoUI.heading("%s win%s!" % [" & ".join(names), "" if names.size() > 1 else "s"], 48, FoUI.GOLD))
	for pi in ranked:
		var p = game.players[pi]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var winner: bool = pi in game.winners()
		var n := FoUI.heading(p.name, 30, FoUI.GOLD if winner else FoUI.INK, false)
		n.custom_minimum_size.x = 280
		row.add_child(n)
		row.add_child(FoUI.label(FoGame.successes_text(p.total), 28, FoUI.GOLD if winner else FoUI.INK, false))
		row.add_child(FoUI.chip("Quests " + " · ".join(p.quest_scores.map(func(s): return str(s))), FoUI.MUTED))
		action_box.add_child(row)
	action_box.add_child(_big_button("New game", _show_setup))


# ------------------------------------------------------------------ overlays

## Queue results screens for Challenges and Quests that finished since the last redraw.
## The --autoplay smoke test never shows them.
func _sync_history() -> void:
	while history_seen < game.history.size():
		if not autoplay:
			results_queue.append(game.history[history_seen])
		history_seen += 1


## True while a results screen, zoomed card, menu or hand-off screen is up.
func _blocking() -> bool:
	return not results_queue.is_empty() or not zoom.is_empty() or menu != "" or handoff >= 0


## True while CPU players should wait: an overlay is open or something is animating.
func _busy() -> bool:
	return _blocking() or tumble_left > 0 or flights > 0


func _open_zoom(card: Dictionary, challenge: bool) -> void:
	zoom = {"card": card, "challenge": challenge}
	_render_overlay()


func _close_zoom() -> void:
	zoom = {}
	_render_overlay()


func _render_overlay() -> void:
	if overlay == null:
		return
	_clear(overlay)
	results_detail = null
	overlay.visible = _blocking() and (game != null or menu != "")
	if not overlay.visible:
		overlay_key = ""
		return
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var key := ""
	if menu != "":
		if menu == "pause":
			dim.gui_input.connect(_close_menu_on_click)
		center.add_child(_menu_panel())
		key = "menu"  # pages within the menu switch without a fade
	elif not zoom.is_empty():
		dim.gui_input.connect(func(ev): if _is_click(ev): _close_zoom())
		center.add_child(_zoom_panel())
		key = "zoom:%s" % zoom.card.name
	elif not results_queue.is_empty():
		var entry: Dictionary = results_queue[0]
		center.add_child(_challenge_results(entry) if entry.type == "challenge" else _quest_results(entry))
		key = "%s:%d:%s:%d" % [entry.type, entry.quest, entry.get("kind", ""), history_seen - results_queue.size()]
	else:
		dim.color = Color(0.02, 0.01, 0.03, 0.96)  # mostly hide the board until they're ready
		center.add_child(_handoff_panel())
		key = "handoff:%d" % handoff
	if key != overlay_key and _animate():
		overlay.modulate.a = 0.0
		create_tween().tween_property(overlay, "modulate:a", 1.0, FADE_TIME)
	else:
		overlay.modulate.a = 1.0
	overlay_key = key


func _overlay_panel(width: float) -> Array:
	var pnl := FoUI.panel(FoUI.box(FoUI.PANEL, FoUI.GOLD, 2, 14, 26))
	pnl.custom_minimum_size.x = width
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	pnl.add_child(box)
	return [pnl, box]


func _zoom_panel() -> Control:
	var card: Dictionary = zoom.card
	var pb := _overlay_panel(1200)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	pb[1].add_child(row)
	var info: Dictionary = card if zoom.challenge else data.ingredient(card.name)
	var tex := FoAssets.challenge_art(info) if zoom.challenge else FoAssets.ingredient_art(info)
	if tex != null:
		row.add_child(FoUI.picture(tex, 440, true))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 16)
	row.add_child(text)
	text.add_child(FoUI.heading(info.get("name", card.name), 44, FoUI.GOLD))
	if zoom.challenge:
		text.add_child(FoUI.label("%s Challenge  ·  %s" % [info.kind, info.type], 24, FoUI.MUTED))
		text.add_child(FoUI.label(info.rule, 26))
	else:
		text.add_child(FoUI.label("Ingredient", 24, FoUI.MUTED))
		text.add_child(FoUI.label(info.get("text", ""), 26))
		var where := _card_location(card)
		if where != "":
			text.add_child(FoUI.label(where, 20, FoUI.RESERVE))
	text.add_child(_big_button("Close", _close_zoom))
	return pb[0]


func _card_location(card: Dictionary) -> String:
	for p in game.players:
		for c in p.reserve:
			if c.id == card.id:
				return "In %s's reserve" % p.name
		for c in p.ingredients:
			if c.id == card.id:
				return "Held by %s" % p.name
	return ""


func _challenge_results(entry: Dictionary) -> Control:
	var pb := _overlay_panel(1560)
	var box: VBoxContainer = pb[1]
	var card: Dictionary = entry.card
	box.add_child(FoUI.label("Quest %d  ·  %s Challenge" % [entry.quest + 1, entry.kind], 20,
		FoUI.RED if entry.kind == FoGame.STRENGTH else FoUI.MAGIC))
	box.add_child(FoUI.heading(card.name, 40, FoUI.GOLD))
	box.add_child(FoUI.label(card.rule, 20))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = mini(560, 110 * entry.rows.size())
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 18)
	scroll.add_child(rows)
	var all_marks: Array[int] = []
	for r in entry.rows:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		rows.add_child(row)
		var who := FoUI.heading(game.players[r.player].name, 24, FoUI.INK, false)
		who.custom_minimum_size.x = 220
		row.add_child(who)
		var dice := HFlowContainer.new()
		dice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dice.add_theme_constant_override("h_separation", 8)
		dice.add_theme_constant_override("v_separation", 8)
		row.add_child(dice)
		for d in r.dice:
			all_marks.append(d.mark)
			var b := FoUI.die_face(d.value, d.mark, d.magic, d.carried, 56)
			var steps: Array = d.steps
			var player_name: String = game.players[r.player].name
			b.pressed.connect(func():
				_play("click")
				if results_detail != null:
					results_detail.text = "%s's die:  %s" % [player_name, _breakdown_text(steps).replace("\n", "   ")])
			dice.add_child(b)
		var outcome: String = r.result
		if r.note != "":
			outcome += "\n" + r.note
		if entry.kind == FoGame.SHARPNESS:
			outcome += _parts_text(r.parts)
		var color := FoUI.INK
		if entry.kind == FoGame.STRENGTH and not r.skipped:
			color = FoUI.GOLD if Scoring.penalty_cost(r.penalty) == 0 else FoUI.RED
		var res := FoUI.label(outcome, 22, color)
		res.custom_minimum_size.x = 420
		row.add_child(res)
	var legend := _marks_legend(all_marks, entry.kind)
	if legend != "":
		box.add_child(FoUI.label(legend, 16, FoUI.MUTED))
	results_detail = FoUI.label("Tap a die to see how its value was worked out.", 18, FoUI.MUTED)
	box.add_child(results_detail)
	if entry.kind == FoGame.STRENGTH:
		box.add_child(FoUI.label("Penalties apply to this Quest's Sharpness Challenge.", 18, FoUI.MUTED))
	box.add_child(_big_button("Continue", _dismiss_results))
	return pb[0]


func _quest_results(entry: Dictionary) -> Control:
	var pb := _overlay_panel(1100)
	var box: VBoxContainer = pb[1]
	box.add_child(FoUI.heading("Quest %d complete" % (entry.quest + 1) + (": final standings" if entry.final else ""), 40, FoUI.GOLD))
	var rows: Array = entry.rows.duplicate()
	rows.sort_custom(func(a, b): return a.total > b.total)
	var best: int = rows[0].total
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)
	for h in ["Blacksmith", "This Quest", "", "Total"]:
		grid.add_child(FoUI.label(h, 20, FoUI.MUTED, false))
	for r in rows:
		var leader: bool = r.total == best
		var cells := [game.players[r.player].name, FoGame.successes_text(r.score),
			"" if r.wager == 0 else "(%d from Challenge, wager %+d)" % [r.challenge, r.wager], str(r.total)]
		for c in cells:
			grid.add_child(FoUI.label(c, 26, FoUI.GOLD if leader else FoUI.INK, false))
	if not entry.final:
		box.add_child(FoUI.label("Next: everyone reserves an Ingredient, then whoever scored the fewest Successes this Quest drafts first.", 20, FoUI.MUTED))
	box.add_child(_big_button("Continue", _dismiss_results))
	return pb[0]


func _dismiss_results() -> void:
	if not results_queue.is_empty():
		results_queue.pop_front()


func _marks_legend(marks: Array[int], kind: String) -> String:
	var parts := PackedStringArray()
	if 1 in marks:
		parts.append("Gold border: " + ("scores a Success" if kind == FoGame.SHARPNESS else "protects you from the penalty"))
	if -1 in marks:
		parts.append("Red border: triggers the penalty")
	return "   ".join(parts)


func _breakdown_text(steps: Array) -> String:
	var lines := PackedStringArray([steps[0].text])
	for i in range(1, steps.size()):
		lines.append("%s  ->  %d" % [steps[i].text, steps[i].value])
	if steps.size() > 1:
		lines.append("= %d" % steps[-1].value)
	return "\n".join(lines)


## " (2 from Vampire Bat + 1 from Mithril)" when more than one thing scored, else "".
func _parts_text(parts: Array) -> String:
	var scoring := parts.filter(func(p): return p[1] != 0)
	if scoring.size() < 2:
		return ""
	return " (" + " + ".join(scoring.map(func(p): return "%d from %s" % [p[1], p[0]])) + ")"


# ------------------------------------------------------------------ saving & hand-off

## Rewrite the save whenever a move is made or a results screen is dismissed.
func _autosave() -> void:
	if not persist:
		return
	var state := [game.moves.size(), history_seen - results_queue.size()]
	if state == saved:
		return
	saved = state
	if game.phase == FoGame.Phase.GAME_OVER:
		FoSave.clear()
	else:
		FoSave.write(game, state[1])


## Hotseat: when a decision moves to a different human, cover the board until they're ready.
## Never for CPU turns, or with only one human at the table.
func _check_handoff() -> void:
	if game.phase == FoGame.Phase.GAME_OVER or game.player().is_bot:
		return
	var humans := game.players.filter(func(p): return not p.is_bot).size()
	if humans >= 2 and game.current != last_human:
		handoff = game.current
	last_human = game.current


func _dismiss_handoff() -> void:
	handoff = -1


func _handoff_panel() -> Control:
	var p = game.players[handoff]
	var pb := _overlay_panel(760)
	var box: VBoxContainer = pb[1]
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var title := FoUI.heading("Pass to %s" % p.name, 56, FoUI.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var what := FoUI.label("%s, it's your turn to %s." % [p.name, _turn_task()], 24, FoUI.INK)
	what.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(what)
	var go := _big_button("I'm %s, let's go" % p.name, _dismiss_handoff)
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(go)
	return pb[0]


func _turn_task() -> String:
	match game.phase:
		FoGame.Phase.CRAFT:
			return "craft: draft an Ingredient, sharpen or pass"
		FoGame.Phase.SWAP:
			return "choose what your Rusty Bauble swaps for"
		FoGame.Phase.WAGER:
			return "decide whether to wager a Success"
		FoGame.Phase.REACT:
			return "roll for the %s Challenge" % game.challenge_kind
		FoGame.Phase.RESERVE:
			return "reserve an Ingredient"
	return "play"


# ------------------------------------------------------------------ menu & settings

func _unhandled_input(ev: InputEvent) -> void:
	if not ev.is_action_pressed("ui_cancel"):
		return
	if not zoom.is_empty():
		_close_zoom()
	elif menu != "":
		_close_menu()
	elif game != null:
		_open_menu("pause")
	get_viewport().set_input_as_handled()


## page: pause, settings, rules or restart. Settings and rules return to where they came from.
func _open_menu(page: String) -> void:
	menu_back = menu if page in ["settings", "rules"] else ""
	menu = page
	_render_overlay()


## Off in tests and --autoplay, like the game save.
func _save_settings() -> void:
	if persist:
		FoSettings.save_file()


func _close_menu_on_click(ev: InputEvent) -> void:
	if _is_click(ev):
		_close_menu()


func _close_menu() -> void:
	_save_settings()
	menu = menu_back if menu in ["settings", "rules"] else ""
	menu_back = ""
	_render_overlay()


func _menu_panel() -> Control:
	match menu:
		"settings":
			return _settings_panel()
		"rules":
			return _rules_panel()
		"restart":
			return _restart_panel()
	var pb := _overlay_panel(560)
	var box: VBoxContainer = pb[1]
	var title := FoUI.heading("Paused", 44, FoUI.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	box.add_child(_big_button("Resume", _close_menu))
	box.add_child(_big_button("Settings", func(): _open_menu("settings")))
	box.add_child(_big_button("How to play", func(): _open_menu("rules")))
	box.add_child(_big_button("Restart", func(): _open_menu("restart")))
	box.add_child(_big_button("Quit to title", _show_setup))
	var note := FoUI.label("The game saves after every move. Pick it up later with Continue on the title screen.", 18, FoUI.MUTED)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(note)
	return pb[0]


func _restart_panel() -> Control:
	var pb := _overlay_panel(640)
	var box: VBoxContainer = pb[1]
	box.add_child(FoUI.heading("Restart?", 40, FoUI.GOLD))
	box.add_child(FoUI.label("A new game starts with the same Blacksmiths. This game will be lost.", 22))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.add_child(_big_button("Restart", func():
		_new_game(game.players.map(func(p): return p.name), game.players.map(func(p): return p.is_bot))))
	row.add_child(_big_button("Cancel", func(): _open_menu("pause")))
	box.add_child(row)
	return pb[0]


func _settings_panel() -> Control:
	var pb := _overlay_panel(860)
	var box: VBoxContainer = pb[1]
	box.add_child(FoUI.heading("Settings", 40, FoUI.GOLD))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 18)
	box.add_child(grid)
	_setting_row(grid, "Sound effects", _slider(FoSettings.sfx_volume, func(v): FoSettings.sfx_volume = v, func(): _play("click")))
	_setting_row(grid, "Music", _slider(FoSettings.music_volume, func(v):
		FoSettings.music_volume = v
		_update_music()))
	_setting_row(grid, "CPU speed", _choice(FoSettings.CPU_SPEEDS, FoSettings.cpu_speed, func(i): FoSettings.cpu_speed = i))
	_setting_row(grid, "Text size", _choice(FoSettings.TEXT_SIZES, FoSettings.text_size, func(i):
		FoSettings.text_size = i
		_apply_text_size()))
	var motion := _toggle("Fewer animations", FoSettings.reduce_motion, func(on):
		FoSettings.reduce_motion = on
		_save_settings())
	_setting_row(grid, "Reduce motion", motion)
	box.add_child(_big_button("Done", _close_menu))
	return pb[0]


func _setting_row(grid: GridContainer, text: String, control: Control) -> void:
	var l := FoUI.label(text, 22, FoUI.INK, false)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(l)
	grid.add_child(control)


## A 0..1 volume slider. `released` runs when a drag ends (e.g. to preview the sound).
func _slider(value: float, changed: Callable, released := Callable()) -> HSlider:
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.05
	sl.value = value
	sl.custom_minimum_size = Vector2(420, 44)
	sl.value_changed.connect(func(v): changed.call(v))
	sl.drag_ended.connect(func(_changed):
		_save_settings()
		if released.is_valid():
			released.call())
	return sl


## A row of buttons, one of them selected.
func _choice(options: Array, selected: int, f: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	for i in options.size():
		var b := Button.new()
		b.text = options[i]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == selected
		b.custom_minimum_size = Vector2(132, 48)
		b.pressed.connect(func():
			_play("toggle")
			f.call(i)
			_save_settings())
		row.add_child(b)
	return row


## Text size changes rebuild the current screen (keeping the setup screen's seats).
func _apply_text_size() -> void:
	theme = FoUI.make_theme()
	if game != null:
		_build_board()
		return
	var page := menu
	var back := menu_back
	var count := count_spin.value
	var seats := seat_rows.map(func(r): return [r[1].text, r[2].button_pressed])
	_show_setup()
	count_spin.value = count
	for i in seats.size():
		seat_rows[i][1].text = seats[i][0]
		seat_rows[i][2].button_pressed = seats[i][1]
	menu = page
	menu_back = back
	_render_overlay()


func _rules_panel() -> Control:
	var pb := _overlay_panel(1240)
	var box: VBoxContainer = pb[1]
	box.add_child(FoUI.heading("How to play", 40, FoUI.GOLD))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 700
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 8)
	for sec in FoRulesText.SECTIONS:
		text.add_child(FoUI.heading(sec[0], 24, FoUI.GOLD))
		var body := FoUI.label(sec[1], 21)
		body.custom_minimum_size.x = 1140
		text.add_child(body)
	scroll.add_child(text)
	box.add_child(scroll)
	box.add_child(_big_button("Done", _close_menu))
	return pb[0]


# ------------------------------------------------------------------ animation

func _animate() -> bool:
	return not FoSettings.reduce_motion and not autoplay and is_inside_tree()


## Dice show random faces for a moment after a roll, then settle with a small pop.
func _tumble(delta: float) -> void:
	tumble_left -= delta
	tumble_tick -= delta
	if tumble_left <= 0:
		tumble_left = 0.0
		_refresh()
		for b in dice_nodes:
			b.scale = Vector2(1.15, 1.15)
			create_tween().tween_property(b, "scale", Vector2.ONE, 0.15)
		return
	if tumble_tick <= 0:
		tumble_tick = TUMBLE_TICK
		for b in dice_nodes:
			if is_instance_valid(b):
				b.text = str(randi_range(1, 6))  # cosmetic only: never touches game.rng
				b.rotation = randf_range(-0.3, 0.3)


func _register_card(c: Dictionary, zone: String, node: Control) -> void:
	if not card_nodes.has(c.id):
		card_nodes[c.id] = [zone, node, c.name]


func _card_rects() -> Dictionary:
	var out := {}
	for id in card_nodes:
		var n = card_nodes[id][1]
		if is_instance_valid(n) and n.is_inside_tree():
			out[id] = [card_nodes[id][0], n.get_global_rect()]
	return out


## Cards that changed zone since the last render (table -> mat, mat -> mat, reserve -> mat)
## fly from where they were. The new card stays invisible until its copy lands.
func _queue_flights(old: Dictionary) -> void:
	if not _animate():
		return
	var moves := []
	for id in card_nodes:
		if old.has(id) and old[id][0] != card_nodes[id][0]:
			var target: Control = card_nodes[id][1]
			target.modulate.a = 0.0
			moves.append([target, old[id][1], card_nodes[id][2]])
	if moves.is_empty():
		return
	flights += moves.size()
	_launch_flights(moves)


func _launch_flights(moves: Array) -> void:
	# wait for containers to lay out the new nodes so their positions are final
	await get_tree().process_frame
	await get_tree().process_frame
	for m in moves:
		var target = m[0]
		if not is_instance_valid(target) or not target.is_inside_tree() or fx_layer == null:
			flights -= 1
			continue
		var to: Rect2 = target.get_global_rect()
		var from: Rect2 = m[1]
		var ghost := FoUI.card_tile(m[2], "", FoAssets.ingredient_art(data.ingredient(m[2])), to.size)
		ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fx_layer.add_child(ghost)
		ghost.global_position = from.position
		ghost.size = to.size
		ghost.scale = from.size / to.size
		var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(ghost, "global_position", to.position, FLIGHT_TIME)
		tw.tween_property(ghost, "scale", Vector2.ONE, FLIGHT_TIME)
		tw.chain().tween_callback(func():
			ghost.queue_free()
			if is_instance_valid(target):
				target.modulate.a = 1.0
			flights -= 1)


# ------------------------------------------------------------------ helpers

## Run a game action after the current signal finishes, then redraw.
func _act(f: Callable) -> void:
	(func():
		f.call()
		_refresh()).call_deferred()


## click_sound: off for buttons whose action has its own sound (drafting a card).
func _button(text: String, f: Callable, click_sound := true) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func():
		if click_sound:
			_play("click")
		_act(f))
	return b


func _big_button(text: String, f: Callable) -> Button:
	var b := _button(text, f)
	b.custom_minimum_size = Vector2(220, 60)
	b.add_theme_font_size_override("font_size", FoUI.fs(24))
	return b


func _prompt(text: String) -> Label:
	return FoUI.heading(text, 26, FoUI.INK)


func _toggle(text: String, on: bool, f: Callable) -> CheckButton:
	var b := CheckButton.new()
	b.text = text
	b.button_pressed = on
	b.toggled.connect(func(v):
		f.call(v)
		_play("toggle"))
	return b


## An Ingredient as a full card tile. Tapping it runs `f`; the corner "i" zooms it.
func _card_tile(card: Dictionary, f: Callable, owner_note := "", edge := FoUI.EDGE) -> Button:
	var title: String = card.name if owner_note == "" else "%s %s" % [owner_note, card.name]
	var t := FoUI.card_tile(title, game.text_of(card), FoAssets.ingredient_art(data.ingredient(card.name)), FoUI.TILE, edge)
	t.pressed.connect(func(): _act(f))
	var info := FoUI.corner_button(t, "i")
	info.pressed.connect(func():
		_play("click")
		_open_zoom(card, false))
	return t


func _tile_flow() -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 10)
	f.add_theme_constant_override("v_separation", 10)
	action_box.add_child(f)
	return f


func _zoomable(c: Control, card: Dictionary, challenge: bool) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	c.gui_input.connect(func(ev):
		if _is_click(ev):
			_play("click")
			_open_zoom(card, challenge))


func _is_click(ev: InputEvent) -> bool:
	return ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT


func _clear(n: Node) -> void:
	for c in n.get_children():
		if c == audio_root:
			continue
		n.remove_child(c)
		c.queue_free()


# ------------------------------------------------------------------ audio

func _setup_audio() -> void:
	audio_root = Node.new()
	audio_root.name = "Audio"
	add_child(audio_root)
	for i in SFX_VOICES:
		var p := AudioStreamPlayer.new()
		audio_root.add_child(p)
		sfx.append(p)
	music = AudioStreamPlayer.new()
	var m := FoAssets.stream(FoAssets.MUSIC)
	if m is AudioStreamMP3:
		m.loop = true
	music.stream = m
	audio_root.add_child(music)
	_update_music()


func _update_music() -> void:
	if music == null or music.stream == null:
		return
	var on := FoSettings.music_volume > 0.0
	if on:
		music.volume_db = MUSIC_DB + linear_to_db(FoSettings.music_volume)
	if on and not music.playing:
		music.play()
	elif not on:
		music.stop()


func _play(event: String) -> void:
	_play_file(FoAssets.sfx_path(event), FoAssets.SFX[event][1])


func _play_file(path: String, volume := 0.5) -> void:
	if FoSettings.sfx_volume <= 0.0 or sfx.is_empty() or not is_inside_tree():
		return
	var s := FoAssets.stream(path)
	if s == null:
		return
	var p := sfx[sfx_next]
	sfx_next = (sfx_next + 1) % sfx.size()
	p.stream = s
	p.volume_db = linear_to_db(volume * FoSettings.sfx_volume)
	p.play()


## What changed since the last redraw, reduced to the things that make a sound or animate.
func _snapshot() -> Dictionary:
	var snap := {
		"phase": game.phase, "quest": game.quest, "current": game.current,
		"kind": game.challenge_kind, "ingredients": [], "sharpen": [], "reserve": [], "dice": "",
	}
	for p in game.players:
		snap.ingredients.append(p.ingredients.map(func(c): return c.name))
		snap.sharpen.append(p.sharpen)
		snap.reserve.append(p.reserve.size())
	if game.phase == FoGame.Phase.REACT:
		snap.dice = str(game.player().dice.map(func(d): return [d.raw, d.bonus, d.carried]))
	return snap


func _play_events() -> void:
	var now := _snapshot()
	var was := last_snap
	last_snap = now
	if was.is_empty():
		return
	if now.phase == FoGame.Phase.GAME_OVER:
		if was.phase != FoGame.Phase.GAME_OVER:
			_play("game_over")
		return
	if now.quest != was.quest:
		_play("quest_end")
	for pi in now.ingredients.size():
		var cards: Array = now.ingredients[pi]
		if cards.size() > was.ingredients[pi].size():
			_play_file(FoAssets.ingredient_sound_path(cards[-1]), 0.6)
		if now.sharpen[pi] > was.sharpen[pi]:
			_play("sharpen")
		if now.reserve[pi] > was.reserve[pi]:
			_play("reserve")
	if now.phase == FoGame.Phase.REACT:
		if was.phase != FoGame.Phase.REACT or was.kind != now.kind:
			_play("challenge")
		if was.phase != FoGame.Phase.REACT or was.kind != now.kind or was.current != now.current:
			_play("roll")
			if _animate():
				tumble_left = TUMBLE_TIME
				tumble_tick = 0.0
		elif was.dice != now.dice:
			_play("reaction")
