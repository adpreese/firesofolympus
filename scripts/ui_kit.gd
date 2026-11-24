class_name FoUI
extends RefCounted
## The game's look: colours, the global Theme, and constructors for styled widgets
## (card tiles, dice, panels). Presentation only: no FoGame access, no game logic.

## Parchment palette, after the React Native prototype (design/prototype/notes.md):
## brown ink on tan and cream, thick dark outlines, flat fills; red = Strength and primary
## actions, navy = Sharpness, green = gains.
const INK := Color("#2B1D14")       # text, outlines, rules
const CREAM := Color("#E6D4B2")     # card faces, raised panels, text on coloured fills
const TAN := Color("#D1B88F")       # the table and ordinary panels
const OCHRE := Color("#C2A36B")     # the dice tray
const UMBER := Color("#3C3426")     # ordinary buttons
const OXBLOOD := Color("#9A2B2B")   # Strength, primary buttons, the current turn
const NAVY := Color("#2C4A82")      # Sharpness
const IVORY := Color("#FBF4DE")     # die faces

const GOLD := OXBLOOD               # accent: headings, the current turn, highlights
const RED := Color("#B3261E")       # penalties, Strength text
const GOOD := Color("#3F7A30")      # Successes, dice gained
const INK_LIGHT := CREAM            # text on OXBLOOD / NAVY / UMBER fills
const MUTED := Color("#6E5A43")     # secondary text (darker than the prototype's #8B7355 for contrast on tan)
const MAGIC := NAVY
const KEPT := Color("#8A5A10")
const RESERVE := GOOD
const PANEL := TAN
const PANEL_LIGHT := CREAM
const EDGE := INK
const BG_TOP := TAN
const BG_BOTTOM := Color("#C8AC7F")
const HEADING_FONT := "Cinzel-Bold.ttf"
const BODY_FONT := "SourceSerif4-Regular.ttf"
const BOLD_FONT := "SourceSerif4-SemiBold.ttf"

## Die symbols, so meaning never rests on colour alone (Source Serif has these glyphs).
const MARK_GOOD := "✓"
const MARK_BAD := "×"
const MARK_MAGIC := "◆"
const MARK_KEPT := "▲"

const TILE := Vector2(176, 240)  # market / choice cards
const MINI := Vector2(84, 104)   # cards on a player's mat


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = fs(22)
	t.default_font = FoAssets.font(BODY_FONT)
	t.set_color("font_color", "Label", INK)
	# Buttons: umber with cream text. Pressed / toggled on (a selected option) is cream with a
	# heavy outline, so a choice never looks like the oxblood call to action (`primary`).
	var states := {
		"normal": box(UMBER, INK, 2, 10),
		"hover": box(UMBER.lightened(0.14), INK, 2, 10),
		"pressed": box(CREAM, INK, 4, 10),
		"hover_pressed": box(CREAM.lightened(0.2), INK, 4, 10),
		"disabled": box(TAN.darkened(0.06), MUTED, 2, 10),
		"focus": StyleBoxEmpty.new(),
	}
	for s in states:
		t.set_stylebox(s, "Button", states[s])
	for c in ["font_color", "font_hover_color", "font_focus_color"]:
		t.set_color(c, "Button", CREAM)
	for c in ["font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(c, "Button", INK)
	t.set_color("font_disabled_color", "Button", MUTED)
	t.set_stylebox("normal", "LineEdit", box(CREAM, INK, 2, 8))
	t.set_stylebox("focus", "LineEdit", box(CREAM, OXBLOOD, 2, 8))
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", MUTED)
	t.set_color("caret_color", "LineEdit", INK)
	t.set_color("selection_color", "LineEdit", Color(OXBLOOD, 0.35))
	for state in ["", "_disabled"]:  # the default icons are dark: invisible on umber buttons
		t.set_icon("checked" + state, "CheckBox", _check_icon(true))
		t.set_icon("unchecked" + state, "CheckBox", _check_icon(false))
	t.set_stylebox("panel", "PanelContainer", box(PANEL, EDGE, 2))
	t.set_stylebox("panel", "PopupMenu", box(CREAM, INK, 2, 6))
	t.set_stylebox("hover", "PopupMenu", box(OXBLOOD, OXBLOOD, 0, 4))
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", CREAM)
	t.set_stylebox("panel", "TooltipPanel", box(CREAM, INK, 2, 8))
	t.set_color("font_color", "TooltipLabel", INK)
	for bar in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", bar, box(Color(INK, 0.12), INK, 0, 4))
		t.set_stylebox("grabber", bar, box(UMBER, UMBER, 0, 4))
		t.set_stylebox("grabber_highlight", bar, box(UMBER.lightened(0.14), UMBER, 0, 4))
		t.set_stylebox("grabber_pressed", bar, box(OXBLOOD, OXBLOOD, 0, 4))
	var groove := box(UMBER, INK, 0, 0)
	groove.content_margin_top = 4
	groove.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", groove)
	var fill := box(OXBLOOD, INK, 0, 0)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	return t


## A square cream check box icon: an outline, filled in when checked.
static func _check_icon(on: bool) -> ImageTexture:
	var n := 22
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in n:
		for x in n:
			var edge := x < 3 or y < 3 or x >= n - 3 or y >= n - 3
			var inner := x >= 6 and y >= 6 and x < n - 6 and y < n - 6
			if edge or (on and inner):
				img.set_pixel(x, y, CREAM)
	return ImageTexture.create_from_image(img)


## Restyle a button as a primary action: oxblood fill (like the prototype's Sharpen bar).
static func primary(b: Button) -> Button:
	var styles := {"normal": OXBLOOD, "hover": OXBLOOD.lightened(0.12), "pressed": OXBLOOD.darkened(0.25),
		"hover_pressed": OXBLOOD.darkened(0.15)}
	for st in styles:
		b.add_theme_stylebox_override(st, box(styles[st], INK, 2, 10))
	for c in ["font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, CREAM)
	return b


## A font size scaled by the player's text size setting.
static func fs(size: int) -> int:
	return roundi(size * FoSettings.text_scale())


static func box(bg: Color, border := EDGE, width := 1, margin := 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_content_margin_all(margin)
	s.anti_aliasing = false  # square corners everywhere: nothing to smooth
	return s


static func panel(style: StyleBox) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", style)
	return p


static func label(text: String, size := 22, color := INK, wrap := true) -> Label:
	var l := Label.new()
	l.text = text
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", fs(size))
	l.add_theme_color_override("font_color", color)
	return l


## wrap = false for labels inside an HBox: wrapping labels there collapse to zero width.
static func heading(text: String, size := 28, color := INK, wrap := true) -> Label:
	var l := label(text, size, color, wrap)
	l.add_theme_font_override("font", FoAssets.font(HEADING_FONT))
	return l


static func picture(tex: Texture2D, size: float, crisp := false) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(size, size)
	if crisp:
		r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return r


## Full-screen vertical gradient behind everything.
static func background() -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, BG_TOP)
	g.set_color(1, BG_BOTTOM)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.5, 0)
	gt.fill_to = Vector2(0.5, 1)
	gt.width = 64
	gt.height = 64
	var r := TextureRect.new()
	r.texture = gt
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## A card as a button: art on top, name, then (if given) its rules text.
## `edge` colours the border (e.g. RESERVE for reserved cards).
static func card_tile(title: String, body: String, tex: Texture2D, size := TILE, edge := EDGE) -> Button:
	var b := Button.new()
	b.custom_minimum_size = size
	b.clip_contents = true
	var small := size.x < 120
	var width := 2 if edge == EDGE else 4
	b.add_theme_stylebox_override("normal", box(CREAM, edge, width, 0))
	b.add_theme_stylebox_override("hover", box(CREAM.lightened(0.25), OXBLOOD, maxi(width, 3), 0))
	b.add_theme_stylebox_override("pressed", box(CREAM.darkened(0.08), OXBLOOD, maxi(width, 3), 0))
	b.add_theme_stylebox_override("disabled", box(CREAM, edge, width, 0))
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	var pad := 4 if small else 8
	v.offset_left = pad
	v.offset_top = pad
	v.offset_right = -pad
	v.offset_bottom = -pad
	v.add_theme_constant_override("separation", 2 if small else 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var art_size := size.x * (0.62 if small else 0.55)
	if tex != null:
		v.add_child(picture(tex, art_size))
	else:
		var blank := Control.new()
		blank.custom_minimum_size = Vector2(art_size, art_size)
		v.add_child(blank)
	# Tile text stays at its base size (the tile can't grow); the zoom view is for reading.
	var name_label := heading(title, 11 if small else 16, INK)
	name_label.add_theme_font_size_override("font_size", 11 if small else 16)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name_label)
	if body != "":
		var text := label(body, 14, INK)
		text.add_theme_font_size_override("font_size", 14)
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(text)
	for c in v.get_children():
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


## One die face. mark: 1 = scores / protects (green, thick border), -1 = triggers a penalty (red).
## armed: a Reaction is chosen and this die can take it (oxblood outline, hover lifts).
static func die_face(value: int, mark: int, magic: bool, carried: bool, size: float, selected := false, armed := false) -> Button:
	var b := Button.new()
	b.text = str(value)
	b.custom_minimum_size = Vector2(size, size)
	b.pivot_offset = Vector2(size, size) / 2
	b.add_theme_font_size_override("font_size", int(size * 0.45))
	b.add_theme_font_override("font", FoAssets.font(BOLD_FONT))
	var bg := IVORY if not selected else Color("#F3D98C")
	var border := INK
	var width := 2
	match mark:
		1:
			border = GOOD
			width = 6
		-1:
			border = RED
			width = 6
	if armed and mark == 0:
		border = OXBLOOD
		width = 4
	var style := box(bg, border, width, 0)
	style.shadow_color = Color(INK, 0.35)
	style.shadow_size = 0
	style.shadow_offset = Vector2(3, 3)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(state, style)
	if armed:
		var lit := box(Color("#F3D98C"), OXBLOOD if mark == 0 else border, width, 0)
		b.add_theme_stylebox_override("hover", lit)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var magic_ink := NAVY
	var kept_ink := KEPT
	var ink := INK
	if magic:
		ink = magic_ink
	if carried:
		ink = kept_ink
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color"]:
		b.add_theme_color_override(c, ink)
	if mark != 0:
		_die_badge(b, MARK_GOOD if mark == 1 else MARK_BAD, GOOD if mark == 1 else RED, size, Vector2(1, 0))
	if magic:
		_die_badge(b, MARK_MAGIC, magic_ink, size, Vector2(0, 1))
	if carried:
		_die_badge(b, MARK_KEPT, kept_ink, size, Vector2(1, 1))
	return b


## A small symbol in a die's corner; corner (0,0) = top-left, (1,1) = bottom-right.
static func _die_badge(die: Button, text: String, color: Color, size: float, corner: Vector2) -> void:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", FoAssets.font(BOLD_FONT))
	l.add_theme_font_size_override("font_size", maxi(12, int(size * 0.24)))
	l.add_theme_color_override("font_color", color)
	var box_size := size * 0.36
	var inset := size * 0.06
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = Vector2(box_size, box_size)
	l.position = Vector2(inset + corner.x * (size - box_size - 2 * inset), inset + corner.y * (size - box_size - 2 * inset))
	die.add_child(l)


## `filled` of `total` small squares, e.g. sharpening progress.
static func pips(filled: int, total: int, color := GOLD) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for i in total:
		var p := Panel.new()
		p.custom_minimum_size = Vector2(14, 14)
		p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		p.add_theme_stylebox_override("panel", box(color if i < filled else CREAM, INK if i >= filled else color, 2, 0))
		row.add_child(p)
	return row


## A short label in a box, e.g. "AP 3".
static func chip(text: String, color := INK, size := 17) -> PanelContainer:
	var p := panel(box(CREAM, EDGE, 1, 0))
	var st: StyleBoxFlat = p.get_theme_stylebox("panel")
	st.content_margin_left = 10
	st.content_margin_right = 10
	st.content_margin_top = 2
	st.content_margin_bottom = 2
	p.add_child(label(text, size, color, false))
	return p
