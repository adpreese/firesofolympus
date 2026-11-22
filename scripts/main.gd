extends Control


func _ready() -> void:
	print("Fires of Olympus %s on %s" % [ProjectSettings.get_setting("application/config/version"), OS.get_name()])
