## Barley-twist lattice tile for the playmat -> assets/images/table/lattice.png
##   godot --headless --script res://tools/make_lattice.gd
## Ray-cast per pixel rather than drawn: each diagonal of the T x T tile is a turned bar with
## STARTS helical grooves (a height field), lit from the upper left, casting a soft shadow on the
## mat; square bevelled rivets cap the crossings. Rendered at 2x (FoUI.Playmat draws it at half
## scale) with SS x SS supersampling. N grooves per half diagonal keeps the twist in phase at the
## tile edges, so it tiles seamlessly.
extends SceneTree

const T := 192.0
const OUT := 2          # output pixels per tile unit
const SS := 3           # supersamples per output pixel, per axis
const N := 11           # grooves per half diagonal
const STARTS := 2       # helix starts (double twist, like the balusters)
const W := 4.6          # bar radius at a ridge crown
const W_IN := 2.9       # bar radius at the bottom of a groove
const RIVET := 7.5      # rivet half diagonal
const RIVET_TOP := 6.4  # rivet height (bars peak at W)
const BEAD := 2.8       # width of the turned collar where a twist meets a rivet
const NAIL := 2.3       # nailhead radius in the middle of each open diamond

const MAT := Color("#D1B88F")
const WOOD := Color("#CDB38A")
const WOOD_DARK := Color("#B49C75")
const WOOD_LIGHT := Color("#D9C39C")
const SHADOW := Color("#A68B62")

var HALF := T / sqrt(2.0)
var SP := HALF / N
var P := SP * STARTS
var L := Vector3(-0.42, -0.62, 0.66).normalized()
var H := (L + Vector3(0, 0, 1)).normalized()


## Radius of the bar at helix phase f in [0, 1): round ridges, narrow grooves.
func prof(f: float) -> float:
	return W_IN + (W - W_IN) * pow(sin(PI * f), 0.45)


## Height of one twisted bar at axial u, lateral v (-1 = miss). Solves the helix phase
## at the surface angle a few times, since the radius depends on where you hit it.
func bar_h(u: float, v: float) -> float:
	if absf(v) >= W + 0.6:
		return -1.0
	# turned collar: a plain neck under the rivet, then a round bead, then the twist starts
	var a := absf(u - roundf(u / HALF) * HALF)
	var neck := RIVET / sqrt(2.0)
	if a < neck + BEAD:
		var r0 := W * 0.85
		if a > neck:
			r0 += (W + 0.6 - r0) * sqrt(sin(PI * (a - neck) / BEAD))
		return sqrt(r0 * r0 - v * v) if absf(v) < r0 else -1.0
	if absf(v) >= W:
		return -1.0
	var r := W
	for i in 4:
		var th := asin(clampf(v / r, -1.0, 1.0))
		r = prof(fposmod(u - P * th / TAU, SP) / SP)
	if absf(v) >= r:
		return -1.0
	return sqrt(r * r - v * v)


func rivet_h(x: float, y: float) -> float:
	# nearest crossing: the centre or a corner
	var c := Vector2(T / 2, T / 2)
	var best := c.distance_squared_to(Vector2(x, y))
	for k in [Vector2(0, 0), Vector2(T, 0), Vector2(0, T), Vector2(T, T)]:
		var d: float = k.distance_squared_to(Vector2(x, y))
		if d < best:
			best = d
			c = k
	var m := absf(x - c.x) + absf(y - c.y)
	if m >= RIVET:
		return -1.0
	var top := RIVET * 0.5
	var h := RIVET_TOP if m < top else lerpf(RIVET_TOP, W * 0.55, (m - top) / (RIVET - top))
	var p := Vector2(x, y).distance_to(c)  # domed pin in the middle
	if p < 1.5:
		h += sqrt(1.5 * 1.5 - p * p) * 0.8
	return h


## Height of everything at (x, y); -1 on the bare mat. The two families share the tile's period.
func height(x: float, y: float) -> float:
	var s2 := sqrt(2.0)
	var d1 := (y - x) / s2
	var h1 := bar_h((x + y) / s2, d1 - roundf(d1 / HALF) * HALF)
	var d2 := (x + y) / s2
	var h2 := bar_h((x - y) / s2, d2 - roundf(d2 / HALF) * HALF)
	var h := maxf(maxf(h1, h2), rivet_h(x, y))
	for c in [Vector2(T / 2, 0), Vector2(T / 2, T), Vector2(0, T / 2), Vector2(T, T / 2)]:
		var d: float = c.distance_to(Vector2(x, y))
		if d < NAIL:
			h = maxf(h, sqrt(NAIL * NAIL - d * d) * 0.6)
	return h


func shade(x: float, y: float) -> Color:
	var h := height(x, y)
	if h < 0.0:
		# soft cast shadow: is something between here and the light?
		var hit := 0.0
		for k in [1.0, 1.7, 2.4, 3.1]:
			var q: float = height(x + L.x / L.z * k, y + L.y / L.z * k)
			if q >= k:
				hit += 1.0
			elif q >= 0.0:
				hit += 0.5
		return MAT.lerp(SHADOW, 0.15 * hit / 4.0)
	var e := 0.12
	var hx0 := maxf(height(x - e, y), 0.0)
	var hx1 := maxf(height(x + e, y), 0.0)
	var hy0 := maxf(height(x, y - e), 0.0)
	var hy1 := maxf(height(x, y + e), 0.0)
	var n := Vector3(-(hx1 - hx0) / (2 * e), -(hy1 - hy0) / (2 * e), 1.0).normalized()
	var diff := maxf(n.dot(L), 0.0)
	var spec := pow(maxf(n.dot(H), 0.0), 28.0)
	# grooves catch less ambient light than the crowns
	var ao := clampf((h - W_IN * 0.6) / (W - W_IN * 0.6), 0.0, 1.0)
	var lum := 0.22 + 0.78 * diff * (0.55 + 0.45 * ao)
	var c := WOOD_DARK.lerp(WOOD, clampf(lum / 0.72, 0.0, 1.0))
	if lum > 0.72:
		c = WOOD.lerp(WOOD_LIGHT, clampf((lum - 0.72) / 0.28, 0.0, 1.0))
	return c.lerp(WOOD_LIGHT, spec * 0.3)


func _init() -> void:
	var px := int(T) * OUT
	var img := Image.create(px, px, false, Image.FORMAT_RGB8)
	var step := 1.0 / (OUT * SS)
	for j in px:
		for i in px:
			var acc := Color(0, 0, 0)
			for sj in SS:
				for si in SS:
					var c := shade((i * SS + si + 0.5) * step, (j * SS + sj + 0.5) * step)
					acc.r += c.r; acc.g += c.g; acc.b += c.b
			var k := 1.0 / (SS * SS)
			img.set_pixel(i, j, Color(acc.r * k, acc.g * k, acc.b * k))
	var path := "res://assets/images/table/lattice.png"
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		path = args[0]
	img.save_png(path)
	print("wrote ", path)
	quit()
