class_name FoAssets
extends RefCounted
## Art, fonts and sounds copied from the earlier React Native prototype (assets/).
## Presentation only: the rules engine never touches this.
##
## Card art is looked up from the CSV "Art Name" column. Some files in assets/ were
## renamed after the spreadsheet was written ("Copy of X.png", missing ".png", or a
## replacement image), so ART_ALIASES maps spreadsheet names to the file that exists.

const INGREDIENT_DIR := "res://assets/images/ingredients/"
const CHALLENGE_DIR := "res://assets/images/challenges/"
const AUDIO_DIR := "res://assets/audio/"
const INGREDIENT_SOUND_DIR := "res://assets/audio/ingredient_sounds/"
const FONT_DIR := "res://assets/fonts/"

## Spreadsheet art name -> actual file (same mapping the prototype used).
const ART_ALIASES := {
	"52_Potion_Lethal.png": "52_Potion_Lethal-brightened.png",
	"20_AluminumWire.png": "160_Handyman_Wire.png",
	"03_Soul.png": "89_Soul_Trapped_G.png",
	"05_Holywater.png": "NewHolyWaterNoWings.png",
}

## Ingredients the spreadsheet names art for, but no image exists yet.
const MISSING_ART := []

## Sound played when an Ingredient is drafted (from the prototype's ingredients.ts).
const INGREDIENT_SOUNDS := {
	"Gold": "Coin Dropped on Ceramic Dish.wav",
	"Hardened Steel": "hammer_hit1.wav",
	"Manticore Poison": "bottle_glug.wav",
	"Lotus Bloom": "leaves_clip.mp3",
	"Silver Wire": "MetalScraping.wav",
	"Dragon Tooth": "click_in_to_place.wav",
	"Soul": "hidden_wall_opening.mp3",
	"Cold Iron": "hammer_hit_2.wav",
	"Diamond Dust": "gravel_scoop.mp3",
	"Adamantium": "short_hammering.wav",
	"Holy Water": "bottle_glug.wav",
	"Emerald": "click_in_to_place.wav",
	"Mithril": "hammer_hit_3.wav",
	"Bronze": "hammer_hit_4.wav",
	"Aluminum": "ceramic_slide_small.mp3",
	"Golden Apple": "click_in_to_place.wav",
	"Rusty Bauble": "MetalScraping.wav",
	"Leather Grip": "ceramic_slide_small.mp3",
	"Jeweled Scabbard": "click_in_to_place.wav",
	"Sphinx's Milk": "bottle_glug.wav",
	"Hyacinth": "leaves_clip.mp3",
	"Electrum": "knife_sharpening_1.wav",
	"Beeswax": "gravel_scoop.mp3",
	"Lucky Fish Scale": "ceramic_slide_small.mp3",
	"Gambler's Charm": "Coin Dropped on Ceramic Dish.wav",
	"Phoenix Egg": "click_in_to_place.wav",
	"Dwarven Whetstone": "knife_sharpening_1.wav",
	"Magic Mirror": "ceramic_slide_small.mp3",
	"Orichalcum": "hammer_hit_3.wav",
	"Blood Ruby": "click_in_to_place.wav",
	"Branch of Yggdrasil": "leaves_clip.mp3",
	"Lightning Bolt": "hammer_hit1.wav",
	"Kraken Blood": "bottle_glug.wav",
	"Celestial Ore": "hammer_hit_4.wav",
	"Stygian Oil": "bottle_glug.wav",
	"Shadow Essence": "hidden_wall_opening.mp3",
}

## Game event -> [file under assets/audio/, volume 0..1]
const SFX := {
	"click": ["Modern7.mp3", 0.5],
	"toggle": ["Modern8.mp3", 0.5],
	"start": ["OldChurchBell.wav.mp3", 0.5],
	# Roll_8d6 split in two: the throw plays on release; Roll_8d6_rattle.wav (dice shaken in the hand) is kept, unused, for later
	"roll": ["Roll_8d6_throw.wav", 0.3],
	"challenge": ["Bank Card Placed Down 03.wav", 0.5],
	"reaction": ["Modern8.mp3", 0.5],
	"sharpen": ["ingredient_sounds/knife_sharpening_2.wav", 0.6],
	"reserve": ["01_chest_open_2.wav", 0.5],
	"quest_start": ["OldChurchBell.wav.mp3", 0.4],
	"quest_scored": ["anvil_3hit.wav", 0.55],
	"game_over": ["anvil_3hit.wav", 0.6],
	# contextual: one per move type (main.gd reads FoGame.moves), plus card hover / zoom
	"your_turn": ["JDSherbert - Ultimate UI SFX Pack - Cursor - 1.wav", 0.5],
	"pass": ["Modern9.mp3", 0.5],
	"swap": ["ingredient_sounds/MetalScraping.wav", 0.5],
	"wager": ["Coin Dropped on Ceramic Dish.wav", 0.6],
	"reroll": ["Roll_8d6_throw.wav", 0.18],
	"plus_one": ["ingredient_sounds/hammer_hit_5.wav", 0.5],
	"keep": ["ingredient_sounds/click_in_to_place.wav", 0.5],
	"copy": ["ingredient_sounds/hammer_hit_6.wav", 0.5],
	# the dice reveal (main.gd plays these at rising pitch for good news, falling for bad)
	"die_land": ["ingredient_sounds/click_in_to_place.wav", 0.3],
	"die_step": ["Modern8.mp3", 0.3],
	"die_good": ["JDSherbert - Ultimate UI SFX Pack - Cursor - 3.wav", 0.45],
	"die_bad": ["ingredient_sounds/hammer_hit_2.wav", 0.45],
	"tally": ["Coin Dropped on Ceramic Dish.wav", 0.3],
	"penalty": ["ingredient_sounds/hammer_hit_4.wav", 0.65],
	"zoom": ["JDSherbert - Ultimate UI SFX Pack - Cursor - 5.wav", 0.4],
	"menu": ["Modern16.mp3", 0.4],
}
const MUSIC := "res://assets/audio/US_Army_Blues_-_07_-_Bayou_Farewell.mp3"

const PIXEL_ART_SIZE := 128

static var _cache := {}


static func ingredient_art_path(art: String) -> String:
	return _resolve(INGREDIENT_DIR, art)


static func challenge_art_path(art: String) -> String:
	return _resolve(CHALLENGE_DIR, art)


static func ingredient_art(card: Dictionary) -> Texture2D:
	return _pixel_art(ingredient_art_path(card.get("art", "")))


static func challenge_art(card: Dictionary) -> Texture2D:
	return _pixel_art(challenge_art_path(card.get("art", "")))


static func ingredient_sound_path(card_name: String) -> String:
	return INGREDIENT_SOUND_DIR + INGREDIENT_SOUNDS[card_name] if INGREDIENT_SOUNDS.has(card_name) else ""


static func sfx_path(event: String) -> String:
	return AUDIO_DIR + SFX[event][0]


static func stream(path: String) -> AudioStream:
	return _load(path)


static func font(file_name: String) -> Font:
	return _load(FONT_DIR + file_name)


## Spreadsheet art name -> res:// path of an existing image, or "" if there isn't one.
static func _resolve(dir: String, art: String) -> String:
	art = art.strip_edges()
	if art == "":
		return ""
	var candidates := [ART_ALIASES.get(art, art), art + ".png", "Copy of " + art]
	for c in candidates:
		if ResourceLoader.exists(dir + c):
			return dir + c
	return ""


## The art is 32-64px pixel art. Upscale it once with nearest-neighbour so it stays crisp
## at any display size without forcing nearest filtering (and jaggy text) on the UI.
static func _pixel_art(path: String) -> Texture2D:
	var key := path + "@px"
	if not _cache.has(key):
		var tex: Texture2D = _load(path)
		if tex != null:
			var img := tex.get_image()
			if img.is_compressed():
				img.decompress()
			var f := maxi(1, PIXEL_ART_SIZE / maxi(img.get_width(), img.get_height()))
			img.resize(img.get_width() * f, img.get_height() * f, Image.INTERPOLATE_NEAREST)
			tex = ImageTexture.create_from_image(img)
		_cache[key] = tex
	return _cache[key]


## Drop cached resources (call on shutdown so nothing is "still in use at exit").
static func clear_cache() -> void:
	_cache.clear()


static func _load(path: String) -> Resource:
	if path == "":
		return null
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]
