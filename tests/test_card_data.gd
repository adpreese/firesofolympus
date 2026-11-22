extends "res://tests/test_case.gd"


func test_csvs_load_and_match_definitions() -> void:
	var d := CardData.load_default()
	eq(d.errors, PackedStringArray(), "card data errors")
	eq(d.ingredients.size(), 25, "ingredient count")
	eq(d.challenges.size(), 14, "challenge count")
	eq(d.challenges.filter(func(c): return c.kind == "Strength").size(), 7, "strength challenges")
	eq(d.challenges.filter(func(c): return c.kind == "Sharpness").size(), 7, "sharpness challenges")


func test_multiline_descriptions_parse() -> void:
	var d := CardData.load_default()
	eq(d.ingredient("Bronze").text, "+1D6\nEffect: 1s become 2s\nEffect: 6s become 5s", "Bronze text")
	var kraken: Dictionary = d.challenges.filter(func(c): return c.name == "Kraken")[0]
	eq(kraken.type, "Giant", "Kraken type")
	eq(kraken.rule, "Overall Result must greater than 20 or get -1d6", "Kraken rule")
