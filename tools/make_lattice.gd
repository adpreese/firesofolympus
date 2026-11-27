## Woven lattice tile for the playmat -> assets/images/table/lattice.png
##   godot --headless --script res://tools/make_lattice.gd
## Flat, like a pattern woven into a tapestry rather than laid on it: the T x T tile is a grid of
## S-unit stitches, and the diagonals are stair-stepped runs of darker thread. Every stitch (ground
## and pattern alike) carries the same basket weave, so the lattice reads as part of the cloth.
## Small stepped diamonds mark the crossings. Rendered at 2x
## (FoUI.Playmat draws it at half scale); N stitches per tile keeps it seamless.
extends SceneTree

const T := 192.0
const OUT := 2          # output pixels per tile unit
const S := 3.0          # stitch size in tile units
const N := 64           # stitches per tile edge (T / S)
const RISE := 2         # stitch rows per stair step
const TREAD := 3        # stitches per tread (overlapping the next by TREAD - RISE)
const WEAVE := 0.06     # basket-weave light/dark swing on the ground
const WEAVE_PATTERN := 0.025  # and on the pattern, kept low so its edges stay crisp

const MAT := Color("#D1B88F")       # ground thread
const BAND := Color("#B39874")      # the stair-step diagonals
const KNOT := Color("#A68B62")      # crossing diamonds, flat


## Stitch colour at cell (cx, cy).
func stitch(cx: int, cy: int) -> Color:
	# crossings sit on cell corners: the tile corners and its centre
	for c in [Vector2(0, 0), Vector2(N, 0), Vector2(0, N), Vector2(N, N), Vector2(N / 2, N / 2)]:
		var m := absf(cx + 0.5 - c.x) + absf(cy + 0.5 - c.y)
		if m <= 3.0:
			return KNOT
	# stair-stepped diagonals in one flat colour
	var r := int(floor(float(cy) / RISE)) * RISE
	var i1 := posmod(cx - r + 1, N)
	if i1 < TREAD:
		return BAND
	var i2 := posmod(-cx - 1 - r + 1, N)
	if i2 < TREAD:
		return BAND
	return MAT


func shade(x: float, y: float) -> Color:
	var cx := int(floor(x / S))
	var cy := int(floor(y / S))
	var base := stitch(posmod(cx, N), posmod(cy, N))
	# basket weave: two threads per stitch, running across or down in alternate stitches,
	# each rounded (lit in the middle, dim where it dips under its neighbour)
	var u := fposmod(x, S) / S
	var v := fposmod(y, S) / S
	var f := v if (cx + cy) % 2 == 0 else u
	var thread := sin(PI * fposmod(f * 2.0, 1.0))   # 0 at the gaps, 1 at a thread's crown
	var k := (thread - 0.6) * (WEAVE if base == MAT else WEAVE_PATTERN) * 2.0
	if k >= 0.0:
		return base.lightened(k)
	return base.darkened(-k)


func _init() -> void:
	var px := int(T) * OUT
	var img := Image.create(px, px, false, Image.FORMAT_RGB8)
	for j in px:
		for i in px:
			img.set_pixel(i, j, shade((i + 0.5) / OUT, (j + 0.5) / OUT))
	var path := "res://assets/images/table/lattice.png"
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		path = args[0]
	img.save_png(path)
	print("wrote ", path)
	quit()
