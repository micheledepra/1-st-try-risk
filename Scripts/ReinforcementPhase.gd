extends Node

## ReinforcementPhase - Handles army placement during reinforcement phase

var game_manager: Node
var map: Node3D

# Track armies placed in current phase per territory
var armies_placed_this_phase: Dictionary = {}  # territory_name -> count

func _ready():
	game_manager = get_node("/root/GameManager")
	map = get_node("/root/Map")
	
	# Connect to phase changes to reset tracking
	if game_manager:
		game_manager.phase_changed.connect(_on_phase_changed)
		game_manager.turn_changed.connect(_on_turn_changed)

func _on_phase_changed(_new_phase):
	# Reset tracking when phase changes
	armies_placed_this_phase.clear()

func _on_turn_changed(_player):
	# Reset tracking when turn changes (new player's reinforcement phase)
	armies_placed_this_phase.clear()

func can_place_army(territory_name: String) -> bool:
	var current_player = game_manager.get_current_player()
	if current_player == null:
		return false
	
	# Check if it's setup or reinforcement phase
	if game_manager.current_phase != game_manager.GamePhase.REINFORCEMENT and \
	   game_manager.current_phase != game_manager.GamePhase.SETUP:
		print("Cannot place armies - wrong phase")
		return false
	
	# Strict ownership check - player must own the territory
	if not current_player.territories_owned.has(territory_name):
		print("Cannot place armies on %s - not owned by Player %d" % [territory_name, current_player.id])
		return false
	
	# Check if player has armies to place
	if current_player.army_reserves <= 0:
		print("Cannot place armies - no armies remaining")
		return false
	
	return true

func place_army(territory_name: String, count: int = 1) -> bool:
	if count <= 0:
		return false
	
	if not can_place_army(territory_name):
		return false
	
	var current_player = game_manager.get_current_player()
	
	# Cap count to available armies
	var actual_count = min(count, current_player.army_reserves)
	if actual_count == 0:
		return false
	
	# Remove armies from reserves
	if not current_player.remove_armies(actual_count):
		return false
	
	# Add armies to territory
	game_manager.add_armies_to_territory(territory_name, actual_count)
	
	# Track armies placed in this phase
	if not armies_placed_this_phase.has(territory_name):
		armies_placed_this_phase[territory_name] = 0
	armies_placed_this_phase[territory_name] += actual_count
	
	# Update visuals
	if map and map.color_manager:
		map.color_manager.set_territory_armies(territory_name, game_manager.get_territory_armies(territory_name))
	
	print("Placed %d army(s) on %s. Player %d has %d armies remaining" % [actual_count, territory_name, current_player.id, current_player.army_reserves])
	
	# Auto-advance phase if no more armies to place
	if current_player.army_reserves == 0:
		if game_manager.current_phase == game_manager.GamePhase.REINFORCEMENT:
			print("All reinforcement armies placed. You can now attack or skip to fortify.")
	
	return true

func place_multiple_armies(territory_name: String, count: int) -> bool:
	return place_army(territory_name, count)

func can_remove_army(territory_name: String) -> bool:
	var current_player = game_manager.get_current_player()
	if current_player == null:
		return false
	
	# Check if it's setup or reinforcement phase
	if game_manager.current_phase != game_manager.GamePhase.REINFORCEMENT and \
	   game_manager.current_phase != game_manager.GamePhase.SETUP:
		print("Cannot remove armies - wrong phase")
		return false
	
	# Strict ownership check - player must own the territory
	if not current_player.territories_owned.has(territory_name):
		print("Cannot remove armies from %s - not owned by Player %d" % [territory_name, current_player.id])
		return false
	
	# Check if there are armies placed this phase to remove
	var armies_this_phase = armies_placed_this_phase.get(territory_name, 0)
	if armies_this_phase <= 0:
		print("Cannot remove armies from %s - no armies placed this phase" % territory_name)
		return false
	
	return true

func remove_army(territory_name: String, count: int = 1) -> bool:
	if count <= 0:
		return false
	
	if not can_remove_army(territory_name):
		return false
	
	var current_player = game_manager.get_current_player()
	
	# Can only remove armies placed in current phase
	var armies_this_phase = armies_placed_this_phase.get(territory_name, 0)
	var actual_count = min(count, armies_this_phase)
	
	if actual_count == 0:
		print("Cannot remove armies from %s - no armies placed this phase" % territory_name)
		return false
	
	# Remove armies from territory
	var current_armies = game_manager.get_territory_armies(territory_name)
	game_manager.set_territory_armies(territory_name, current_armies - actual_count)
	
	# Add armies back to reserves
	current_player.add_armies(actual_count)
	
	# Update tracking
	armies_placed_this_phase[territory_name] -= actual_count
	
	# Update visuals
	if map and map.color_manager:
		map.color_manager.set_territory_armies(territory_name, game_manager.get_territory_armies(territory_name))
	
	print("Removed %d army(s) from %s. Player %d now has %d armies to place" % [actual_count, territory_name, current_player.id, current_player.army_reserves])
	
	return true

func get_territories_for_placement() -> Array[String]:
	var current_player = game_manager.get_current_player()
	if current_player == null:
		return []
	
	var result: Array[String] = []
	result.assign(current_player.territories_owned)
	return result
