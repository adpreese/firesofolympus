extends "res://tests/test_case.gd"

const PATH := "user://test_save.json"
var data := CardData.load_default()


func test_save_round_trip() -> void:
	var g := FoGame.new(data)
	g.setup(["Ann", "Cpu"], [false, true], 1234)
	for i in 20:
		FoBot.step(g)
	FoSave.write(g, 1, PATH)
	var got := FoSave.read(data, PATH)
	eq(got.size(), 2, "save read back")
	if got.size() == 2:
		var r: FoGame = got[0]
		eq(r.log_lines, g.log_lines, "same game")
		eq([r.players[0].name, r.players[0].is_bot, r.players[1].is_bot], ["Ann", false, true], "seats")
		eq(got[1], 1, "seen results")
	FoSave.clear(PATH)
	eq(FoSave.read(data, PATH), [], "cleared")
	while g.phase != FoGame.Phase.GAME_OVER:
		FoBot.step(g)
	FoSave.write(g, 0, PATH)
	eq(FoSave.read(data, PATH), [], "finished games are not resumable")
	FoSave.clear(PATH)


func test_bad_saves_are_ignored() -> void:
	for text in ["", "not json", "[]", '{"format": 99}', '{"format": 1, "names": ["a"], "bots": [true], "moves": []}',
			'{"format": 1, "names": ["a", "b"], "bots": [true, true], "seed": 3, "moves": [["reserve", 1]]}']:
		var f := FileAccess.open(PATH, FileAccess.WRITE)
		f.store_string(text)
		f.close()
		eq(FoSave.read(data, PATH), [], "rejects %s" % text)
	FoSave.clear(PATH)
