extends Node

## AttackPhase - Handles combat mechanics and territory conquest

var game_manager: Node
var map: Node3D
# Cached reference to color_manager (Performance Improvement 2)
var color_manager: Node

# Dice rolling optimization (Performance Improvement 14)
var rng_cache: Array[int] = []
var rng_cache_index: int = 0
const RNG_CACHE_SIZE: int = 1000

func _ready():
	game_manager = get_node("/root/GameManager")
	# Cache parent map reference instead of using global path
	map = get_parent()
	if not map is Node3D:
		push_error("AttackPhase: Parent is not a Map node!")
		return
	# Cache color_manager to avoid repeated access
	if map:
		color_manager = map.get_node_or_null("TerritoryColorManager")
	
	# Pre-generate random numbers for dice rolls (Performance Improvement 14)
	_refill_rng_cache()

func can_attack(from_territory: String, to_territory: String) -> bool:
	# Check if it's attack phase
	if game_manager.current_phase != game_manager.GamePhase.ATTACK:
		return false
	
	var current_player = game_manager.get_current_player()
	if current_player == null:
		return false
	
	# Check if attacker owns the from_territory
	if not current_player.territories_owned.has(from_territory):
		return false
	
	# Check if attacker has enough armies (need at least 2, must leave 1 behind)
	if game_manager.get_territory_armies(from_territory) < 2:
		return false
	
	# Check if defender owns the to_territory (can't attack own territory)
	if current_player.territories_owned.has(to_territory):
		return false
	
	# Check if territories are adjacent
	var from_data = game_manager.map_data.get(from_territory, {})
	var neighbors = from_data.get("neighbors", [])
	if not neighbors.has(to_territory):
		return false
	
	return true

func execute_attack(from_territory: String, to_territory: String, attacker_dice_count: int = 3) -> Dictionary:
	if not can_attack(from_territory, to_territory):
		return {"success": false, "error": "Invalid attack"}
	
	var current_player = game_manager.get_current_player()
	var defender = game_manager.get_territory_owner(to_territory)
	
	# Determine actual dice counts
	var attacker_armies = game_manager.get_territory_armies(from_territory)
	attacker_dice_count = min(attacker_dice_count, min(3, attacker_armies - 1))  # Max 3, must leave 1
	
	var defender_armies = game_manager.get_territory_armies(to_territory)
	var defender_dice_count = min(2, defender_armies)  # Defender gets max 2 dice
	
	# Roll dice
	var attacker_rolls = roll_dice(attacker_dice_count)
	var defender_rolls = roll_dice(defender_dice_count)
	
	# Sort in descending order
	attacker_rolls.sort()
	attacker_rolls.reverse()
	defender_rolls.sort()
	defender_rolls.reverse()
	
	# Compare dice
	var attacker_losses = 0
	var defender_losses = 0
	var comparisons = min(attacker_rolls.size(), defender_rolls.size())
	
	for i in range(comparisons):
		if attacker_rolls[i] > defender_rolls[i]:
			defender_losses += 1
		else:
			attacker_losses += 1
	
	# Apply losses
	game_manager.add_armies_to_territory(from_territory, -attacker_losses)
	game_manager.add_armies_to_territory(to_territory, -defender_losses)
	
	# Update visuals using cached reference (Performance Improvement 2)
	if color_manager:
		color_manager.set_territory_armies(from_territory, game_manager.get_territory_armies(from_territory))
		color_manager.set_territory_armies(to_territory, game_manager.get_territory_armies(to_territory))
	
	# Check if territory was conquered
	var conquered = false
	if game_manager.get_territory_armies(to_territory) == 0:
		conquered = true
		conquer_territory(from_territory, to_territory, current_player, defender)
	
	var result = {
		"success": true,
		"attacker_rolls": attacker_rolls,
		"defender_rolls": defender_rolls,
		"attacker_losses": attacker_losses,
		"defender_losses": defender_losses,
		"conquered": conquered,
		"from_territory": from_territory,
		"to_territory": to_territory
	}
	
	print("Attack: %s (%d) -> %s (%d)" % [from_territory, attacker_armies, to_territory, defender_armies])
	print("Rolls - Attacker: %s, Defender: %s" % [str(attacker_rolls), str(defender_rolls)])
	print("Losses - Attacker: %d, Defender: %d" % [attacker_losses, defender_losses])
	if conquered:
		print("Territory conquered!")
	
	return result

func roll_dice(count: int) -> Array[int]:
	# Use pre-generated random numbers (Performance Improvement 14)
	var rolls: Array[int] = []
	
	for i in range(count):
		if rng_cache_index >= rng_cache.size():
			_refill_rng_cache()
		rolls.append(rng_cache[rng_cache_index])
		rng_cache_index += 1
	
	return rolls

func _refill_rng_cache():
	# Pre-generate random numbers in batches (Performance Improvement 14)
	rng_cache.clear()
	for i in range(RNG_CACHE_SIZE):
		rng_cache.append(randi_range(1, 6))  # Uniform distribution
	rng_cache_index = 0

func conquer_territory(from_territory: String, to_territory: String, attacker: Player, defender: Player):
	# Transfer ownership
	defender.remove_territory(to_territory)
	attacker.add_territory(to_territory)
	
	# Invalidate caches (Performance Improvements 8 & 9)
	game_manager.connectivity_dirty = true
	game_manager.continent_cache_dirty = true
	
	# Update map ownership
	if map:
		map.set_territory_owner(to_territory, attacker.id)
	
	# Move armies (must move at least attacker_dice_count used, but we'll move all but 1)
	var armies_to_move = game_manager.get_territory_armies(from_territory) - 1
	game_manager.add_armies_to_territory(from_territory, -armies_to_move)
	game_manager.set_territory_armies(to_territory, armies_to_move)
	
	# Update visuals using cached reference (Performance Improvement 2)
	if color_manager:
		color_manager.set_territory_armies(from_territory, game_manager.get_territory_armies(from_territory))
		color_manager.set_territory_armies(to_territory, game_manager.get_territory_armies(to_territory))
	
	# Check if defender was eliminated
	if defender.territories_owned.is_empty():
		game_manager.eliminate_player(defender)
	
	print("Player %d conquered %s from Player %d" % [attacker.id, to_territory, defender.id])

func get_valid_attack_targets(from_territory: String) -> Array[String]:
	var targets: Array[String] = []
	
	var current_player = game_manager.get_current_player()
	if current_player == null or not current_player.territories_owned.has(from_territory):
		return targets
	
	if game_manager.get_territory_armies(from_territory) < 2:
		return targets
	
	var from_data = game_manager.map_data.get(from_territory, {})
	var neighbors = from_data.get("neighbors", [])
	
	for neighbor in neighbors:
		# Only include territories owned by other players
		if not current_player.territories_owned.has(neighbor):
			targets.append(neighbor)
	
	return targets

func get_territories_that_can_attack() -> Array[String]:
	var result: Array[String] = []
	
	var current_player = game_manager.get_current_player()
	if current_player == null:
		return result
	
	for territory_name in current_player.territories_owned:
		if game_manager.get_territory_armies(territory_name) >= 2:
			var targets = get_valid_attack_targets(territory_name)
			if not targets.is_empty():
				result.append(territory_name)
	
	return result
