extends Control
## Minimal pass-and-play UI. All rules live in FoGame; this only draws state and
## forwards clicks. CPU seats are driven by FoBot, one decision every bot_delay seconds.
## Smoke test: `godot -- --autoplay` plays an all-CPU game at full speed and quits.

const BOT_DELAY := 0.45
const MAX_PLAYERS := 4
const DEFAULT_NAMES := ["Andrea", "Bob", "Carlos", "Dhivya"]

var data: CardData
var game: FoGame
var selected_reaction := ""
var bot_wait := 0.0
var bot_delay := BOT_DELAY
var autoplay := "--autoplay" in OS.get_cmdline_user_args()

var seat_rows: Array = []  # [row, LineEdit, CheckBox]
var count_spin: SpinBox
var players_box: VBoxContainer
var header: Label
var action_box: VBoxContainer
var log_view: RichTextLabel


func _ready() -> void:
	var t := Theme.new()
	t.default_font_size = 22
	theme = t
	data = CardData.load_default()
	_show_setup()
	if autoplay:
		bot_delay = 0.0
		for row in seat_rows:
			row[2].button_pressed = true
	if autoplay or "--start" in OS.get_cmdline_user_args():
		_start_game()


func _process(delta: float) -> void:
	if autoplay and game != null and game.phase == FoGame.Phase.GAME_OVER:
		print(game.log_lines[-1])
		get_tree().quit()
		return
	if game == null or game.phase == FoGame.Phase.GAME_OVER or not game.player().is_bot:
		return
	bot_wait -= delta
	if bot_wait > 0:
		return
	bot_wait = bot_delay
	FoBot.step(game)
	_refresh()


# ------------------------------------------------------------------ setup screen

func _show_setup() -> void:
	game = null
	action_box = null
	_clear(self)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	box.add_child(_label("Fires of Olympus", 56))
	if not data.errors.is_empty():
		box.add_child(_label("Card data problems:\n" + "\n".join(data.errors), 18))
	var row := HBoxContainer.new()
	row.add_child(_label("Blacksmiths"))
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
		var name_edit := LineEdit.new()
		name_edit.text = DEFAULT_NAMES[i]
		name_edit.custom_minimum_size.x = 280
		var cpu := CheckBox.new()
		cpu.text = "CPU"
		cpu.button_pressed = i > 0
		r.add_child(name_edit)
		r.add_child(cpu)
		box.add_child(r)
		seat_rows.append([r, name_edit, cpu])
	box.add_child(_button("Start", _start_game))
	_update_seats()


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
	game = FoGame.new(data)
	game.setup(names, bots, randi())
	_build_board()


# ------------------------------------------------------------------ board

func _build_board() -> void:
	_clear(self)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 20)
	margin.add_child(root)

	var left := ScrollContainer.new()
	left.custom_minimum_size.x = 460
	left.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	players_box = VBoxContainer.new()
	players_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	players_box.add_theme_constant_override("separation", 14)
	left.add_child(players_box)
	root.add_child(left)

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header = _label("")
	mid.add_child(header)
	mid.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	action_box = VBoxContainer.new()
	action_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_box.add_theme_constant_override("separation", 12)
	scroll.add_child(action_box)
	mid.add_child(scroll)
	root.add_child(mid)

	log_view = RichTextLabel.new()
	log_view.custom_minimum_size.x = 480
	log_view.scroll_following = true
	log_view.add_theme_font_size_override("normal_font_size", 17)
	root.add_child(log_view)
	_refresh()


func _refresh() -> void:
	if game == null or action_box == null:
		return
	_render_players()
	_render_header()
	_render_actions()
	log_view.text = "\n".join(game.log_lines)


func _render_header() -> void:
	var s: Dictionary = game.strength_card
	var h: Dictionary = game.sharpness_card
	header.text = "Quest %d of 3\nStrength: %s (%s) - %s\nSharpness: %s (%s) - %s" % [
		mini(game.quest + 1, 3), s.name, s.type, s.rule, h.name, h.type, h.rule]


func _render_players() -> void:
	_clear(players_box)
	for pi in game.players.size():
		var p = game.players[pi]
		var lines := PackedStringArray()
		var marker := "> " if pi == game.current and game.phase != FoGame.Phase.GAME_OVER else ""
		lines.append("%s%s%s - %d Successes %s" % [marker, p.name, " (CPU)" if p.is_bot else "", p.total, str(p.quest_scores)])
		lines.append("AP %d   Sharpened %dx%s" % [p.ap, p.sharpen, "   passed" if p.passed else ""])
		lines.append("Ingredients: " + _names(p.ingredients))
		lines.append("Reserve: " + _names(p.reserve))
		var a: Dictionary = game.pool_size(pi, FoGame.STRENGTH)
		var b: Dictionary = game.pool_size(pi, FoGame.SHARPNESS)
		lines.append("Dice: Strength %d, Sharpness %d" % [a.normal + a.magic, b.normal + b.magic])
		if not p.penalty.is_empty():
			lines.append("Penalty: " + Scoring.describe_penalty(p.penalty))
		var l := _label("\n".join(lines), 19)
		if marker != "":
			l.add_theme_color_override("font_color", Color(1.0, 0.75, 0.35))
		players_box.add_child(l)
		players_box.add_child(HSeparator.new())


func _render_actions() -> void:
	_clear(action_box)
	if game.phase == FoGame.Phase.GAME_OVER:
		_render_game_over()
		return
	var p := game.player()
	if p.is_bot:
		action_box.add_child(_label("%s (CPU) is thinking..." % p.name))
		if game.phase == FoGame.Phase.REACT:
			_render_dice(false)
		return
	match game.phase:
		FoGame.Phase.CRAFT:
			_render_craft()
		FoGame.Phase.SWAP:
			action_box.add_child(_label("%s: Rusty Bauble - choose an opponent's Ingredient to swap it with" % p.name))
			var grid := _grid()
			for t in game.swap_targets(game.current):
				var who: String = game.players[t.player].name
				grid.add_child(_card_button(t.card, func(): game.act_swap(t.player, t.card.id), who + ": "))
		FoGame.Phase.WAGER:
			action_box.add_child(_label("%s: Gambler's Charm - wager a Success?\nIf you score the most Sharpness Successes this Quest (no ties) you gain 1, otherwise you lose 1." % p.name))
			var row := HBoxContainer.new()
			row.add_child(_button("Wager", func(): game.act_wager(true)))
			row.add_child(_button("No wager", func(): game.act_wager(false)))
			action_box.add_child(row)
		FoGame.Phase.REACT:
			_render_react()
		FoGame.Phase.RESERVE:
			action_box.add_child(_label("%s: reserve one Ingredient for future Quests (only you can draft it)" % p.name))
			var grid := _grid()
			for c in game.reservable(game.current):
				grid.add_child(_card_button(c, func(): game.act_reserve(c.id)))


func _render_craft() -> void:
	var p := game.player()
	action_box.add_child(_label("%s - choose an action (%d AP left, each action costs 1)" % [p.name, p.ap]))
	action_box.add_child(_label("Ingredients on the table", 18))
	var grid := _grid()
	for c in game.market:
		grid.add_child(_card_button(c, func(): game.act_draft(c.id)))
	var reserve := game.reserve_options(game.current)
	if not reserve.is_empty():
		action_box.add_child(_label("Your reserve", 18))
		var rgrid := _grid()
		for c in reserve:
			rgrid.add_child(_card_button(c, func(): game.act_draft(c.id)))
	var row := HBoxContainer.new()
	var sharpen_text := "Sharpen"
	if p.sharpen < FoGame.SHARPEN_DICE.size():
		sharpen_text += " (+%dd6)" % (FoGame.SHARPEN_DICE[p.sharpen] + game.flag_sum(game.current, "electrum"))
	var sb := _button(sharpen_text, func(): game.act_sharpen())
	sb.disabled = not game.can_sharpen(game.current)
	row.add_child(sb)
	row.add_child(_button("Pass (done for this Quest)", func(): game.act_pass()))
	action_box.add_child(row)


func _render_react() -> void:
	var p := game.player()
	var card := game.challenge_card(game.challenge_kind)
	action_box.add_child(_label("%s - %s Challenge vs %s" % [p.name, game.challenge_kind, card.name]))
	_render_dice(true)
	action_box.add_child(_label("Current result: " + game.describe_outcome(game.current)))
	var reactions := game.available_reactions(game.current)
	var still_valid := false
	if not reactions.is_empty():
		action_box.add_child(_label("Reactions: pick one, then click a die", 18))
		var row := HFlowContainer.new()
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
	action_box.add_child(_button("Done", func():
		selected_reaction = ""
		game.finish_reactions()))


func _render_dice(clickable: bool) -> void:
	var p := game.player()
	var row := HFlowContainer.new()
	for i in p.dice.size():
		var d = p.dice[i]
		var v := game.die_value(game.current, d, game.challenge_kind)
		var b := Button.new()
		b.text = str(v)
		b.custom_minimum_size = Vector2(72, 72)
		b.add_theme_font_size_override("font_size", 32)
		b.tooltip_text = "rolled %d%s%s" % [d.raw, " (magic)" if d.magic else "", " (kept)" if d.carried else ""]
		if d.magic:
			b.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
		if d.carried:
			b.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		if clickable:
			b.pressed.connect(func(): _act(func():
				if selected_reaction != "":
					game.apply_reaction(selected_reaction, i)))
		else:
			b.disabled = true
		row.add_child(b)
	action_box.add_child(row)


func _render_game_over() -> void:
	var ranked := range(game.players.size())
	ranked.sort_custom(func(a, b): return game.players[a].total > game.players[b].total)
	var lines := PackedStringArray()
	for pi in ranked:
		var p = game.players[pi]
		lines.append("%s%s: %d Successes %s" % ["* " if pi in game.winners() else "", p.name, p.total, str(p.quest_scores)])
	action_box.add_child(_label("Game over!\n\n" + "\n".join(lines), 28))
	action_box.add_child(_button("New game", _show_setup))


# ------------------------------------------------------------------ helpers

## Run a game action after the current signal finishes, then redraw.
func _act(f: Callable) -> void:
	(func():
		f.call()
		_refresh()).call_deferred()


func _button(text: String, f: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func(): _act(f))
	return b


func _card_button(card: Dictionary, f: Callable, prefix := "") -> Button:
	var b := _button("%s%s\n%s" % [prefix, card.name, game.text_of(card)], f)
	b.custom_minimum_size = Vector2(300, 130)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 18)
	return b


func _grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 3
	action_box.add_child(g)
	return g


func _label(text: String, size := 22) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	return l


func _names(cards: Array) -> String:
	return "-" if cards.is_empty() else ", ".join(cards.map(func(c): return c.name))


func _clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()
