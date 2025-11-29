extends Control
# MainMenu.tscn script

@onready var player_count_selector = $VBoxContainer/PlayerCountContainer/SpinBox
@onready var start_button = $VBoxContainer/StartButton

func _ready():
	start_button.pressed.connect(_on_start_pressed)
	player_count_selector.min_value = 2
	player_count_selector.max_value = 6
	player_count_selector.value = 3

func _on_start_pressed():
	var num_players = int(player_count_selector.value)
	GameManager.set_num_players(num_players)
	GameManager.start_player_setup()
	get_tree().change_scene_to_file("res://_0_Game basics/Scenes/PlayerSetup.tscn")
