extends Control
# PlayerSetup.tscn script

# Template material to clone for each player
const TERRITORY_MATERIAL_TEMPLATE = preload("res://materials/Map/territory_material_1.tres")

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
	# Pre-create materials for each player using the template
	create_player_materials()
	
	# Distribute territories randomly among players
	GameManager.distribute_territories_randomly()
	
	# Give initial armies for setup phase
	GameManager.assign_initial_armies()
	
	# Emit signals to notify of turn start
	GameManager.emit_signal("turn_changed", GameManager.get_current_player())
	GameManager.emit_signal("phase_changed", GameManager.current_phase)
	
	# Load the map scene
	get_tree().change_scene_to_file("res://Scenes/Map.tscn")

func create_player_materials():
	"""Clone template material for each player color and store in GameManager"""
	var materials_dict: Dictionary = {}
	var textures_enabled = SettingsManager.get_territory_textures_enabled()
	
	for player in GameManager.players:
		var material = TERRITORY_MATERIAL_TEMPLATE.duplicate()
		material.albedo_color = player.color
		
		# Remove texture if textures are disabled
		if not textures_enabled:
			material.albedo_texture = null
		
		# Store by color hash for fast lookup
		var color_hash = player.color.to_html()
		materials_dict[color_hash] = material
		
		print("PlayerSetup: Created material for %s (color: %s, texture: %s)" % 
			[player.player_name, color_hash, "enabled" if textures_enabled else "disabled"])
	
	# Store in GameManager for TerritoryColorManager to access
	GameManager.set_meta("territory_materials", materials_dict)
	print("PlayerSetup: Pre-created %d player materials" % materials_dict.size())
