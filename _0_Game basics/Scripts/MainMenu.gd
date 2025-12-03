extends Control
# MainMenu.tscn script

@onready var player_count_selector = $VBoxContainer/PlayerCountContainer/SpinBox
@onready var developer_mode_toggle = $SettingsContainer/SettingsVBox/GameModeCategory/GameModeContent/GameModeContainer/DeveloperModeToggle
@onready var texture_toggle = $SettingsContainer/SettingsVBox/GraphicsCategory/GraphicsContent/GraphicsContainer/TextureToggle
@onready var start_button = $VBoxContainer/StartButton

func _ready():
	start_button.pressed.connect(_on_start_pressed)
	player_count_selector.min_value = 2
	player_count_selector.max_value = 6
	player_count_selector.value = 3
	
	# Setup game mode toggle
	developer_mode_toggle.toggled.connect(_on_developer_mode_toggled)
	developer_mode_toggle.button_pressed = SettingsManager.get_developer_mode()
	
	# Setup texture toggle
	texture_toggle.toggled.connect(_on_texture_toggle_toggled)
	texture_toggle.button_pressed = SettingsManager.get_territory_textures_enabled()
	
	print("MainMenu: Loaded settings - Developer Mode: %s, Textures: %s" % 
		[developer_mode_toggle.button_pressed, texture_toggle.button_pressed])

func _on_developer_mode_toggled(toggled_on: bool):
	SettingsManager.set_developer_mode(toggled_on)
	if toggled_on:
		print("MainMenu: Game Mode set to Developer (Manual Battle Resolution)")
	else:
		print("MainMenu: Game Mode set to Auto Resolution")

func _on_texture_toggle_toggled(pressed: bool):
	SettingsManager.set_territory_textures_enabled(pressed)
	print("MainMenu: Territory textures set to %s" % ("Enabled" if pressed else "Disabled"))

func _on_start_pressed():
	var num_players = int(player_count_selector.value)
	GameManager.set_num_players(num_players)
	GameManager.start_player_setup()
	get_tree().change_scene_to_file("res://_0_Game basics/Scenes/PlayerSetup.tscn")
