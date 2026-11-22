class_name CardData
extends RefCounted
## Card text comes from the design CSVs (names, descriptions, art names).
## Card *behaviour* is in DEFS below, hand-written from that text. Tests check the
## two stay in sync, so renaming a card in the spreadsheet fails loudly.

const INGREDIENTS_CSV := "res://data/blade_ingredients.csv"
const CHALLENGES_CSV := "res://data/combined_tests.csv"
const MONSTER_TYPES := ["Elemental", "Demon", "Giant"]

## Ingredient definition keys:
##   dice: int            d6 added to every Challenge pool (negative removes dice)
##   vs: {type: int}      d6 added only against Challenges of that monster type
##   magic: int           Sphinx's Milk magic dice (1-3 count as 5, 4-6 count as 6)
##   ap: int              Action Point change when drafted
##   mod: int             Modifier added to every die
##   sharp_mod: int       Modifier added to every die in the Sharpness Challenge
##   bronze: bool         Effect: 1s become 2s, 6s become 5s
##   leather: bool        Modifier: +2 to dice showing 2 or 3
##   mithril: bool        each final result >= 6 in Sharpness is a bonus Success
##   bonus_success: int   flat Successes on the Sharpness Challenge
##   hyacinth: bool       +1d6 per other Ingredient
##   electrum: bool       +1d6 per Sharpening action
##   no_sharpen: bool     can't Sharpen (further) this Quest
##   skip_strength: bool  skip the Strength Challenge this Quest
##   swap_on_draft: bool  Rusty Bauble swap
##   gamble: bool         Gambler's Charm wager
##   reactions: [{kind: reroll|plus_one|keep, uses, scope: challenge|quest|quest_once,
##                vs?: monster type, challenge?: Strength|Sharpness}]
const DEFS := {
	"Gold": {"vs": {"Elemental": 1}, "reactions": [{"kind": "reroll", "uses": 1, "scope": "challenge"}]},
	"Hardened Steel": {"dice": 3},
	"Manticore Poison": {"vs": {"Giant": 1}, "sharp_mod": 1},
	"Lotus Bloom": {"dice": 2},
	"Silver Wire": {"dice": 2, "mod": -1},
	"Dragon Tooth": {"ap": 2, "vs": {"Demon": 1}},
	"Soul": {"dice": 1, "reactions": [{"kind": "plus_one", "uses": 1, "scope": "challenge"}]},
	"Cold Iron": {"dice": 2, "vs": {"Elemental": 1}},
	"Diamond Dust": {"reactions": [{"kind": "plus_one", "uses": 2, "scope": "challenge"}]},
	"Adamantium": {"dice": 4, "ap": -3},
	"Holy Water": {"vs": {"Demon": -1}, "reactions": [{"kind": "reroll", "uses": 2, "scope": "quest_once"}]},
	"Emerald": {"dice": 1, "ap": 1, "reactions": [{"kind": "reroll", "uses": 1, "scope": "quest", "vs": "Giant"}]},
	"Mithril": {"vs": {"Elemental": 1}, "mithril": true},
	"Bronze": {"dice": 1, "bronze": true},
	"Aluminum": {"dice": 2, "no_sharpen": true},
	"Golden Apple": {"dice": -1, "skip_strength": true},
	"Rusty Bauble": {"dice": 2, "swap_on_draft": true},
	"Leather Grip": {"leather": true},
	"Jeweled Scabbard": {"dice": 1, "reactions": [{"kind": "keep", "uses": 2, "scope": "challenge", "challenge": "Strength"}]},
	"Sphinx's Milk": {"magic": 1},
	"Hyacinth": {"hyacinth": true},
	"Electrum": {"ap": -1, "electrum": true},
	"Beeswax": {"dice": -1, "ap": 2},
	"Lucky Fish Scale": {"dice": -2, "bonus_success": 1},
	"Gambler's Charm": {"dice": 1, "gamble": true},
}

var ingredients: Array = []  # {name, text, art, def}
var challenges: Array = []   # {name, kind, type, rule, art}
var errors: PackedStringArray = []


static func load_default() -> CardData:
	var d := CardData.new()
	d.load_files(INGREDIENTS_CSV, CHALLENGES_CSV)
	return d


func def(card_name: String) -> Dictionary:
	return DEFS.get(card_name, {})


func ingredient(card_name: String) -> Dictionary:
	for i in ingredients:
		if i.name == card_name:
			return i
	return {}


func load_files(ingredients_path: String, challenges_path: String) -> void:
	ingredients.clear()
	challenges.clear()
	errors.clear()
	for row in _read_csv(ingredients_path):
		var card_name: String = row[0].strip_edges()
		if not DEFS.has(card_name):
			errors.append("Ingredient '%s' has no rules definition" % card_name)
		ingredients.append({
			"name": card_name,
			"text": _clean(row[1]),
			"art": row[2].strip_edges() if row.size() > 2 else "",
			"def": def(card_name),
		})
	for card_name in DEFS:
		if ingredient(card_name).is_empty():
			errors.append("Rules definition '%s' has no card in the CSV" % card_name)

	for row in _read_csv(challenges_path):
		var card_name: String = row[0].strip_edges()
		var lines := _clean(row[1]).split("\n")
		var head := lines[0].split("-")
		var kind := head[0].strip_edges()
		var type := head[1].strip_edges() if head.size() > 1 else ""
		lines.remove_at(0)
		if kind != "Strength" and kind != "Sharpness":
			errors.append("Challenge '%s' has unknown kind '%s'" % [card_name, kind])
		if type not in MONSTER_TYPES:
			errors.append("Challenge '%s' has unknown monster type '%s'" % [card_name, type])
		if not Scoring.knows(card_name):
			errors.append("Challenge '%s' has no rules implementation" % card_name)
		challenges.append({
			"name": card_name,
			"kind": kind,
			"type": type,
			"rule": "\n".join(lines),
			"art": row[2].strip_edges() if row.size() > 2 else "",
		})


func _read_csv(path: String) -> Array:
	var rows := []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append("Can't open %s" % path)
		return rows
	f.get_csv_line()  # header
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 2 or row[0].strip_edges() == "":
			continue
		rows.append(row)
	return rows


## Trim each line, drop blank lines and collapse double spaces.
func _clean(text: String) -> String:
	var out := PackedStringArray()
	for line in text.split("\n"):
		var l := line.strip_edges()
		while l.contains("  "):
			l = l.replace("  ", " ")
		if l != "":
			out.append(l)
	return "\n".join(out)
