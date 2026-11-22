extends "res://tests/test_case.gd"
## Every card's art and sound resolves to a real imported file, so a renamed image in
## the spreadsheet or assets/ fails here instead of silently showing a blank card.


func test_ingredient_art_resolves() -> void:
	var d := CardData.load_default()
	for c in d.ingredients:
		var path := FoAssets.ingredient_art_path(c.art)
		if c.name in FoAssets.MISSING_ART:
			eq(path, "", "%s now has art; remove it from MISSING_ART" % c.name)
		else:
			ok(path != "" and FoAssets.ingredient_art(c) != null, "%s art '%s'" % [c.name, c.art])


func test_challenge_art_resolves() -> void:
	var d := CardData.load_default()
	for c in d.challenges:
		ok(FoAssets.challenge_art(c) != null, "%s art '%s'" % [c.name, c.art])


func test_sounds_and_fonts_load() -> void:
	var d := CardData.load_default()
	for c in d.ingredients:
		ok(FoAssets.stream(FoAssets.ingredient_sound_path(c.name)) != null, "%s sound" % c.name)
	for event in FoAssets.SFX:
		ok(FoAssets.stream(FoAssets.sfx_path(event)) != null, "sfx '%s'" % event)
	ok(FoAssets.stream(FoAssets.MUSIC) is AudioStreamMP3, "music")
	ok(FoAssets.font("Cinzel-Bold.ttf") != null, "heading font")
	ok(FoAssets.font("SourceSerif4-Regular.ttf") != null, "body font")
