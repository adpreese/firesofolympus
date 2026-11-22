extends SceneTree
## Regenerates the app icon (icon.png, 1024x1024, no alpha as the App Store requires) and the
## launch image (assets/splash.png, shown on a FoUI.BG_BOTTOM-coloured screen) from the sword art.
##   godot --headless --script res://tools/make_art.gd

const SWORD := "res://assets/images/challenges/15_sword.png"
const EMBER := Color(1.0, 0.55, 0.15)


func _init() -> void:
	var sword := Image.load_from_file(ProjectSettings.globalize_path(SWORD))
	sword.convert(Image.FORMAT_RGBA8)
	_icon(sword).save_png("res://icon.png")
	_splash(sword).save_png("res://assets/splash.png")
	print("wrote icon.png and assets/splash.png")
	quit()


func _icon(sword: Image) -> Image:
	var n := 1024
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		var bg := FoUI.BG_TOP.lerp(FoUI.BG_BOTTOM, float(y) / n)
		for x in n:
			img.set_pixel(x, y, bg.lerp(EMBER, _glow(x, y, n) * 0.85))
	_stamp(img, sword, 880)
	img.convert(Image.FORMAT_RGB8)
	return img


func _splash(sword: Image) -> Image:
	var n := 1024
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var c := EMBER
			c.a = _glow(x, y, n) * 0.6
			img.set_pixel(x, y, c)
	_stamp(img, sword, 700)
	return img


## A soft ember glow centred a little below the middle, 1 at the centre fading to 0.
func _glow(x: int, y: int, n: int) -> float:
	var d := Vector2(x, y).distance_to(Vector2(n * 0.5, n * 0.56)) / (n * 0.42)
	return clampf(1.0 - d, 0.0, 1.0) ** 1.8


## The pixel art scaled up crisply (nearest) to `size` and centred.
func _stamp(img: Image, art: Image, size: int) -> void:
	var big := art.duplicate()
	big.resize(size, size, Image.INTERPOLATE_NEAREST)
	var at := (Vector2i(img.get_width(), img.get_height()) - Vector2i(size, size)) / 2
	img.blend_rect(big, Rect2i(Vector2i.ZERO, big.get_size()), at)
