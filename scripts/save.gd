class_name FoSave
extends RefCounted
## The single save slot: setup + seed + every move so far (FoGame.moves), rewritten after
## each move. Loading replays the moves, so a save can't drift from the rules engine; a save
## whose moves no longer apply (rules changed since) is treated as no save.

const PATH := "user://save.json"
const FORMAT := 1


## `seen`: how many FoGame.history entries the players have already dismissed.
static func write(g: FoGame, seen: int, path := PATH) -> void:
	var d := {
		"format": FORMAT,
		"version": ProjectSettings.get_setting("application/config/version", ""),
		"names": g.players.map(func(p): return p.name),
		"bots": g.players.map(func(p): return p.is_bot),
		"seed": g.seed_value,
		"moves": g.moves,
		"seen": seen,
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("Could not write save: %s" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify(d))
	f.close()


## [FoGame, seen] for the saved game, or [] if there is no usable save.
static func read(data: CardData, path := PATH) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return []
	var d = json.data
	if not (d is Dictionary) or int(d.get("format", 0)) != FORMAT:
		return []
	for k in ["names", "bots", "moves"]:
		if not (d.get(k) is Array):
			return []
	var names: Array = d.names.map(func(n): return str(n))
	var bots: Array = d.bots.map(func(b): return bool(b))
	if names.size() < 2 or names.size() != bots.size():
		return []
	var g := FoGame.replay(data, names, bots, int(d.get("seed", 0)), d.moves)
	if g == null or g.phase == FoGame.Phase.GAME_OVER:
		return []
	return [g, clampi(int(d.get("seen", 0)), 0, g.history.size())]


static func clear(path := PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
