extends Control
## Minimal pass-and-play UI. All rules live in FoGame; this only draws state and
## forwards clicks. CPU seats are driven by FoBot, one decision every bot_delay seconds.
## Smoke test: `godot -- --autoplay` plays an all-CPU game at full speed and quits.
## Art, fonts and sounds come from FoAssets; sounds are triggered by diffing game state
## between redraws, so CPU moves make the same noises as human ones.

const BOT_DELAY := 0.45
const MAX_PLAYERS := 4
const DEFAULT_NAMES := ["Andrea", "Bob", "Carlos", "Dhivya"]
const SFX_VOICES := 8
const MUSIC_DB := -14.0
const HEADING_FONT := "Cinzel-Bold.ttf"
const BODY_FONT := "SourceSerif4-Regular.ttf"
const GOLD := Color(1.0, 0.75, 0.35)
const RED := Color(0.95, 0.35, 0.3)
const PANEL_BG := Color(0.16, 0.12, 0.18)

static var sound_on := true
static var music_on := true

var data: CardData
var game: FoGame
var selected_reaction := ""
var bot_wait := 0.0
var bot_delay := BOT_DELAY
var autoplay := "--autoplay" in OS.get_cmdline_user_args()

var seat_rows: Array = []  # [row, LineEdit, CheckBox]
var count_spin: SpinBox
var players_box: VBoxContainer
var header: VBoxContainer
var action_box: VBoxContainer
var log_view: RichTextLabel
var heading_font: Font
var audio_root: Node  # survives _clear(self) so music keeps playing across screens
var music: AudioStreamPlayer
var sfx: Array[AudioStreamPlayer] = []
var sfx_next := 0
var last_snap := {}
var overlay: Control           # results screens and card zoom, drawn over the board
var results_queue: Array = []  # FoGame.history entries the players haven't dismissed yet
var history_seen := 0
var zoom := {}                 # {card, challenge} while a card is zoomed
var selected_die := -1         # die whose breakdown is shown during a Challenge
var die_context := ""          # resets selected_die when the roller or Challenge changes
var results_detail: Label
var quitting := false


func _ready() -> void:
	var t := Theme.new()
	t.default_font_size = 22
	t.default_font = FoAssets.font(BODY_FONT)
	theme = t
	heading_font = FoAssets.font(HEADING_FONT)
	_setup_audio()
	data = CardData.load_default()
	_show_setup()
	if autoplay:
		bot_delay = 0.0
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
	if game == null or game.phase == FoGame.Phase.GAME_OVER or not game.player().is_bot or _blocking():
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
	box.add_child(_heading("Fires of Olympus", 64))
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
	var audio_row := HBoxContainer.new()
	audio_row.add_child(_toggle("Sound effects", sound_on, func(on): sound_on = on))
	audio_row.add_child(_toggle("Music", music_on, func(on):
		music_on = on
		_update_music()))
	box.add_child(audio_row)
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
	last_snap = {}
	results_queue.clear()
	history_seen = 0
	zoom = {}
	selected_die = -1
	_play("start")
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
	header = VBoxContainer.new()
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
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	_refresh()


func _refresh() -> void:
	if game == null or action_box == null:
		return
	_play_events()
	_sync_history()
	_render_players()
	_render_header()
	_render_actions()
	log_view.text = "\n".join(game.log_lines)
	_render_overlay()


func _render_header() -> void:
	_clear(header)
	header.add_child(_heading("Quest %d of 3" % mini(game.quest + 1, 3), 30))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	for kind in [FoGame.STRENGTH, FoGame.SHARPNESS]:
		var active: bool = game.phase == FoGame.Phase.REACT and game.challenge_kind == kind
		row.add_child(_challenge_panel(game.challenge_card(kind), active))
	header.add_child(row)


func _challenge_panel(card: Dictionary, active: bool) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = GOLD if active else Color(0.35, 0.3, 0.38)
	style.set_border_width_all(3 if active else 1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var tex := FoAssets.challenge_art(card)
	if tex != null:
		row.add_child(_picture(tex, 120))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := _heading("%s: %s" % [card.kind, card.name], 22)
	if active:
		title.add_theme_color_override("font_color", GOLD)
	text.add_child(title)
	text.add_child(_label("%s\n%s" % [card.type, card.rule], 17))
	row.add_child(text)
	_zoomable(panel, card, true)
	return panel


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
			l.add_theme_color_override("font_color", GOLD)
		players_box.add_child(l)
		var icons := HFlowContainer.new()
		players_box.add_child(icons)
		for c in p.ingredients + p.reserve:
			var tex := FoAssets.ingredient_art(data.ingredient(c.name))
			if tex != null:
				var pic := _picture(tex, 56)
				pic.tooltip_text = c.name
				_zoomable(pic, c, false)
				icons.add_child(pic)
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
	var vals := game.values(game.current, game.challenge_kind)
	var result := "Current result: " + game.describe_outcome(game.current)
	var note := Scoring.total_note(card.name, vals)
	if note != "":
		result += "   " + note
	if game.challenge_kind == FoGame.SHARPNESS:
		result += _parts_text(game.success_parts(game.current, vals))
	action_box.add_child(_label(result))
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


## The rolling player's dice. Clicking one applies the selected Reaction, or with
## no Reaction selected shows how that die's value was worked out.
func _render_dice(clickable: bool) -> void:
	var p := game.player()
	var ctx := "%d:%d:%s" % [game.quest, game.current, game.challenge_kind]
	if ctx != die_context:
		die_context = ctx
		selected_die = -1
	var marks := game.die_marks(game.current, game.challenge_kind)
	var row := HFlowContainer.new()
	for i in p.dice.size():
		var d = p.dice[i]
		var v := game.die_value(game.current, d, game.challenge_kind)
		var b := _die_button(v, marks[i], d.magic, d.carried, 72, clickable and i == selected_die)
		if clickable:
			b.pressed.connect(func(): _act(func():
				if selected_reaction != "":
					game.apply_reaction(selected_reaction, i)
				else:
					selected_die = -1 if selected_die == i else i))
		else:
			b.disabled = true
		row.add_child(b)
	action_box.add_child(row)
	var legend := _marks_legend(marks, game.challenge_kind)
	if legend != "":
		action_box.add_child(_label(legend, 16))
	if clickable:
		if selected_die >= 0 and selected_die < p.dice.size():
			var steps := game.die_breakdown(game.current, p.dice[selected_die], game.challenge_kind)
			action_box.add_child(_label(_breakdown_text(steps), 18))
		elif selected_reaction == "":
			action_box.add_child(_label("Tap a die to see how its value was worked out.", 16))


func _render_game_over() -> void:
	var ranked := range(game.players.size())
	ranked.sort_custom(func(a, b): return game.players[a].total > game.players[b].total)
	var lines := PackedStringArray()
	for pi in ranked:
		var p = game.players[pi]
		lines.append("%s%s: %d Successes %s" % ["* " if pi in game.winners() else "", p.name, p.total, str(p.quest_scores)])
	action_box.add_child(_label("Game over!\n\n" + "\n".join(lines), 28))
	action_box.add_child(_button("New game", _show_setup))


# ------------------------------------------------------------------ overlays

## Queue results screens for Challenges and Quests that finished since the last redraw.
## The --autoplay smoke test never shows them.
func _sync_history() -> void:
	while history_seen < game.history.size():
		if not autoplay:
			results_queue.append(game.history[history_seen])
		history_seen += 1


## True while a results screen or zoomed card is up: CPU players wait for it to close.
func _blocking() -> bool:
	return not results_queue.is_empty() or not zoom.is_empty()


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
	overlay.visible = _blocking()
	if not overlay.visible:
		return
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	if not zoom.is_empty():
		dim.gui_input.connect(func(ev): if _is_click(ev): _close_zoom())
		center.add_child(_zoom_panel())
	else:
		var entry: Dictionary = results_queue[0]
		center.add_child(_challenge_results(entry) if entry.type == "challenge" else _quest_results(entry))


func _overlay_panel(width: float) -> Array:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	return [panel, box]


func _zoom_panel() -> Control:
	var card: Dictionary = zoom.card
	var pb := _overlay_panel(1200)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	pb[1].add_child(row)
	var info: Dictionary = card if zoom.challenge else data.ingredient(card.name)
	var tex := FoAssets.challenge_art(info) if zoom.challenge else FoAssets.ingredient_art(info)
	if tex != null:
		var pic := _picture(tex, 440)
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		row.add_child(pic)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 16)
	row.add_child(text)
	var title := _heading(info.get("name", card.name), 44)
	title.add_theme_color_override("font_color", GOLD)
	text.add_child(title)
	if zoom.challenge:
		text.add_child(_label("%s Challenge - %s" % [info.kind, info.type], 24))
		text.add_child(_label(info.rule, 26))
	else:
		text.add_child(_label("Ingredient", 24))
		text.add_child(_label(info.get("text", ""), 26))
		var where := _card_location(card)
		if where != "":
			text.add_child(_label(where, 20))
	text.add_child(_button("Close", _close_zoom))
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
	var title := _heading("Quest %d - %s Challenge: %s" % [entry.quest + 1, entry.kind, card.name], 36)
	title.add_theme_color_override("font_color", GOLD)
	box.add_child(title)
	box.add_child(_label(card.rule, 20))
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
		var who := _heading(game.players[r.player].name, 24)
		who.custom_minimum_size.x = 220
		row.add_child(who)
		var dice := HFlowContainer.new()
		dice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(dice)
		for d in r.dice:
			all_marks.append(d.mark)
			var b := _die_button(d.value, d.mark, d.magic, d.carried, 56, false)
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
		var res := _label(outcome, 22)
		res.custom_minimum_size.x = 420
		if entry.kind == FoGame.STRENGTH and not r.skipped:
			res.add_theme_color_override("font_color", GOLD if Scoring.penalty_cost(r.penalty) == 0 else RED)
		row.add_child(res)
	var legend := _marks_legend(all_marks, entry.kind)
	if legend != "":
		box.add_child(_label(legend, 16))
	results_detail = _label("Tap a die to see how its value was worked out.", 18)
	box.add_child(results_detail)
	if entry.kind == FoGame.STRENGTH:
		box.add_child(_label("Penalties apply to this Quest's Sharpness Challenge.", 18))
	box.add_child(_button("Continue", _dismiss_results))
	return pb[0]


func _quest_results(entry: Dictionary) -> Control:
	var pb := _overlay_panel(1100)
	var box: VBoxContainer = pb[1]
	var title := _heading("Quest %d complete" % (entry.quest + 1) + (" - final standings" if entry.final else ""), 40)
	title.add_theme_color_override("font_color", GOLD)
	box.add_child(title)
	var rows: Array = entry.rows.duplicate()
	rows.sort_custom(func(a, b): return a.total > b.total)
	var best: int = rows[0].total
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)
	for h in ["Blacksmith", "This Quest", "", "Total"]:
		var hl := _label(h, 20)
		hl.autowrap_mode = TextServer.AUTOWRAP_OFF  # wrapping labels collapse to 0 width in a grid
		grid.add_child(hl)
	for r in rows:
		var leader: bool = r.total == best
		var cells := [game.players[r.player].name, FoGame.successes_text(r.score),
			"" if r.wager == 0 else "(%d from Challenge, wager %+d)" % [r.challenge, r.wager], str(r.total)]
		for c in cells:
			var l := _label(c, 26)
			l.autowrap_mode = TextServer.AUTOWRAP_OFF
			if leader:
				l.add_theme_color_override("font_color", GOLD)
			grid.add_child(l)
	if not entry.final:
		box.add_child(_label("Next: everyone reserves an Ingredient, then whoever scored the fewest Successes this Quest drafts first.", 20))
	box.add_child(_button("Continue", _dismiss_results))
	return pb[0]


func _dismiss_results() -> void:
	if not results_queue.is_empty():
		results_queue.pop_front()


## One die face. mark: 1 = scores / protects (gold, thick border), -1 = triggers a penalty (red, thick border).
func _die_button(value: int, mark: int, magic: bool, carried: bool, size: float, selected: bool) -> Button:
	var b := Button.new()
	b.text = str(value)
	b.custom_minimum_size = Vector2(size, size)
	b.add_theme_font_size_override("font_size", int(size * 0.45))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.25, 0.22, 0.28) if not selected else Color(0.4, 0.34, 0.45)
	style.set_corner_radius_all(int(size * 0.15))
	match mark:
		1:
			style.border_color = GOLD
			style.set_border_width_all(5)
		-1:
			style.border_color = RED
			style.set_border_width_all(5)
		_:
			style.border_color = Color(0.45, 0.4, 0.5)
			style.set_border_width_all(1)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(state, style)
	var font_color := Color.WHITE
	if magic:
		font_color = Color(0.5, 0.8, 1.0)
	if carried:
		font_color = Color(1.0, 0.85, 0.3)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color"]:
		b.add_theme_color_override(c, font_color)
	return b


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


func _zoomable(c: Control, card: Dictionary, challenge: bool) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	c.gui_input.connect(func(ev):
		if _is_click(ev):
			_play("click")
			_open_zoom(card, challenge))


func _is_click(ev: InputEvent) -> bool:
	return ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT


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


func _toggle(text: String, on: bool, f: Callable) -> CheckButton:
	var b := CheckButton.new()
	b.text = text
	b.button_pressed = on
	b.toggled.connect(func(v):
		f.call(v)
		_play("toggle"))
	return b


func _heading(text: String, size := 28) -> Label:
	var l := _label(text, size)
	if heading_font != null:
		l.add_theme_font_override("font", heading_font)
	return l


func _picture(tex: Texture2D, size: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(size, size)
	return r


## An Ingredient button plus a narrow "Info" button that zooms the card.
func _card_button(card: Dictionary, f: Callable, prefix := "") -> Control:
	var wrap := HBoxContainer.new()
	wrap.add_theme_constant_override("separation", 2)
	var b := _button("%s%s\n%s" % [prefix, card.name, game.text_of(card)], f, false)
	b.custom_minimum_size = Vector2(300, 130)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_child(b)
	var info := _button("Info", func(): _open_zoom(card, false))
	info.custom_minimum_size = Vector2(56, 130)
	info.add_theme_font_size_override("font_size", 15)
	wrap.add_child(info)
	var tex := FoAssets.ingredient_art(data.ingredient(card.name))
	if tex != null:
		b.icon = tex
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 96)
		b.add_theme_constant_override("h_separation", 10)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 18)
	return wrap


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
	music.volume_db = MUSIC_DB
	audio_root.add_child(music)
	_update_music()


func _update_music() -> void:
	if music == null or music.stream == null:
		return
	if music_on and not music.playing:
		music.play()
	elif not music_on:
		music.stop()


func _play(event: String) -> void:
	_play_file(FoAssets.sfx_path(event), FoAssets.SFX[event][1])


func _play_file(path: String, volume := 0.5) -> void:
	if not sound_on or sfx.is_empty() or not is_inside_tree():
		return
	var s := FoAssets.stream(path)
	if s == null:
		return
	var p := sfx[sfx_next]
	sfx_next = (sfx_next + 1) % sfx.size()
	p.stream = s
	p.volume_db = linear_to_db(volume)
	p.play()


## What changed since the last redraw, reduced to the things that make a sound.
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
		elif was.dice != now.dice:
			_play("reaction")
