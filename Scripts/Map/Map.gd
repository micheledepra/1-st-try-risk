extends Node3D

var input_manager: Node
var color_manager: Node
var game_manager: Node
var reinforcement_phase: Node
var attack_phase: Node
var fortify_phase: Node

# Interaction state
var first_selected_territory: String = ""
var interaction_mode: String = ""  # "place", "attack", "fortify"

func _ready():
	# Wait for children to be ready first
	await get_tree().process_frame
	
	input_manager = get_node_or_null("TerritoryInputManager")
	color_manager = get_node_or_null("TerritoryColorManager")
	game_manager = get_node("/root/GameManager")
	
	# Create phase controllers
	reinforcement_phase = Node.new()
	reinforcement_phase.name = "ReinforcementPhase"
	reinforcement_phase.set_script(load("res://Scripts/ReinforcementPhase.gd"))
	add_child(reinforcement_phase)
	
	attack_phase = Node.new()
	attack_phase.name = "AttackPhase"
	attack_phase.set_script(load("res://Scripts/AttackPhase.gd"))
	add_child(attack_phase)
	
	fortify_phase = Node.new()
	fortify_phase.name = "FortifyPhase"
	fortify_phase.set_script(load("res://Scripts/FortifyPhase.gd"))
	add_child(fortify_phase)
	
	if input_manager == null:
		push_error("Map: TerritoryInputManager not found - input will not work!")
	else:
		# Connect to territory click signal from input manager (single source of truth)
		if not input_manager.territory_clicked.is_connected(_on_territory_clicked):
			input_manager.territory_clicked.connect(_on_territory_clicked)
			print("Map: Connected to TerritoryInputManager.territory_clicked")
	
	
	if color_manager == null:
		push_warning("Map: TerritoryColorManager not found - visual state disabled")
	
	print("Map initialized with continent-based structure and game systems")
	
	# Check if game is already set up from menu system
	if game_manager and not game_manager.players.is_empty():
		print("Map: Game already initialized with %d players" % game_manager.players.size())
		# Update visual state for existing territories
		update_territory_visuals()
	else:
		# Fallback: Wait a bit then start the game with default settings
		await get_tree().create_timer(1.0).timeout
		start_game()

func update_territory_visuals():
	# Update the visual representation of all territories based on current game state
	if not game_manager or not color_manager:
		return
	
	for territory_name in game_manager.territory_armies.keys():
		var owner = game_manager.get_territory_owner(territory_name)
		if owner:
			color_manager.set_territory_owner(territory_name, owner.id)

func set_territory_owner(territory_name: String, player_id: int):
	if color_manager:
		color_manager.set_territory_owner(territory_name, player_id)

func get_territory_owner(territory_name: String) -> int:
	if color_manager:
		return color_manager.territory_owners.get(territory_name, 0)
	return 0

func set_continent_owner(continent_name: String, player_id: int):
	if color_manager:
		color_manager.set_continent_owner(continent_name, player_id)

func get_continent_owner(continent_name: String) -> int:
	if color_manager:
		return color_manager.get_continent_owner(continent_name)
	return -1

func get_territories_in_continent(continent_name: String) -> Array:
	if color_manager:
		return color_manager.get_territories_in_continent(continent_name)
	return []

func get_all_continents() -> Array:
	if color_manager:
		return color_manager.get_all_continents()
	return []

func reset_all_territories():
	if color_manager:
		color_manager.reset_all_territories()

func start_game():
	if game_manager:
		# Start a 3-player game by default (can be made configurable)
		game_manager.start_new_game(3)
		print("Game started with 3 players")

func _on_territory_clicked(territory_name: String):
	if not game_manager:
		return
	
	var current_phase = game_manager.current_phase
	
	match current_phase:
		game_manager.GamePhase.SETUP, game_manager.GamePhase.REINFORCEMENT:
			handle_reinforcement_click(territory_name)
			
		game_manager.GamePhase.ATTACK:
			handle_attack_click(territory_name)
			
		game_manager.GamePhase.FORTIFY:
			handle_fortify_click(territory_name)

func handle_reinforcement_click(territory_name: String):
	if reinforcement_phase.place_army(territory_name):
		print("Army placed on %s" % territory_name)
	else:
		print("Cannot place army on %s" % territory_name)

func handle_attack_click(territory_name: String):
	if first_selected_territory == "":
		# Select attacking territory
		var current_player = game_manager.get_current_player()
		if current_player.territories_owned.has(territory_name):
			if game_manager.get_territory_armies(territory_name) >= 2:
				first_selected_territory = territory_name
				print("Selected %s to attack from" % territory_name)
			else:
				print("Territory needs at least 2 armies to attack")
		else:
			print("You don't own %s" % territory_name)
	else:
		# Execute attack
		var result = attack_phase.execute_attack(first_selected_territory, territory_name, 3)
		if result.success:
			print("Attack executed!")
		else:
			print("Cannot attack: %s" % result.get("error", "Unknown error"))
		
		first_selected_territory = ""

func handle_fortify_click(territory_name: String):
	if first_selected_territory == "":
		# Select source territory
		var current_player = game_manager.get_current_player()
		if current_player.territories_owned.has(territory_name):
			if game_manager.get_territory_armies(territory_name) >= 2:
				first_selected_territory = territory_name
				print("Selected %s to fortify from" % territory_name)
			else:
				print("Territory needs at least 2 armies to fortify")
		else:
			print("You don't own %s" % territory_name)
	else:
		# Execute fortify (move half the available armies by default)
		var max_armies = fortify_phase.get_max_armies_to_move(first_selected_territory)
		var armies_to_move = max(1, max_armies / 2)
		
		if fortify_phase.execute_fortify(first_selected_territory, territory_name, armies_to_move):
			print("Fortified %s with %d armies" % [territory_name, armies_to_move])
		else:
			print("Cannot fortify to %s" % territory_name)
		
		first_selected_territory = ""

func _input(_event):
	# Remove test keyboard shortcuts - game is now controlled through UI
	pass
