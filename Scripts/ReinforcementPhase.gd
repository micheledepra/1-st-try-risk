extends Node

## ReinforcementPhase - Handles army placement during reinforcement phase

var game_manager: Node
var map: Node3D
# Cached reference to color_manager (Performance Improvement 2)
var color_manager: Node

func _ready():
	game_manager = get_node("/root/GameManager")
	# Cache parent map reference instead of using global path
	map = get_parent()
	# Cache color_manager to avoid repeated access
	if map:
		color_manager = map.get_node_or_null("TerritoryColorManager")

func can_place_army(territory_name: String) -> bool:
	var current_player = game_manager.get_current_player()
	if current_player == null:
		return false
	
	# Check if it's reinforcement phase
	if game_manager.current_phase != game_manager.GamePhase.REINFORCEMENT and \
	   game_manager.current_phase != game_manager.GamePhase.SETUP:
		return false
	
	# Check if player owns the territory
	if not current_player.territories_owned.has(territory_name):
		return false
	
	# Check if player has armies to place
	if current_player.army_reserves <= 0:
		return false
	
	return true

func place_army(territory_name: String) -> bool:
	if not can_place_army(territory_name):
		return false
	
	var current_player = game_manager.get_current_player()
	
	# Remove army from reserves
	if not current_player.remove_armies(1):
		return false
	
	# Add army to territory
	game_manager.add_armies_to_territory(territory_name, 1)
	
	# Update visuals using cached reference (Performance Improvement 2)
	if color_manager:
		color_manager.set_territory_armies(territory_name, game_manager.get_territory_armies(territory_name))
	
	print("Placed 1 army on %s. Player %d has %d armies remaining" % [territory_name, current_player.id, current_player.army_reserves])
	
	# Auto-advance phase if no more armies to place
	if current_player.army_reserves == 0:
		if game_manager.current_phase == game_manager.GamePhase.REINFORCEMENT:
			print("All reinforcement armies placed. You can now attack or skip to fortify.")
	
	return true

func place_multiple_armies(territory_name: String, count: int) -> bool:
	if count <= 0:
		return false
	
	var current_player = game_manager.get_current_player()
	if current_player == null or current_player.army_reserves < count:
		return false
	
	# Validate before making changes
	if not can_place_army(territory_name):
		return false
	
	# Place all armies at once
	if not current_player.remove_armies(count):
		return false
	
	game_manager.add_armies_to_territory(territory_name, count)
	
	# Update visuals using cached reference (Performance Improvement 2)
	if color_manager:
		color_manager.set_territory_armies(territory_name, game_manager.get_territory_armies(territory_name))
	
	print("Placed %d armies on %s. Player %d has %d armies remaining" % [count, territory_name, current_player.id, current_player.army_reserves])
	
	return true

func get_territories_for_placement() -> Array[String]:
	var current_player = game_manager.get_current_player()
	if current_player == null:
		return []
	
	var result: Array[String] = []
	result.assign(current_player.territories_owned)
	return result
