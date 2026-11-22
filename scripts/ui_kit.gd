class_name FoUI
extends RefCounted
## The game's look: colours, the global Theme, and constructors for styled widgets
## (card tiles, dice, panels). Presentation only: no FoGame access, no game logic.

const GOLD := Color(1.0, 0.75, 0.35)
const RED := Color(0.95, 0.38, 0.32)
const INK := Color(0.94, 0.9, 0.84)
const MUTED := Color(0.68, 0.63, 0.7)
const MAGIC := Color(0.5, 0.8, 1.0)
const KEPT := Color(1.0, 0.85, 0.3)
const RESERVE := Color(0.45, 0.75, 0.65)
const PANEL := Color(0.14, 0.1, 0.16)
const PANEL_LIGHT := Color(0.21, 0.16, 0.24)
const EDGE := Color(0.38, 0.31, 0.42)
const BG_TOP := Color(0.13, 0.07, 0.12)
const BG_BOTTOM := Color(0.03, 0.02, 0.05)
const HEADING_FONT := "Cinzel-Bold.ttf"
const BODY_FONT := "SourceSerif4-Regular.ttf"
const BOLD_FONT := "SourceSerif4-SemiBold.ttf"

const TILE := Vector2(176, 240)  # market / choice cards
const MINI := Vector2(84, 104)   # cards on a player's mat


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = fs(22)
	t.default_font = FoAssets.font(BODY_FONT)
	t.set_color("font_color", "Label", INK)
	var states := {
		"normal": box(PANEL_LIGHT, EDGE, 1, 8, 10),
		"hover": box(PANEL_LIGHT.lightened(0.08), GOLD, 2, 8, 10),
		"pressed": box(PANEL_LIGHT.darkened(0.2), GOLD, 2, 8, 10),
		"disabled": box(PANEL.darkened(0.2), EDGE.darkened(0.3), 1, 8, 10),
		"focus": StyleBoxEmpty.new(),
	}
	for s in states:
		t.set_stylebox(s, "Button", states[s])
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", GOLD)
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", MUTED.darkened(0.3))
	t.set_stylebox("normal", "LineEdit", box(PANEL, EDGE, 1, 6, 8))
	t.set_stylebox("focus", "LineEdit", box(PANEL, GOLD, 2, 6, 8))
	t.set_stylebox("panel", "PanelContainer", box(PANEL, EDGE))
	return t


## A font size scaled by the player's text size setting.
static func fs(size: int) -> int:
	return roundi(size * FoSettings.text_scale())


static func box(bg: Color, border := EDGE, width := 1, radius := 10, margin := 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	s.anti_aliasing = true
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
	var radius := 6 if small else 10
	b.add_theme_stylebox_override("normal", box(PANEL_LIGHT, edge, 2 if edge != EDGE else 1, radius, 0))
	b.add_theme_stylebox_override("hover", box(PANEL_LIGHT.lightened(0.08), GOLD, 2, radius, 0))
	b.add_theme_stylebox_override("pressed", box(PANEL_LIGHT.darkened(0.2), GOLD, 2, radius, 0))
	b.add_theme_stylebox_override("disabled", box(PANEL_LIGHT, edge, 2 if edge != EDGE else 1, radius, 0))
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
	var name_label := heading(title, 11 if small else 16, GOLD)
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


## A small round "i" button pinned to a tile's top-right corner.
static func corner_button(parent: Control, text: String) -> Button:
	var i := Button.new()
	i.text = text
	i.add_theme_font_size_override("font_size", 16)
	var r := 16
	for s in ["normal", "hover", "pressed"]:
		var st := box(PANEL.darkened(0.3) if s == "normal" else PANEL_LIGHT, GOLD if s != "normal" else EDGE, 1, r, 0)
		i.add_theme_stylebox_override(s, st)
	i.anchor_left = 1
	i.anchor_right = 1
	i.offset_left = -38
	i.offset_right = -6
	i.offset_top = 6
	i.offset_bottom = 38
	parent.add_child(i)
	return i


## One die face. mark: 1 = scores / protects (gold, thick border), -1 = triggers a penalty (red).
static func die_face(value: int, mark: int, magic: bool, carried: bool, size: float, selected := false) -> Button:
	var b := Button.new()
	b.text = str(value)
	b.custom_minimum_size = Vector2(size, size)
	b.pivot_offset = Vector2(size, size) / 2
	b.add_theme_font_size_override("font_size", int(size * 0.45))
	b.add_theme_font_override("font", FoAssets.font(BOLD_FONT))
	var bg := Color(0.93, 0.89, 0.82) if not selected else Color(1.0, 0.95, 0.75)
	var border := Color(0.5, 0.42, 0.38)
	var width := 2
	match mark:
		1:
			border = GOLD
			width = 6
		-1:
			border = RED
			width = 6
	var style := box(bg, border, width, int(size * 0.18), 0)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 3)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(state, style)
	var ink := Color(0.15, 0.1, 0.12)
	if magic:
		ink = Color(0.1, 0.35, 0.75)
	if carried:
		ink = Color(0.6, 0.38, 0.0)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color"]:
		b.add_theme_color_override(c, ink)
	return b


## `filled` of `total` small squares, e.g. sharpening progress.
static func pips(filled: int, total: int, color := GOLD) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for i in total:
		var p := Panel.new()
		p.custom_minimum_size = Vector2(14, 14)
		p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		p.add_theme_stylebox_override("panel", box(color if i < filled else PANEL, color, 1, 3, 0))
		row.add_child(p)
	return row


## A short label in a rounded box, e.g. "AP 3".
static func chip(text: String, color := INK, size := 17) -> PanelContainer:
	var p := panel(box(PANEL.darkened(0.25), EDGE, 1, 12, 0))
	var st: StyleBoxFlat = p.get_theme_stylebox("panel")
	st.content_margin_left = 10
	st.content_margin_right = 10
	st.content_margin_top = 2
	st.content_margin_bottom = 2
	p.add_child(label(text, size, color, false))
	return p
