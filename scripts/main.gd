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
var cpu: Array = []            # per seat: {} for a human, {level, persona} for a CPU
var bot_plan: FoBot.Plan       # the CPU decision being thought about
const TOUCH := 72.0             # minimum tap size: 44 pt on an iPad at this 1920x1080 layout
const THINK_MS := 10.0         # Hard CPUs think this long per frame so the UI stays smooth
var autoplay := "--autoplay" in OS.get_cmdline_user_args()

var seat_rows: Array = []  # [seat box, name LineEdit, CPU CheckBox, persona OptionButton, level OptionButton, blurb Label]
var player_count := 3            # seats in use on the setup screen
var count_row: HBoxContainer
var players_box: BoxContainer   # a row along the bottom; a column on the phone's Blacksmiths tab
var order_strip: Container      # HBox; an HFlow on a phone
const MATS_HEIGHT := 300.0      # the row of player mats along the bottom
const QUEUE_LEN := 8            # crafting turns shown in the draft-order strip
const PHONE_QUEUE_LEN := 5

## Portrait windows (phones) get a single-column layout at this design size instead of
## 1920x1080: 640 px across a ~390 pt phone keeps 72 px taps near 44 pt and text readable.
const DESK_SIZE := Vector2i(1920, 1080)
const PHONE_SIZE := Vector2i(640, 1136)
const PHONE_TABS := [["table", "Table"], ["players", "Blacksmiths"]]
var phone := false             # single-column layout; picked from the window shape in _ready
var layout_forced := ""        # "phone" / "desktop" from --phone, --desktop or ?layout= (web)
var phone_tab := "table"       # page shown on a phone
var phone_pages := {}          # tab key -> page Control
var tab_buttons := {}          # tab key -> Button
var phone_turn := ""           # last decision seen, to jump back to the Table for a human
var top_bar: VBoxContainer     # phone: quest title and Menu, above the tabs
var header: VBoxContainer
var action_box: VBoxContainer
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
var flight_gen := 0            # bumped when the board is rebuilt, so stale flights don't touch `flights`
var roll_pending := false      # roll sound/haptic waiting for the overlay to close


var board_margin: MarginContainer
var persist := false           # autosave to FoSave (off for tests and --autoplay)
var saved := []                # [moves, seen] last written, to skip identical saves
var resume := []               # [FoGame, seen] from the save file, for the title screen
var menu := ""                 # open menu page: pause, settings, rules, restart ("" = none)
var menu_back := ""            # page that settings / rules return to
var handoff := -1              # human seat the device should be passed to, -1 = none
var last_human := -1           # human seat that last had a decision
var on_title := false          # the main menu is showing (vs seat setup or a game)
var touching := false          # last pointer input was a touch: no hover effects
var peek: Control              # full-size preview of a hovered mat card (mouse only)
const HOLD_TIME := 0.45         # long press on a card opens its zoom
const HOLD_SLOP := 16.0         # moving further than this (e.g. scrolling) cancels a hold
const LIFT := 1.06              # hovered cards grow this much

const TITLE_ART := "res://assets/images/challenges/HydraChopBIGB.png"
const TITLE_INK := Color("#E6D4B2")   # the prototype's start-screen palette
const TITLE_RED := Color("#9A2B2B")
const TITLE_DARK := Color("#3C3426")
const TITLE_EDGE := Color("#2B1D14")


func _ready() -> void:
	FoSettings.load_file()
	persist = not autoplay
	theme = FoUI.make_theme()
	_setup_audio()
	layout_forced = _forced_layout()
	phone = _want_phone()
	_apply_layout_size()
	get_viewport().size_changed.connect(_on_resize)
	data = CardData.load_default()
	if autoplay or "--start" in OS.get_cmdline_user_args():
		_show_setup()
	else:
		_show_title()
	if autoplay:
		for row in seat_rows:
			row[2].button_pressed = true
	if autoplay or "--start" in OS.get_cmdline_user_args():
		_start_game()


## Keep the board clear of the notch and home indicator (iOS). Desktop reports the menu bar
## and dock as unsafe, so insets only apply on mobile.
func _apply_safe_area() -> void:
	if board_margin == null:
		return
	var insets := [0.0, 0.0, 0.0, 0.0]  # left, top, right, bottom in canvas units
	if OS.has_feature("mobile") and is_inside_tree():
		var win := DisplayServer.window_get_size()
		var safe := DisplayServer.get_display_safe_area()
		var vp := get_viewport_rect().size
		if win.x > 0 and win.y > 0 and safe.size.x > 0:
			var k := Vector2(vp.x / win.x, vp.y / win.y)
			insets = [safe.position.x * k.x, safe.position.y * k.y,
				maxf(0, win.x - safe.end.x) * k.x, maxf(0, win.y - safe.end.y) * k.y]
	var sides := ["left", "top", "right", "bottom"]
	for i in 4:
		board_margin.add_theme_constant_override("margin_" + sides[i], 16 + int(insets[i]))


## `--phone` / `--desktop` on the command line, or `?layout=phone|desktop` in the page URL.
func _forced_layout() -> String:
	var args := OS.get_cmdline_user_args()
	if "--phone" in args:
		return "phone"
	if "--desktop" in args:
		return "desktop"
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('layout') || ''", true)
		if q is String and q in ["phone", "desktop"]:
			return q
	return ""


func _want_phone() -> bool:
	if layout_forced != "":
		return layout_forced == "phone"
	var win := DisplayServer.window_get_size()
	return win.y > win.x


func _apply_layout_size() -> void:
	if is_inside_tree():
		get_tree().root.content_scale_size = PHONE_SIZE if phone else DESK_SIZE


## Rotating a phone, or resizing a browser window past square, swaps layouts.
func _on_resize() -> void:
	_apply_safe_area()
	var want := _want_phone()
	if want == phone:
		return
	phone = want
	_apply_layout_size()
	_rebuild_screen()


## Narrowest width the current layout is drawn at (the window can be wider, never narrower).
func _view_w() -> float:
	return float(PHONE_SIZE.x if phone else DESK_SIZE.x)


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
	if roll_pending and not _blocking():
		roll_pending = false
		_play("roll")
		_haptic(40)
	if tumble_left > 0 and not _blocking():
		_tumble(delta)
	if game == null or game.phase == FoGame.Phase.GAME_OVER or not game.player().is_bot or _busy():
		return
	if bot_plan == null or bot_plan.g != game or bot_plan.stale() or bot_plan.pi != game.current:
		var c: Dictionary = cpu[game.current] if game.current < cpu.size() else {}
		bot_plan = FoBot.plan(game, c.get("level", FoBot.Level.NORMAL), c.get("persona", ""))
	var decided := bot_plan.advance(INF if autoplay else THINK_MS)
	bot_wait -= delta
	if bot_wait > 0 or not decided:
		return
	bot_wait = 0.0 if autoplay else FoSettings.cpu_delay()
	game.play_move(bot_plan.move)
	bot_plan = null
	_refresh()


# ------------------------------------------------------------------ setup screen

## Main menu, after the prototype's start screen: the Hydra art under a warm tint, a grid of
## buttons, and the title below. New game opens the seat setup (`_show_setup`).
func _show_title() -> void:
	_leave_game()
	on_title = true
	_clear(self)
	var art := TextureRect.new()
	art.texture = load(TITLE_ART)
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(art)
	var tint := ColorRect.new()
	tint.color = Color(0.17, 0.11, 0.08, 0.4)
	tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(tint)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_top", 150)
	margin.add_theme_constant_override("margin_bottom", 60)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 24)
	margin.add_child(col)
	var grid := GridContainer.new()
	grid.columns = 1 if phone else 2
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 20)
	col.add_child(grid)
	grid.add_child(_menu_button("New game", TITLE_RED, func():
		_play("toggle")
		_haptic(30)
		_show_setup(), false))
	var cont := _menu_button("Continue", TITLE_DARK, func():
		_play("challenge")
		_enter_game(resume[0], resume[1], resume[2]), false)
	cont.disabled = resume.is_empty()
	grid.add_child(cont)
	grid.add_child(_menu_button("How to play", TITLE_DARK, func(): _open_menu("rules")))
	grid.add_child(_menu_button("Settings", TITLE_DARK, func(): _open_menu("settings")))
	if not resume.is_empty():
		var g: FoGame = resume[0]
		var who: Array = g.players.map(func(p): return p.name)
		var where := _title_text("Saved: Quest %d of 3 with %s" % [g.quest + 1, ", ".join(who)], FoUI.BODY_FONT, 20)
		col.add_child(where)
	var mid := CenterContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(mid)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 12)
	mid.add_child(titles)
	if phone:  # stacked, so the title fits across; the width lets the wrapping labels lay out
		titles.custom_minimum_size.x = _view_w() - 64
		titles.add_child(_title_text("FIRES OF\nOLYMPUS", FoUI.HEADING_FONT, 64, 3))
		titles.add_child(_title_text("A dice-based drafter crafter game", FoUI.BODY_FONT, 24, 2))
	else:
		titles.add_child(_title_text("FIRES OF OLYMPUS", FoUI.HEADING_FONT, 96, 4))
		titles.add_child(_title_text("A dice-based drafter crafter game", FoUI.BODY_FONT, 32, 2))
	if not data.errors.is_empty():
		col.add_child(FoUI.label("Card data problems:\n" + "\n".join(data.errors), 18, FoUI.RED))
	_add_overlay()


## Cream text with a hard drop shadow, readable over the title art.
func _title_text(text: String, font_file: String, size: int, shadow := 2) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", FoAssets.font(font_file))
	l.add_theme_font_size_override("font_size", FoUI.fs(size))
	l.add_theme_color_override("font_color", TITLE_INK)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", shadow)
	l.add_theme_constant_override("shadow_offset_y", shadow)
	l.add_theme_constant_override("shadow_outline_size", shadow * 2)
	if phone:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## A title-screen button in the prototype's colours: filled, dark border, cream caps.
func _menu_button(text: String, color: Color, f: Callable, click_sound := true) -> Button:
	var b := _button(text.to_upper(), f, click_sound)
	b.custom_minimum_size = Vector2(340, TOUCH)
	b.add_theme_font_override("font", FoAssets.font(FoUI.BOLD_FONT))
	b.add_theme_font_size_override("font_size", FoUI.fs(24))
	var styles := {"normal": color, "hover": color.lightened(0.15), "pressed": color.darkened(0.2),
		"focus": color, "disabled": color.darkened(0.3)}
	for st in styles:
		var sb := FoUI.box(styles[st], TITLE_EDGE if st != "hover" else TITLE_INK, 2, 8, 10)
		b.add_theme_stylebox_override(st, sb)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, TITLE_INK)
	b.add_theme_color_override("font_disabled_color", Color(TITLE_INK, 0.4))
	return b


## Back to no game: used by the title and setup screens.
func _leave_game() -> void:
	_reset_flights()
	game = null
	action_box = null
	overlay = null
	menu = ""
	zoom = {}
	resume = FoSave.read(data) if persist else []


## Seat setup: who plays, which seats are CPUs.
func _show_setup() -> void:
	_leave_game()
	on_title = false
	_clear(self)
	add_child(FoUI.background())
	var scroll := ScrollContainer.new()  # only scrolls with 4 seats at large text sizes
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var pnl := FoUI.panel(FoUI.box(FoUI.PANEL, FoUI.GOLD, 2, 16, 32))
	center.add_child(pnl)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	if phone:
		pnl.add_theme_stylebox_override("panel", FoUI.box(FoUI.PANEL, FoUI.GOLD, 2, 16, 20))
		box.custom_minimum_size.x = _view_w() - 32 - 40
	pnl.add_child(box)
	var title := FoUI.heading("New game", 56, FoUI.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.add_child(FoUI.heading("Blacksmiths", 24, FoUI.INK, false))
	count_row = _choice(range(2, MAX_PLAYERS + 1).map(func(n): return str(n)), player_count - 2, func(i): _set_player_count(i + 2))
	row.add_child(count_row)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap)
	var rules := _button("How to play", func(): _open_menu("rules"))
	box.add_child(row)
	if phone:
		box.add_child(rules)
	else:
		row.add_child(rules)
	seat_rows.clear()
	for i in MAX_PLAYERS:
		var seat := VBoxContainer.new()
		seat.add_theme_constant_override("separation", 2 if not phone else 6)
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 12)
		var name_edit := LineEdit.new()
		name_edit.custom_minimum_size = Vector2(300, TOUCH)
		if phone:  # name on its own line, CPU options under it
			name_edit.custom_minimum_size.x = 0
			seat.add_child(name_edit)
		var is_cpu := CheckBox.new()
		is_cpu.text = "CPU"
		is_cpu.custom_minimum_size.y = TOUCH
		var persona := OptionButton.new()
		for pd in FoBot.PERSONAS:
			persona.add_item(pd.name)
		persona.select(i % FoBot.PERSONAS.size())
		persona.custom_minimum_size = Vector2(190, TOUCH)
		var level := OptionButton.new()
		for l in FoBot.LEVELS:
			level.add_item(l)
		level.select(FoBot.Level.NORMAL)
		level.custom_minimum_size = Vector2(150, TOUCH)
		var blurb := FoUI.label("", 16, FoUI.MUTED, phone)
		if not phone:
			r.add_child(name_edit)
		r.add_child(is_cpu)
		r.add_child(persona)
		r.add_child(level)
		seat.add_child(r)
		seat.add_child(blurb)
		box.add_child(seat)
		seat_rows.append([seat, name_edit, is_cpu, persona, level, blurb])
		is_cpu.button_pressed = i > 0
		is_cpu.toggled.connect(func(_on): _update_seat(i, true))
		persona.item_selected.connect(func(_idx): _update_seat(i, true))
		_update_seat(i, true)
	var go := HBoxContainer.new()
	go.add_theme_constant_override("separation", 16)
	var back := _title_button("Back", _show_title)
	back.custom_minimum_size.x = 140 if phone else 220
	go.add_child(back)
	var begin := _title_button("Begin the Quests", _start_game)
	begin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	begin.add_theme_stylebox_override("normal", FoUI.box(TITLE_RED, FoUI.GOLD, 2, 8, 10))
	go.add_child(begin)
	box.add_child(go)
	if not resume.is_empty():
		var note := FoUI.label("Beginning a new game replaces the saved one.", 18, FoUI.MUTED)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(note)
	_update_seats()
	_add_overlay()


func _title_button(text: String, f: Callable) -> Button:
	var b := _button(text, f)
	b.custom_minimum_size.y = TOUCH
	b.add_theme_font_override("font", FoAssets.font(FoUI.HEADING_FONT))
	b.add_theme_font_size_override("font_size", FoUI.fs(28))
	return b


func _set_player_count(n: int) -> void:
	player_count = clampi(n, 2, MAX_PLAYERS)
	if count_row != null:
		count_row.get_child(player_count - 2).button_pressed = true
	_update_seats()


func _update_seats() -> void:
	for i in seat_rows.size():
		seat_rows[i][0].visible = i < player_count


## Show or hide a seat's CPU options. rename: swap a default name for the persona's name (or back).
func _update_seat(i: int, rename: bool) -> void:
	var row: Array = seat_rows[i]
	var on: bool = row[2].button_pressed
	var pd: Dictionary = FoBot.PERSONAS[row[3].selected]
	row[3].visible = on
	row[4].visible = on
	row[5].visible = on
	row[5].text = pd.blurb
	var current: String = row[1].text.strip_edges()
	var defaults: Array = DEFAULT_NAMES + FoBot.PERSONAS.map(func(x): return x.name)
	if rename and (current == "" or current in defaults):
		row[1].text = pd.name if on else DEFAULT_NAMES[i]


func _start_game() -> void:
	var names := []
	var bots := []
	var cpus := []
	for i in player_count:
		var row: Array = seat_rows[i]
		var n: String = row[1].text.strip_edges()
		names.append(n if n != "" else "Player %d" % (i + 1))
		bots.append(row[2].button_pressed)
		cpus.append({"level": row[4].selected, "persona": FoBot.PERSONAS[row[3].selected].key} if row[2].button_pressed else {})
	_new_game(names, bots, cpus)


func _new_game(names: Array, bots: Array, cpus: Array) -> void:
	var g := FoGame.new(data)
	g.setup(names, bots, randi())
	_enter_game(g, 0, cpus)
	_play("start")


## Show `g` on the board. `seen`: history entries already dismissed (from a save).
## `cpus`: per seat {level, persona} for CPUs; missing entries play at Normal.
func _enter_game(g: FoGame, seen: int, cpus: Array = []) -> void:
	game = g
	cpu = []
	for i in g.players.size():
		var c: Dictionary = cpus[i] if i < cpus.size() and cpus[i] is Dictionary else {}
		if g.players[i].is_bot and c.is_empty():
			c = {"level": FoBot.Level.NORMAL, "persona": ""}
		cpu.append(c if g.players[i].is_bot else {})
	bot_plan = null
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
	roll_pending = false
	overlay_key = ""
	_build_board()


# ------------------------------------------------------------------ board

func _build_board() -> void:
	_reset_flights()
	_clear(self)
	add_child(FoUI.background())
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	board_margin = margin
	_apply_safe_area()
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	if phone:
		_build_phone_board(root)
	else:
		_build_desk_board(root)

	fx_layer = Control.new()
	fx_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fx_layer)
	_add_overlay()
	_refresh()


func _build_desk_board(root: VBoxContainer) -> void:
	top_bar = null
	phone_pages = {}
	tab_buttons = {}
	var mid := VBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
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

	# the table edge: turn order, then each Blacksmith's mat in that order
	order_strip = HBoxContainer.new()
	order_strip.add_theme_constant_override("separation", 8)
	root.add_child(order_strip)
	var bottom := ScrollContainer.new()
	bottom.custom_minimum_size.y = MATS_HEIGHT
	bottom.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	players_box = HBoxContainer.new()
	players_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	players_box.add_theme_constant_override("separation", 12)
	bottom.add_child(players_box)
	root.add_child(bottom)


## Phone: title bar, turn order, then one page at a time: the Table (Challenges and the
## current decision) or the Blacksmiths (every mat, stacked).
func _build_phone_board(root: VBoxContainer) -> void:
	top_bar = VBoxContainer.new()
	root.add_child(top_bar)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 4)
	order_strip = flow
	root.add_child(order_strip)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	root.add_child(tabs)
	var group := ButtonGroup.new()
	tab_buttons = {}
	for t in PHONE_TABS:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size.y = TOUCH
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func():
			_play("toggle")
			_show_tab(t[0]))
		tabs.add_child(b)
		tab_buttons[t[0]] = b

	var table := _page_scroll()
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", 12)
	header = VBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	tv.add_child(header)
	action_box = VBoxContainer.new()
	action_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_box.add_theme_constant_override("separation", 12)
	tv.add_child(action_box)
	table.add_child(tv)

	var mats := _page_scroll()
	players_box = VBoxContainer.new()
	players_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	players_box.add_theme_constant_override("separation", 12)
	mats.add_child(players_box)
	phone_pages = {"table": table, "players": mats}
	for k in phone_pages:
		root.add_child(phone_pages[k])
	_show_tab(phone_tab)


func _page_scroll() -> ScrollContainer:
	var s := ScrollContainer.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	return s


func _show_tab(tab: String) -> void:
	phone_tab = tab
	for k in phone_pages:
		phone_pages[k].visible = k == tab
	for k in tab_buttons:
		tab_buttons[k].set_pressed_no_signal(k == tab)


## On a phone, jump to the Table whenever a human has a new decision to make.
func _follow_turn() -> void:
	if not phone or phone_pages.is_empty():
		return
	var key := "%d:%d:%d" % [game.quest, game.current, game.phase]
	if key == phone_turn:
		return
	phone_turn = key
	if game.phase == FoGame.Phase.GAME_OVER or not game.player().is_bot:
		_show_tab("table")


func _add_overlay() -> void:
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	_render_overlay()


func _refresh() -> void:
	if game == null or action_box == null:
		return
	var old_cards := _card_rects()
	_hide_peek()
	_play_events()
	_sync_history()
	_autosave()
	_check_handoff()
	_follow_turn()
	card_nodes = {}
	_render_players()
	_render_header()
	_render_actions()
	_render_overlay()
	_queue_flights(old_cards)


func _render_header() -> void:
	_clear(header)
	var bar: Container = top_bar if phone and top_bar != null else header
	if bar != header:
		_clear(bar)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10 if phone else 16)
	var title := FoUI.heading("Quest %d of 3" % mini(game.quest + 1, 3), 26 if phone else 34, FoUI.GOLD, false)
	if phone:
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.clip_text = true
	top.add_child(title)
	var phase_name := _phase_name()
	if phase_name != "":
		var c := FoUI.chip(phase_name, FoUI.INK, 16 if phone else 18)
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(c)
	if not phone:
		var gap := Control.new()
		gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(gap)
	var menu_button := Button.new()
	menu_button.text = "Menu"
	menu_button.custom_minimum_size = Vector2(110 if phone else 140, TOUCH)
	menu_button.pressed.connect(func():
		_play("menu")
		_open_menu("pause"))
	top.add_child(menu_button)
	bar.add_child(top)
	var row: BoxContainer = VBoxContainer.new() if phone else HBoxContainer.new()
	row.add_theme_constant_override("separation", 10 if phone else 14)
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
		row.add_child(FoUI.picture(tex, 84 if phone else 120, true))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 4)
	text.add_child(FoUI.label("%s Challenge  ·  %s" % [card.kind, card.type], 15 if phone else 16, accent))
	text.add_child(FoUI.heading(card.name, 22 if phone else 26, FoUI.GOLD if active else FoUI.INK))
	text.add_child(FoUI.label(card.rule, 17 if phone else 18))
	row.add_child(text)
	_zoomable(pnl, card, true)
	return pnl


# ------------------------------------------------------------------ player mats

func _render_players() -> void:
	_clear(players_box)
	for pi in _seat_order():
		var m := _player_mat(pi)
		m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		m.size_flags_stretch_ratio = 1.0
		players_box.add_child(m)
	_render_order()


## Seats in this Quest's turn order (setup order before it's rolled).
func _seat_order() -> Array:
	return Array(game.order) if game.order.size() == game.players.size() else range(game.players.size())


## The strip above the mats. Crafting: the snake draft's next turns, current first, with a
## turn-around mark where the snake reverses. Challenges and reserving go once round in
## turn order: done seats dim, the current one is lit.
func _render_order() -> void:
	_clear(order_strip)
	if game.phase == FoGame.Phase.GAME_OVER:
		return
	var crafting := game.phase in [FoGame.Phase.CRAFT, FoGame.Phase.SWAP]
	var title := FoUI.label("Draft order" if crafting else "Turn order", 18, FoUI.MUTED, false)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	order_strip.add_child(title)
	if crafting:
		var n := PHONE_QUEUE_LEN if phone else QUEUE_LEN
		var queue := game.craft_queue(n)
		for i in queue.size():
			if i > 0:
				var turn: bool = queue[i].round != queue[i - 1].round
				order_strip.add_child(_order_arrow("↩" if turn else "›", turn))
			order_strip.add_child(_order_chip(queue[i].player, i == 0, false))
		if queue.size() == n:
			order_strip.add_child(_order_arrow("…", false))
		return
	var order := _seat_order()
	var at := order.find(game.current)
	for i in order.size():
		if i > 0:
			order_strip.add_child(_order_arrow("›", false))
		order_strip.add_child(_order_chip(order[i], i == at, i < at))


func _order_chip(pi: int, now: bool, done: bool) -> Control:
	var p = game.players[pi]
	var color := FoUI.GOLD if now else (FoUI.MUTED if done else FoUI.INK)
	var c := FoUI.panel(FoUI.box(FoUI.PANEL_LIGHT if now else FoUI.PANEL.darkened(0.25),
		FoUI.GOLD if now else FoUI.EDGE, 2 if now else 1, 12, 0))
	var st: StyleBoxFlat = c.get_theme_stylebox("panel")
	st.content_margin_left = 12
	st.content_margin_right = 12
	st.content_margin_top = 3
	st.content_margin_bottom = 3
	c.add_child(FoUI.label(("▶ " if now else "") + p.name, 18, color, false))
	if done:
		c.modulate.a = 0.6
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return c


func _order_arrow(text: String, turn: bool) -> Label:
	var l := FoUI.label(text, 22 if turn else 20, FoUI.GOLD if turn else FoUI.MUTED, false)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if turn:
		l.tooltip_text = "Snake draft: the order reverses each round"
	return l


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
	var seat := _seat_order().find(pi)
	var badge := FoUI.chip(["1st", "2nd", "3rd", "4th"][seat] if seat >= 0 and seat < 4 else "", FoUI.GOLD if active else FoUI.MUTED, 16)
	badge.tooltip_text = "Turn order this Quest"
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(badge)
	var name_label := FoUI.heading(p.name, 24, FoUI.GOLD if active else FoUI.INK, false)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	top.add_child(name_label)
	if p.is_bot:
		var c: Dictionary = cpu[pi] if pi < cpu.size() else {}
		var chip := FoUI.chip("CPU · %s" % FoBot.LEVELS[c.get("level", FoBot.Level.NORMAL)], FoUI.MUTED, 14)
		if c.get("persona", "") != "":
			chip.tooltip_text = FoBot.persona(c.persona).blurb
		top.add_child(chip)
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
	elif p.penalty.get("free_six", 0) > 0:
		v.add_child(FoUI.label("Boon: " + Scoring.describe_penalty(p.penalty), 17, FoUI.GOLD))

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
		if not t.get_meta("held", false):
			_play("zoom")
			_open_zoom(c, false))
	_card_feel(t, c, true)
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
			var row := _button_row()
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
	var row := _button_row()
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
		var row: Container = VBoxContainer.new() if phone else HFlowContainer.new()
		row.add_theme_constant_override("separation" if phone else "h_separation", 8)
		for r in reactions:
			var verb: String = {"reroll": "Reroll a die", "plus_one": "+1 to a die", "keep": "Keep a die for Sharpness", "copy": "Copy a die"}[r.kind]
			var b := _button("%s: %s (%d left)" % [r.card, verb, r.left], func(): selected_reaction = r.key)
			if phone:  # full width, wrapping, so long card names never run off the screen
				b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
		var b := FoUI.die_face(v, 0 if tumbling else marks[i], d.magic, d.carried, 80 if phone else 84, clickable and i == selected_die)
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
	var legend := _marks_legend(marks, game.challenge_kind, p.dice)
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
	action_box.add_child(FoUI.heading("%s win%s!" % [" & ".join(names), "" if names.size() > 1 else "s"], 36 if phone else 48, FoUI.GOLD))
	for pi in ranked:
		var p = game.players[pi]
		var row: Container = HFlowContainer.new() if phone else HBoxContainer.new()
		row.add_theme_constant_override("h_separation" if phone else "separation", 16)
		var winner: bool = pi in game.winners()
		var n := FoUI.heading(p.name, 24 if phone else 30, FoUI.GOLD if winner else FoUI.INK, false)
		n.custom_minimum_size.x = 170 if phone else 280
		row.add_child(n)
		row.add_child(FoUI.label(FoGame.successes_text(p.total), 22 if phone else 28, FoUI.GOLD if winner else FoUI.INK, false))
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
	_hide_peek()
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
	var pnl := FoUI.panel(FoUI.box(FoUI.PANEL, FoUI.GOLD, 2, 14, 20 if phone else 26))
	pnl.custom_minimum_size.x = minf(width, _view_w() - 32)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	pnl.add_child(box)
	return [pnl, box]


func _zoom_panel() -> Control:
	var card: Dictionary = zoom.card
	var pb := _overlay_panel(1200)
	var row: BoxContainer = VBoxContainer.new() if phone else HBoxContainer.new()  # art above the text on a phone
	row.add_theme_constant_override("separation", 16 if phone else 28)
	pb[1].add_child(row)
	var info: Dictionary = card if zoom.challenge else data.ingredient(card.name)
	var tex := FoAssets.challenge_art(info) if zoom.challenge else FoAssets.ingredient_art(info)
	if tex != null:
		var pic := FoUI.picture(tex, 320 if phone else 440, true)
		pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		row.add_child(pic)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 12 if phone else 16)
	row.add_child(text)
	text.add_child(FoUI.heading(info.get("name", card.name), 34 if phone else 44, FoUI.GOLD))
	if zoom.challenge:
		text.add_child(FoUI.label("%s Challenge  ·  %s" % [info.kind, info.type], 20 if phone else 24, FoUI.MUTED))
		text.add_child(FoUI.label(info.rule, 22 if phone else 26))
	else:
		text.add_child(FoUI.label("Ingredient", 20 if phone else 24, FoUI.MUTED))
		text.add_child(FoUI.label(info.get("text", ""), 22 if phone else 26))
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
	box.add_child(FoUI.heading(card.name, 32 if phone else 40, FoUI.GOLD))
	box.add_child(FoUI.label(card.rule, 18 if phone else 20))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = mini(620, 190 * entry.rows.size()) if phone else mini(560, 110 * entry.rows.size())
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 18)
	scroll.add_child(rows)
	var all_marks: Array[int] = []
	var all_dice := []
	for r in entry.rows:
		# desktop: name | dice | result in one row; phone: name, dice, result stacked
		var row: BoxContainer = VBoxContainer.new() if phone else HBoxContainer.new()
		row.add_theme_constant_override("separation", 6 if phone else 16)
		rows.add_child(row)
		var who := FoUI.heading(game.players[r.player].name, 24, FoUI.INK, false)
		who.custom_minimum_size.x = 0 if phone else 220
		row.add_child(who)
		var dice := HFlowContainer.new()
		dice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dice.add_theme_constant_override("h_separation", 8)
		dice.add_theme_constant_override("v_separation", 8)
		row.add_child(dice)
		for d in r.dice:
			all_marks.append(d.mark)
			all_dice.append(d)
			var b := FoUI.die_face(d.value, d.mark, d.magic, d.carried, 72 if phone else 64)
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
			color = FoUI.GOLD if Scoring.penalty_cost(r.penalty) <= 0 else FoUI.RED
		var res := FoUI.label(outcome, 20 if phone else 22, color)
		res.custom_minimum_size.x = 0 if phone else 420
		row.add_child(res)
	var legend := _marks_legend(all_marks, entry.kind, all_dice)
	if legend != "":
		box.add_child(FoUI.label(legend, 16, FoUI.MUTED))
	results_detail = FoUI.label("Tap a die to see how its value was worked out.", 18, FoUI.MUTED)
	box.add_child(results_detail)
	if entry.kind == FoGame.STRENGTH:
		var what := "The boon applies" if entry.card.name == "Fiery Salamander" else "Penalties apply"
		box.add_child(FoUI.label("%s to this Quest's Sharpness Challenge." % what, 18, FoUI.MUTED))
	box.add_child(_big_button("Continue", _dismiss_results))
	return pb[0]


func _quest_results(entry: Dictionary) -> Control:
	var pb := _overlay_panel(1100)
	var box: VBoxContainer = pb[1]
	box.add_child(FoUI.heading("Quest %d complete" % (entry.quest + 1) + (": final standings" if entry.final else ""), 32 if phone else 40, FoUI.GOLD))
	var rows: Array = entry.rows.duplicate()
	rows.sort_custom(func(a, b): return a.total > b.total)
	var best: int = rows[0].total
	var grid := GridContainer.new()
	grid.columns = 3 if phone else 4  # a phone puts the wager note under "This Quest"
	grid.add_theme_constant_override("h_separation", 20 if phone else 40)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)
	for h in (["Blacksmith", "This Quest", "Total"] if phone else ["Blacksmith", "This Quest", "", "Total"]):
		grid.add_child(FoUI.label(h, 18 if phone else 20, FoUI.MUTED, false))
	for r in rows:
		var leader: bool = r.total == best
		var wager: String = "" if r.wager == 0 else "(%d from Challenge, wager %+d)" % [r.challenge, r.wager]
		var cells := [game.players[r.player].name, FoGame.successes_text(r.score), wager, str(r.total)]
		if phone:
			cells = [cells[0], cells[1] + ("" if wager == "" else "\n" + wager), cells[3]]
		for c in cells:
			grid.add_child(FoUI.label(c, 22 if phone else 26, FoUI.GOLD if leader else FoUI.INK, false))
	if not entry.final:
		box.add_child(FoUI.label("Next: everyone reserves an Ingredient, then whoever scored the fewest Successes this Quest drafts first.", 20, FoUI.MUTED))
	box.add_child(_big_button("Continue", _dismiss_results))
	return pb[0]


func _dismiss_results() -> void:
	if not results_queue.is_empty():
		results_queue.pop_front()


## Explains the die symbols on show. `dice`: FoGame.Die objects or history dice dicts.
func _marks_legend(marks: Array[int], kind: String, dice: Array) -> String:
	var parts := PackedStringArray()
	if 1 in marks:
		parts.append("%s Gold border: %s" % [FoUI.MARK_GOOD, "scores a Success" if kind == FoGame.SHARPNESS else "protects you from the penalty (or earns the boon)"])
	if -1 in marks:
		parts.append("%s Red border: triggers the penalty" % FoUI.MARK_BAD)
	if dice.any(func(d): return d.magic):
		parts.append("%s Magic die (Sphinx's Milk)" % FoUI.MARK_MAGIC)
	if dice.any(func(d): return d.carried):
		parts.append("%s %s" % [FoUI.MARK_KEPT, "Kept for Sharpness" if kind == FoGame.STRENGTH else "Kept from Strength"])
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
		FoSave.write(game, state[1], cpu)


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
	var title := FoUI.heading("Pass to %s" % p.name, 40 if phone else 56, FoUI.GOLD)
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
	box.add_child(_big_button("Quit to title", _show_title))
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
		_new_game(game.players.map(func(p): return p.name), game.players.map(func(p): return p.is_bot), cpu)))
	row.add_child(_big_button("Cancel", func(): _open_menu("pause")))
	box.add_child(row)
	return pb[0]


func _settings_panel() -> Control:
	var pb := _overlay_panel(860)
	var box: VBoxContainer = pb[1]
	box.add_child(FoUI.heading("Settings", 40, FoUI.GOLD))
	var grid := GridContainer.new()
	grid.columns = 1 if phone else 2  # a phone puts each label above its control
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 8 if phone else 18)
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
	if OS.has_feature("mobile") or DisplayServer.is_touchscreen_available():
		_setting_row(grid, "Haptics", _toggle("Vibrate on rolls and drafts", FoSettings.haptics, func(on):
			FoSettings.haptics = on
			_save_settings()))
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
	sl.custom_minimum_size = Vector2(0 if phone else 420, 44)
	if phone:
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
		b.custom_minimum_size = Vector2(maxf(TOUCH, 132 if options[i].length() > 2 else 0), TOUCH)
		b.pressed.connect(func():
			_play("toggle")
			f.call(i)
			_save_settings())
		row.add_child(b)
	return row


## Text size changes rebuild the current screen (keeping the setup screen's seats).
func _apply_text_size() -> void:
	theme = FoUI.make_theme()
	_rebuild_screen()


## Redraw whatever is showing, e.g. for a new text size or after switching phone / desktop layout.
func _rebuild_screen() -> void:
	if data == null:
		return
	if game != null:
		_build_board()
		return
	if on_title:
		var title_page := menu
		_show_title()
		menu = title_page
		_render_overlay()
		return
	var page := menu
	var back := menu_back
	var seats := seat_rows.map(func(r): return [r[1].text, r[2].button_pressed, r[3].selected, r[4].selected])
	_show_setup()
	for i in seats.size():
		seat_rows[i][2].button_pressed = seats[i][1]
		seat_rows[i][3].select(seats[i][2])
		seat_rows[i][4].select(seats[i][3])
		_update_seat(i, false)
		seat_rows[i][1].text = seats[i][0]
	menu = page
	menu_back = back
	_render_overlay()


func _rules_panel() -> Control:
	var pb := _overlay_panel(1240)
	var box: VBoxContainer = pb[1]
	box.add_child(FoUI.heading("How to play", 40, FoUI.GOLD))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = PHONE_SIZE.y - 340 if phone else 700
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 8)
	for sec in FoRulesText.SECTIONS:
		text.add_child(FoUI.heading(sec[0], 24, FoUI.GOLD))
		var body := FoUI.label(sec[1], 19 if phone else 21)
		body.custom_minimum_size.x = _view_w() - 32 - 40 - 40 if phone else 1140
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
		if is_instance_valid(n) and n.is_inside_tree() and n.is_visible_in_tree():  # not on a hidden phone tab
			out[id] = [card_nodes[id][0], n.get_global_rect()]
	return out


## Cards that changed zone since the last render (table -> mat, mat -> mat, reserve -> mat)
## fly from where they were. The new card stays invisible until its copy lands.
func _queue_flights(old: Dictionary) -> void:
	if not _animate():
		return
	var moves := []
	for id in card_nodes:
		if old.has(id) and old[id][0] != card_nodes[id][0] and card_nodes[id][1].is_visible_in_tree():
			var target: Control = card_nodes[id][1]
			target.modulate.a = 0.0
			moves.append([target, old[id][1], card_nodes[id][2]])
	if moves.is_empty():
		return
	flights += moves.size()
	_launch_flights(moves, flight_gen)


## Drop cards in the air (their ghosts go with the old fx_layer) so CPU turns don't wait on them.
func _reset_flights() -> void:
	flight_gen += 1
	flights = 0


func _launch_flights(moves: Array, gen: int) -> void:
	# wait for containers to lay out the new nodes so their positions are final
	await get_tree().process_frame
	await get_tree().process_frame
	for m in moves:
		if gen != flight_gen:
			return
		var target = m[0]
		if not is_instance_valid(target) or not target.is_inside_tree() or not is_instance_valid(fx_layer):
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
		# bound to the ghost, so the tween dies with it if the board is rebuilt mid-flight
		var tw := ghost.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(ghost, "global_position", to.position, FLIGHT_TIME)
		tw.tween_property(ghost, "scale", Vector2.ONE, FLIGHT_TIME)
		tw.chain().tween_callback(func():
			ghost.queue_free()
			if is_instance_valid(target):
				target.modulate.a = 1.0
			if gen == flight_gen:
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
	b.custom_minimum_size.y = TOUCH
	b.pressed.connect(func():
		if click_sound:
			_play("click")
		_act(f))
	return b


func _big_button(text: String, f: Callable) -> Button:
	var b := _button(text, f)
	b.custom_minimum_size = Vector2(220, TOUCH)
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
	t.pressed.connect(func():
		if not t.get_meta("held", false):
			_act(f))
	_card_feel(t, card, false)
	var info := FoUI.corner_button(t, "i")
	info.pressed.connect(func():
		_play("zoom")
		_open_zoom(card, false))
	return t


## Hover lifts a card (and a mat card shows a full-size preview); holding a card opens its
## zoom, the touch stand-in for hover. After a hold the release doesn't count as a tap.
func _card_feel(t: Control, card: Dictionary, preview: bool) -> void:
	t.mouse_entered.connect(func():
		if touching:
			return
		_lift(t, true)
		_play("hover")
		if preview:
			_show_peek(t, card))
	t.mouse_exited.connect(func():
		_lift(t, false)
		_hide_peek())
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = HOLD_TIME
	t.add_child(timer)
	var start := [Vector2.ZERO]
	timer.timeout.connect(func():
		t.set_meta("held", true)
		_lift(t, false)
		_hide_peek()
		_haptic(25)
		_play("zoom")
		_open_zoom(card, false))
	t.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				t.set_meta("held", false)
				start[0] = ev.position
				if timer.is_inside_tree():
					timer.start()
			else:
				timer.stop()
		elif ev is InputEventMouseMotion and not timer.is_stopped() and ev.position.distance_to(start[0]) > HOLD_SLOP:
			timer.stop())


func _lift(t: Control, up: bool) -> void:
	if not is_instance_valid(t):
		return
	t.pivot_offset = t.size / 2
	t.z_index = 1 if up else 0
	var to := Vector2(LIFT, LIFT) if up else Vector2.ONE
	if _animate():
		t.create_tween().tween_property(t, "scale", to, 0.1)
	else:
		t.scale = to


## A mat card is too small to read, so hovering shows the full tile just above it.
func _show_peek(t: Control, card: Dictionary) -> void:
	_hide_peek()
	if fx_layer == null or not is_instance_valid(fx_layer) or not t.is_inside_tree():
		return
	peek = FoUI.card_tile(card.name, game.text_of(card), FoAssets.ingredient_art(data.ingredient(card.name)), FoUI.TILE, FoUI.GOLD)
	peek.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx_layer.add_child(peek)
	var r := t.get_global_rect()
	var view := get_viewport_rect().size
	var pos := Vector2(r.get_center().x - FoUI.TILE.x / 2, r.position.y - FoUI.TILE.y - 10)
	if pos.y < 0:
		pos.y = r.end.y + 10
	pos.x = clampf(pos.x, 8, view.x - FoUI.TILE.x - 8)
	peek.global_position = pos


func _hide_peek() -> void:
	if peek != null and is_instance_valid(peek):
		peek.queue_free()
	peek = null


## Emulated mouse events from a touch carry DEVICE_ID_EMULATION, so a real mouse turns hover back on.
func _input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch or ev is InputEventScreenDrag:
		touching = true
	elif ev is InputEventMouse and ev.device != InputEvent.DEVICE_ID_EMULATION:
		touching = false


## Big buttons side by side; they wrap to a second line on a phone.
func _button_row() -> Container:
	var row: Container = HFlowContainer.new() if phone else HBoxContainer.new()
	for k in (["h_separation", "v_separation"] if phone else ["separation"]):
		row.add_theme_constant_override(k, 12)
	return row


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
			_play("zoom")
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


## A short buzz on phones and tablets (iOS uses the Taptic Engine).
func _haptic(ms: int) -> void:
	if FoSettings.haptics and OS.has_feature("mobile") and not autoplay and is_inside_tree():
		Input.vibrate_handheld(ms, 0.5)


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
		"moves": game.moves.size(),
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
			_haptic(80)
		return
	if now.quest != was.quest:
		_play("quest_end")
	_play_moves(was.moves)
	var p := game.player()
	if now.current != was.current and not p.is_bot and now.phase != FoGame.Phase.REACT:
		_play("your_turn")  # (a roll has its own sound)
	for pi in now.ingredients.size():
		var cards: Array = now.ingredients[pi]
		if cards.size() > was.ingredients[pi].size():
			_play_file(FoAssets.ingredient_sound_path(cards[-1]), 0.6)
			_haptic(20)
		if now.sharpen[pi] > was.sharpen[pi]:
			_play("sharpen")
		if now.reserve[pi] > was.reserve[pi]:
			_play("reserve")
			_haptic(20)
	if now.phase == FoGame.Phase.REACT:
		if was.phase != FoGame.Phase.REACT or was.kind != now.kind:
			_play("challenge")
		if was.phase != FoGame.Phase.REACT or was.kind != now.kind or was.current != now.current:
			roll_pending = true  # played in _process once any overlay is dismissed, with the tumble
			if _animate():
				tumble_left = TUMBLE_TIME
				tumble_tick = 0.0
		elif was.dice != now.dice and not (game.moves.size() > was.moves and game.moves[-1][0] == "react"):
			_play("reaction")


## A sound for each move since the last redraw that the state diff above doesn't cover
## (drafts, sharpening and reserving already sound from the mats changing).
func _play_moves(since: int) -> void:
	var played := {}
	for i in range(since, game.moves.size()):
		var m: Array = game.moves[i]
		var event := ""
		match m[0]:
			"pass":
				event = "pass"
			"swap":
				event = "swap"
			"wager":
				event = "wager" if m[1] else ""
			"react":
				event = game.reaction_kind(m[1])
		if event != "" and FoAssets.SFX.has(event) and not played.has(event):
			played[event] = true
			_play(event)
			if event in ["swap", "wager"]:
				_haptic(20)
