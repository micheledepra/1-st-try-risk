extends Node

## FortifyPhase - Handles army movement between connected territories

const TRANSFER_UNITS_UI = preload("res://UI/TransferUnitsUI.tscn")

var game_manager: Node
var map: Node3D
var map_ref: Node3D = null  # Reference to Map for UI updates
var ui_container: CanvasLayer

func _ready():
	game_manager = get_node("/root/GameManager")
	map = get_node("/root/Map")
	
	# Create UI container for modals
	ui_container = CanvasLayer.new()
	ui_container.layer = 100  # Above game UI
	add_child(ui_container)

func can_fortify(from_territory: String, to_territory: String, army_count: int) -> Dictionary:
	var result = {"valid": false, "error": ""}
	
	# Check if it's fortify phase
	if game_manager.current_phase != game_manager.GamePhase.FORTIFY:
		result.error = "Not in fortify phase"
		return result
	
	var current_player = game_manager.get_current_player()
	if current_player == null:
		result.error = "No current player"
		return result
	
	# Check if player owns both territories
	if not current_player.territories_owned.has(from_territory):
		result.error = "You don't own the source territory"
		return result
	
	if not current_player.territories_owned.has(to_territory):
		result.error = "You don't own the destination territory"
		return result
	
	# Check if territories are the same
	if from_territory == to_territory:
		result.error = "Cannot fortify to the same territory"
		return result
	
	# Check if enough armies (must leave at least 1)
	var available_armies = game_manager.get_territory_armies(from_territory)
	if available_armies <= 1:
		result.error = "Source territory must have at least 2 armies"
		return result
	
	if army_count < 1:
		result.error = "Must move at least 1 army"
		return result
	
	if army_count >= available_armies:
		result.error = "Must leave at least 1 army in source territory"
		return result
	
	# Check if territories are connected through player-owned territories
	if not game_manager.are_territories_connected(from_territory, to_territory, current_player.id):
		result.error = "Territories are not connected through your controlled territories"
		return result
	
	result.valid = true
	return result

func execute_fortify(from_territory: String, to_territory: String, army_count: int) -> bool:
	var validation = can_fortify(from_territory, to_territory, army_count)
	if not validation.valid:
		push_warning("Fortify failed: %s" % validation.error)
		return false
	
	# Move armies
	game_manager.add_armies_to_territory(from_territory, -army_count)
	game_manager.add_armies_to_territory(to_territory, army_count)
	
	# Update visuals
	if map and map.color_manager:
		map.color_manager.set_territory_armies(from_territory, game_manager.get_territory_armies(from_territory))
		map.color_manager.set_territory_armies(to_territory, game_manager.get_territory_armies(to_territory))
	
	print("Fortified: Moved %d armies from %s to %s" % [army_count, from_territory, to_territory])
	
	return true

func get_valid_fortify_sources() -> Array[String]:
	var sources: Array[String] = []
	
	var current_player = game_manager.get_current_player()
	if current_player == null:
		return sources
	
	# Only territories with 2+ armies can be sources
	for territory_name in current_player.territories_owned:
		if game_manager.get_territory_armies(territory_name) >= 2:
			sources.append(territory_name)
	
	return sources

func get_valid_fortify_destinations(from_territory: String) -> Array[String]:
	var destinations: Array[String] = []
	
	var current_player = game_manager.get_current_player()
	if current_player == null:
		return destinations
	
	# Check all owned territories for connectivity
	for territory_name in current_player.territories_owned:
		if territory_name == from_territory:
			continue
		
		if game_manager.are_territories_connected(from_territory, territory_name, current_player.id):
			destinations.append(territory_name)
	
	return destinations

func handle_fortify_transfer(from_territory: String, to_territory: String):
	"""Show TransferUnitsUI modal for fortify phase"""
	var validation = can_fortify(from_territory, to_territory, 1)  # Check with min armies
	if not validation.valid:
		print("Cannot fortify: %s" % validation.error)
		if map_ref and map_ref.game_ui:
			map_ref.game_ui.set_instruction_text("❌ Cannot fortify: %s" % validation.error)
		return
	
	# Show transfer UI
	var transfer_ui = TRANSFER_UNITS_UI.instantiate()
	ui_container.add_child(transfer_ui)
	
	var remaining_units = game_manager.get_territory_armies(from_territory)
	transfer_ui.setup(from_territory, to_territory, remaining_units)
	transfer_ui.transfer_confirmed.connect(_on_fortify_transfer_confirmed.bind(from_territory, to_territory))

func _on_fortify_transfer_confirmed(units: int, from_territory: String, to_territory: String):
	"""Handle fortify transfer confirmation from UI"""
	if execute_fortify(from_territory, to_territory, units):
		print("Fortified: Moved %d armies from %s to %s" % [units, from_territory, to_territory])
		if map_ref and map_ref.game_ui:
			map_ref.game_ui.set_instruction_text("✓ Fortified %s with %d armies" % [to_territory, units])
			# Reset instruction after brief delay
			await get_tree().create_timer(1.5).timeout
			if map_ref and map_ref.game_ui:
				map_ref.game_ui._update_ui()
	else:
		print("Fortify failed")
		if map_ref and map_ref.game_ui:
			map_ref.game_ui.set_instruction_text("❌ Fortify failed")

func get_max_armies_to_move(from_territory: String) -> int:
	var total = game_manager.get_territory_armies(from_territory)
	return max(0, total - 1)  # Must leave at least 1
