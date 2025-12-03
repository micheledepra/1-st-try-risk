extends Node

## SettingsManager - Autoload Singleton
## Handles game settings (save/load/apply)
## Organized by category for easy expansion

# Settings configuration (hierarchical structure)
var settings: Dictionary = {
	"game_mode": {
		"developer_mode": false  # Manual vs Auto battle resolution
	},
	"graphics": {
		"territory_textures_enabled": true  # Default: textures ON
	}
	# Future categories can be added here:
	# "audio": { "master_volume": 1.0, "music_volume": 0.8 }
	# "controls": { "mouse_sensitivity": 1.0 }
}

const SETTINGS_FILE_PATH = "user://settings.json"

func _ready():
	load_settings()
	apply_settings()
	print("SettingsManager: Initialized with settings from %s" % SETTINGS_FILE_PATH)

func load_settings():
	"""Load settings from disk or create defaults"""
	if not FileAccess.file_exists(SETTINGS_FILE_PATH):
		print("SettingsManager: No settings file found, creating defaults")
		save_settings()
		return
	
	var file = FileAccess.open(SETTINGS_FILE_PATH, FileAccess.READ)
	if file == null:
		push_warning("SettingsManager: Failed to open settings file")
		return
	
	var json = JSON.new()
	var parse_result = json.parse(file.get_as_text())
	file.close()
	
	if parse_result == OK:
		settings = json.data
		print("SettingsManager: Loaded settings successfully")
	else:
		push_warning("SettingsManager: Failed to parse settings.json, using defaults")

func save_settings():
	"""Save settings to disk"""
	var file = FileAccess.open(SETTINGS_FILE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SettingsManager: Failed to open settings file for writing")
		return
	
	file.store_string(JSON.stringify(settings, "\t"))
	file.close()
	print("SettingsManager: Settings saved to %s" % SETTINGS_FILE_PATH)

func apply_settings():
	"""Apply settings to game (called at startup and when changed)"""
	# Game mode settings
	if settings.has("game_mode"):
		GameManager.developer_mode = settings["game_mode"].get("developer_mode", false)
	
	# Graphics settings applied when materials are created
	print("SettingsManager: Settings applied")

# === Game Mode Settings ===

func get_developer_mode() -> bool:
	return settings.get("game_mode", {}).get("developer_mode", false)

func set_developer_mode(enabled: bool):
	if not settings.has("game_mode"):
		settings["game_mode"] = {}
	settings["game_mode"]["developer_mode"] = enabled
	GameManager.developer_mode = enabled
	save_settings()
	print("SettingsManager: Developer mode set to %s" % enabled)

# === Graphics Settings ===

func get_territory_textures_enabled() -> bool:
	return settings.get("graphics", {}).get("territory_textures_enabled", true)

func set_territory_textures_enabled(enabled: bool):
	if not settings.has("graphics"):
		settings["graphics"] = {}
	settings["graphics"]["territory_textures_enabled"] = enabled
	save_settings()
	print("SettingsManager: Territory textures set to %s" % enabled)

# === Future Categories (Template) ===

# func get_master_volume() -> float:
# 	return settings.get("audio", {}).get("master_volume", 1.0)
# 
# func set_master_volume(volume: float):
# 	if not settings.has("audio"):
# 		settings["audio"] = {}
# 	settings["audio"]["master_volume"] = volume
# 	AudioServer.set_bus_volume_db(0, linear_to_db(volume))
# 	save_settings()
