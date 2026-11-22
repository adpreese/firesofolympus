class_name FoSettings
extends RefCounted
## Player preferences, kept in user://settings.cfg (IndexedDB on the web build).

const PATH := "user://settings.cfg"
const CPU_SPEEDS := ["Slow", "Normal", "Fast"]
const CPU_DELAYS := [0.9, 0.45, 0.15]  # seconds between CPU decisions
const TEXT_SIZES := ["Normal", "Large", "Larger"]
const TEXT_SCALES := [1.0, 1.15, 1.3]

static var sfx_volume := 1.0    # 0..1, 0 = off
static var music_volume := 0.7
static var cpu_speed := 1       # index into CPU_SPEEDS
static var text_size := 0       # index into TEXT_SIZES
static var reduce_motion := false
static var haptics := true


static func load_file() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	sfx_volume = clampf(float(cf.get_value("audio", "sfx", sfx_volume)), 0.0, 1.0)
	music_volume = clampf(float(cf.get_value("audio", "music", music_volume)), 0.0, 1.0)
	cpu_speed = clampi(int(cf.get_value("game", "cpu_speed", cpu_speed)), 0, CPU_SPEEDS.size() - 1)
	text_size = clampi(int(cf.get_value("display", "text_size", text_size)), 0, TEXT_SIZES.size() - 1)
	reduce_motion = bool(cf.get_value("display", "reduce_motion", reduce_motion))
	haptics = bool(cf.get_value("game", "haptics", haptics))


static func save_file() -> void:
	var cf := ConfigFile.new()
	cf.set_value("audio", "sfx", sfx_volume)
	cf.set_value("audio", "music", music_volume)
	cf.set_value("game", "cpu_speed", cpu_speed)
	cf.set_value("display", "text_size", text_size)
	cf.set_value("display", "reduce_motion", reduce_motion)
	cf.set_value("game", "haptics", haptics)
	cf.save(PATH)


static func cpu_delay() -> float:
	return CPU_DELAYS[cpu_speed]


static func text_scale() -> float:
	return TEXT_SCALES[text_size]
