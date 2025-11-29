extends Control
# PlayerSetup.tscn script

var current_player_setup_index: int = 0

@onready var title_label = $VBoxContainer/TitleLabel
@onready var name_input = $VBoxContainer/NameInput
@onready var color_option = $VBoxContainer/ColorContainer/ColorOptionButton
@onready var next_button = $VBoxContainer/NextButton

var available_colors: Dictionary = {
	"Red": Color.RED,
	"Blue": Color.BLUE,
	"Green": Color.GREEN,
	"Yellow": Color.YELLOW,
	"Magenta": Color.MAGENTA,
	"Cyan": Color.CYAN
}

var used_colors: Array[String] = []

func _ready():
	next_button.pressed.connect(_on_next_pressed)
	setup_color_options()
	update_ui()

func setup_color_options():
	color_option.clear()
	for color_name in available_colors.keys():
		if not used_colors.has(color_name):
			color_option.add_item(color_name)

func update_ui():
	title_label.text = "Player %d Setup" % (current_player_setup_index + 1)
	name_input.text = ""
	name_input.placeholder_text = "Enter player name"
	
	if current_player_setup_index >= GameManager.num_players - 1:
		next_button.text = "Start Game"
	else:
		next_button.text = "Next Player"

func _on_next_pressed():
	var player_name = name_input.text.strip_edges()
	if player_name.is_empty():
		player_name = "Player %d" % (current_player_setup_index + 1)
	
	var selected_color_name = color_option.get_item_text(color_option.selected)
	var selected_color = available_colors[selected_color_name]
	
	# Create player and add to GameManager
	var player = Player.new(current_player_setup_index + 1, player_name, selected_color)
	GameManager.players.append(player)
	used_colors.append(selected_color_name)
	
	current_player_setup_index += 1
	
	if current_player_setup_index >= GameManager.num_players:
		# All players set up, start game
		start_game()
	else:
		setup_color_options()
		update_ui()

func start_game():
	# Distribute territories randomly among players
	GameManager.distribute_territories_randomly()
	
	# Give initial armies for setup phase
	GameManager.assign_initial_armies()
	
	# Emit signals to notify of turn start
	GameManager.emit_signal("turn_changed", GameManager.get_current_player())
	GameManager.emit_signal("phase_changed", GameManager.current_phase)
	
	# Load the map scene
	get_tree().change_scene_to_file("res://Scenes/Map.tscn")
