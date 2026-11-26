class_name FoUI
extends RefCounted
## The game's look: colours, the global Theme, and constructors for styled widgets
## (card tiles, dice, panels). Presentation only: no FoGame access, no game logic.

## Parchment palette, after the React Native prototype (design/prototype/notes.md):
## brown ink on tan and cream, thick dark outlines, flat fills; red = Strength only,
## navy = Sharpness only, green = gains. "Act here" (primary buttons, the current turn) is ink.
const INK := Color("#2B1D14")       # text, outlines, rules
const CREAM := Color("#E6D4B2")     # card faces, raised panels, text on coloured fills
const TAN := Color("#D1B88F")       # the table and ordinary panels
const OCHRE := Color("#C2A36B")     # the dice tray
const UMBER := Color("#3C3426")     # ordinary buttons
const OXBLOOD := Color("#9A2B2B")   # Strength
const NAVY := Color("#2C4A82")      # Sharpness
const IVORY := Color("#FBF4DE")     # die faces

const GOLD := OXBLOOD               # accent for menu headings (not for "your turn": that is ink)
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
	# heavy outline, so a choice never looks like the filled ink call to action (`primary`).
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


## Restyle a button as the primary action: ink fill. Red and navy are kept for Strength and
## Sharpness, so a call to action never looks like a Challenge colour.
static func primary(b: Button) -> Button:
	var styles := {"normal": INK, "hover": INK.lightened(0.16), "pressed": INK.lightened(0.3),
		"hover_pressed": INK.lightened(0.24)}
	for st in styles:
		b.add_theme_stylebox_override(st, box(styles[st], INK, 2, 10))
	for c in ["font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, CREAM)
	return b


## Restyle a button as a quiet alternative (e.g. Pass beside Sharpen): an ink outline, no fill.
static func secondary(b: Button) -> Button:
	var styles := {"normal": Color(CREAM, 0.0), "hover": Color(CREAM, 0.5), "pressed": CREAM.darkened(0.08),
		"hover_pressed": CREAM}
	for st in styles:
		b.add_theme_stylebox_override(st, box(styles[st], INK, 2, 10))
	for c in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, INK)
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


## Full-screen playmat behind everything: a centred column `frame_span` wide (0 = the whole screen)
## of lattice inside an egg-and-dart frame `frame_w` deep, with dark bars either side like the title art.
## Keep the board clear of the frame.
static func background(frame_w := 28.0, frame_span := 0.0) -> Playmat:
	var r := Playmat.new()
	r.frame_w = frame_w
	r.frame_span = frame_span
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## The SVGs are imported at 2x (svg/scale) so they stay crisp on high-DPI screens;
## the frame is a nine-slice (tools/make_playmat_frame.py) whose edges repeat whole eggs.
class Playmat extends Control:
	const LATTICE := preload("res://assets/images/table/lattice.svg")
	const FRAME := preload("res://assets/images/table/frame.svg")
	const TEX_SCALE := 2.0
	const FRAME_SRC := 28.0  # frame depth in the SVG
	var frame_w := 28.0
	var frame_span := 0.0
	var _box := StyleBoxTexture.new()

	func _init() -> void:
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_box.texture = FRAME
		_box.draw_center = false
		_box.set_texture_margin_all(FRAME_SRC * TEX_SCALE)
		_box.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
		_box.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
		resized.connect(queue_redraw)

	func _draw() -> void:
		# Outside the framed column: the title screen's dark bars (FoUI.INK = main.gd TITLE_BARS).
		var w := size.x if frame_span <= 0.0 else minf(frame_span, size.x)
		var x := (size.x - w) / 2.0
		if x > 0.0:
			draw_rect(Rect2(Vector2.ZERO, size), FoUI.INK)
		var k := 1.0 / TEX_SCALE
		draw_set_transform(Vector2(x, 0.0), 0.0, Vector2(k, k))
		draw_texture_rect(LATTICE, Rect2(Vector2.ZERO, Vector2(w, size.y) / k), true)
		var f := frame_w / (FRAME_SRC * TEX_SCALE)
		draw_set_transform(Vector2(x, 0.0), 0.0, Vector2(f, f))
		draw_style_box(_box, Rect2(Vector2.ZERO, Vector2(w, size.y) / f))


const GILT := Color("#D4A640")    # a card's dice count (a gold die)
const SILVER := Color("#BCC1C6")  # a card's AP (a silver diamond)
## Limestone plaque: pale and neutral, so it stands off the tan board by value and the art leads.
const CARD_FACE := Color("#ECE8DF")
const CARD_BAR := Color("#E0DBCF")   # the name bar
const CARD_HI := Color("#FFFFFF")    # bevel light (top / left) and the rule under the name bar
const CARD_LO := Color("#A39C8E")    # bevel shade (bottom / right)
const CARD_WELL := Color("#FBFAF6")  # the rules well
const CARD_LINE := Color("#3A352D")  # outline and well edges
const CARD_FOLD := Color("#C9C2B3")  # underside of the "more" corner
const CARD_BAR_H := 40              # full-size card regions are fixed, so cards scan in a grid
const CARD_RULE_LINES := 3        # rules text past this is cut, with a folded corner: hold to read
const CARD_TEXT := 13


## Splits a card's flat stat lines ("+3D6", "-3 AP") out of its rules text for the top bar.
## Conditional lines ("+1D6 against Demons") stay in `rest`.
static func card_stats(body: String) -> Dictionary:
	var dice_re := RegEx.create_from_string("^([+-])\\s*(\\d+)\\s*D6$")
	var ap_re := RegEx.create_from_string("^([+-])\\s*(\\d+)\\s*AP$")
	var out := {"dice": null, "ap": null}
	var rest: PackedStringArray = []
	for line in body.split("\n"):
		var s := line.strip_edges()
		if s == "":
			continue
		var m := dice_re.search(s)
		if m != null and out.dice == null:
			out.dice = int(m.get_string(2)) * (-1 if m.get_string(1) == "-" else 1)
			continue
		m = ap_re.search(s)
		if m != null and out.ap == null:
			out.ap = int(m.get_string(2)) * (-1 if m.get_string(1) == "-" else 1)
			continue
		rest.append(s)
	out.rest = "\n".join(rest)
	return out


## A card as a button. Full size, a cast limestone plaque with fixed regions: a top bar (name,
## gold die = dice count, silver diamond = AP), the art in a well, then up to three lines of the
## rest of the rules in a second well, cut with a folded corner when there's more (hold to read it).
## No rules text, no rules well: the art well runs down into its space.
## `edge` colours the outline when it marks something (RESERVE for reserved cards, INK for a preview).
static func card_tile(title: String, body: String, tex: Texture2D, size := TILE, edge := EDGE) -> Button:
	var b := Button.new()
	b.custom_minimum_size = size
	b.clip_contents = true
	if size.x < 120:
		return _mini_tile(b, title, tex, size, edge)
	var pad := _card_frame(b, edge)
	var st := card_stats(body)
	var inner := size - Vector2(2 * pad, 2 * pad)
	var font := FoAssets.font(BODY_FONT)
	var line_h := font.get_height(CARD_TEXT) + 3
	var rules_h := CARD_RULE_LINES * line_h - 3 + 10
	var gap := 5.0
	var art_h := inner.y - CARD_BAR_H - 2 * gap - 4 - rules_h
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = pad
	root.offset_top = pad
	root.offset_right = -pad
	root.offset_bottom = -pad
	b.add_child(root)
	var bar := _card_bar(title, st, inner.x)
	bar.size = Vector2(inner.x, CARD_BAR_H)
	root.add_child(bar)
	var well := panel(_flat(Color(0, 0, 0, 0), 3))  # no fill or outline: the art sits on the plaque
	well.position = Vector2(gap, CARD_BAR_H + gap)
	# With no rules text there's no rules well: the art well takes its space.
	well.size = Vector2(inner.x - 2 * gap, art_h if st.rest != "" else art_h + 4 + rules_h)
	if tex != null:
		well.add_child(picture(tex, 20))
	root.add_child(well)
	if st.rest != "":
		var rules := _card_rules(st.rest, inner.x - 2 * gap)
		rules.position = Vector2(gap, CARD_BAR_H + gap + art_h + 4)
		rules.size = Vector2(inner.x - 2 * gap, rules_h)
		root.add_child(rules)
	_ignore_mouse(b)
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	return b


static func _mini_tile(b: Button, title: String, tex: Texture2D, size: Vector2, edge: Color) -> Button:
	var width := 2 if edge == EDGE else 4
	b.add_theme_stylebox_override("normal", box(CREAM, edge, width, 0))
	b.add_theme_stylebox_override("hover", box(CREAM.lightened(0.25), OXBLOOD, maxi(width, 3), 0))
	b.add_theme_stylebox_override("pressed", box(CREAM.darkened(0.08), OXBLOOD, maxi(width, 3), 0))
	b.add_theme_stylebox_override("disabled", box(CREAM, edge, width, 0))
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top"]:
		v.set("offset_" + side, 4)
	for side in ["right", "bottom"]:
		v.set("offset_" + side, -4)
	v.add_theme_constant_override("separation", 2)
	b.add_child(v)
	var art_size := size.x * 0.62
	if tex != null:
		v.add_child(picture(tex, art_size))
	else:
		var blank := Control.new()
		blank.custom_minimum_size = Vector2(art_size, art_size)
		v.add_child(blank)
	# Tile text stays at its base size (the tile can't grow); the zoom view is for reading.
	var name_label := heading(title, 11, INK)
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name_label)
	_ignore_mouse(v)
	return b


static func _ignore_mouse(n: Node) -> void:
	for c in n.get_children():
		if c is Control:
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_mouse(c)


## A flat stylebox: `border` = [colour, width] on every side, or per side via `sides` (l, t, r, b).
static func _flat(bg: Color, margin := 0, border := [], sides := []) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.anti_aliasing = false
	s.set_content_margin_all(margin)
	if border.size() == 2:
		s.border_color = border[0]
		var w: Array = sides if sides.size() == 4 else [border[1], border[1], border[1], border[1]]
		s.border_width_left = w[0]
		s.border_width_top = w[1]
		s.border_width_right = w[2]
		s.border_width_bottom = w[3]
	return s


## The plaque: an outline, then a cast bevel lit from the top left. A marking `edge` draws the
## outline heavier inside the same inset, so marked cards keep the same layout. Returns the inset.
static func _card_frame(b: Button, edge: Color) -> int:
	var marked := edge != EDGE
	var w := 4 if marked else 1
	var bevel := 3
	var face := CARD_FACE
	var line := edge if marked else CARD_LINE
	b.add_theme_stylebox_override("normal", box(face, line, w, 0))
	b.add_theme_stylebox_override("disabled", box(face, line, w, 0))
	b.add_theme_stylebox_override("hover", box(face.lightened(0.15), line.lightened(0.2), w, 0))
	b.add_theme_stylebox_override("pressed", box(face.darkened(0.08), INK, w, 0))
	var hi := CARD_HI
	var lo := CARD_LO
	var o := Control.new()
	o.set_anchors_preset(Control.PRESET_FULL_RECT)
	o.draw.connect(func():
		var s := o.size
		var f := float(w)
		var e := float(bevel)
		o.draw_rect(Rect2(f, f, s.x - 2 * f, e), hi)
		o.draw_rect(Rect2(f, f, e, s.y - 2 * f), hi)
		o.draw_rect(Rect2(f, s.y - f - e, s.x - 2 * f, e), lo)
		o.draw_rect(Rect2(s.x - f - e, f, e, s.y - 2 * f), lo))
	b.add_child(o)
	return 4 + bevel


## Top bar (fixed height): name on the left, then the gold die and silver diamond. The name
## stays on one line, shrinking to 12 px; past that it wraps to two.
static func _card_bar(title: String, st: Dictionary, width: float) -> Control:
	var chips: Array[Control] = []
	if st.dice != null:
		chips.append(_stat_chip("%d" % st.dice, true))
	if st.ap != null:
		chips.append(_stat_chip("%+d" % st.ap, false))
	var chips_w := 0.0
	for c in chips:
		chips_w += c.custom_minimum_size.x + 3
	var text_w := width - 12 - chips_w
	var font := FoAssets.font(HEADING_FONT)
	var size := 14
	while size > 12 and font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > text_w:
		size -= 1
	for word in title.split(" "):  # a word never breaks mid-word
		while size > 10 and font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > text_w:
			size -= 1
	var bar := panel(_flat(CARD_BAR, 0, [CARD_HI, 2], [0, 0, 0, 2]))
	var inner := Control.new()
	bar.add_child(inner)
	var name := heading(title, size, INK)
	name.add_theme_font_size_override("font_size", size)
	name.add_theme_constant_override("line_spacing", 0)
	name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name.autowrap_mode = TextServer.AUTOWRAP_WORD
	name.set_anchors_preset(Control.PRESET_FULL_RECT)
	name.offset_left = 6
	name.offset_right = -(chips_w + 6)
	inner.add_child(name)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_right = -5
	for c in chips:
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(c)
	inner.add_child(row)
	return bar


## A stat token, shaped by meaning: a gold die face (dice count) or a silver diamond (AP).
static func _stat_chip(n: String, dice: bool) -> Control:
	var bold := FoAssets.font(BOLD_FONT)
	var metal := GILT if dice else SILVER
	var c := Control.new()
	c.custom_minimum_size = Vector2(26 if dice else 28, 26)
	c.draw.connect(func():
		var s := c.size
		if dice:
			c.draw_rect(Rect2(Vector2.ZERO, s), metal)
			c.draw_rect(Rect2(Vector2(1, 1), s - Vector2(2, 2)), metal.lightened(0.35), false, 1.0)
			c.draw_rect(Rect2(Vector2.ZERO, s), INK, false, 1.5)
		else:
			var m := s / 2
			var pts := PackedVector2Array([Vector2(m.x, 0), Vector2(s.x, m.y), Vector2(m.x, s.y), Vector2(0, m.y)])
			c.draw_colored_polygon(pts, metal)
			pts.append(pts[0])
			c.draw_polyline(pts, INK, 1.5, true)
		var fsz := 13 if n.length() < 3 else 11
		var tw := bold.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
		c.draw_string(bold, Vector2((s.x - tw) / 2, s.y / 2 + bold.get_ascent(fsz) / 2 - 1), n,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, INK))
	return c


## The rules well: up to CARD_RULE_LINES lines. Longer text ends in "…" and the well gets a
## folded bottom-right corner, the sign that holding the card shows the rest.
static func _card_rules(text: String, width: float) -> Control:
	var font := FoAssets.font(BODY_FONT)
	var face := CARD_FACE
	var under := CARD_FOLD
	var line := CARD_LINE
	var more := _text_height(font, text, CARD_TEXT, width - 10) > CARD_RULE_LINES * (font.get_height(CARD_TEXT) + 3)
	var p := panel(_flat(CARD_WELL, 4, [CARD_LINE, 1]))
	var l := label(text.replace("\n", " ") if more else text, CARD_TEXT, INK)
	l.add_theme_font_size_override("font_size", CARD_TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.max_lines_visible = CARD_RULE_LINES
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	p.add_child(l)
	var w := Control.new()
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	w.add_child(p)
	if more:
		var fold := Control.new()
		fold.set_anchors_preset(Control.PRESET_FULL_RECT)
		fold.draw.connect(func():
			var s := fold.size
			var k := 11.0
			fold.draw_colored_polygon(PackedVector2Array([s - Vector2(k, 0), s - Vector2(0, k), s]), face)
			fold.draw_colored_polygon(PackedVector2Array([s - Vector2(k, 0), s - Vector2(0, k), s - Vector2(k, k)]), under)
			fold.draw_polyline(PackedVector2Array([s - Vector2(k, 0), s - Vector2(k, k), s - Vector2(0, k), s - Vector2(k, 0)]), line, 1.0))
		w.add_child(fold)
	return w


## Height a wrapped, centred Label of `text` would take at `width` (Label's line spacing is 3).
static func _text_height(font: Font, text: String, size: int, width: float) -> float:
	var h := font.get_height(size)
	var lines := maxi(1, roundi(font.get_multiline_string_size(text.strip_edges(), HORIZONTAL_ALIGNMENT_CENTER, width, size).y / h))
	return lines * h + (lines - 1) * 3


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
static func pips(filled: int, total: int, color := INK, size := 14.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for i in total:
		var p := Panel.new()
		p.custom_minimum_size = Vector2(size, size)
		p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		p.add_theme_stylebox_override("panel", box(color if i < filled else CREAM, INK if i >= filled else color, 2, 0))
		row.add_child(p)
	return row


## A dice pool without a box: a small square in the Challenge's colour, then "2d6" in it.
static func pool(dice: int, color: Color, size := 18) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	var sq := Panel.new()
	sq.custom_minimum_size = Vector2(12, 12)
	sq.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sq.add_theme_stylebox_override("panel", box(color, color, 0, 0))
	row.add_child(sq)
	row.add_child(label("%dd6" % dice, size, color, false))
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
