extends Node

## AttackPhase - Handles combat mechanics and territory conquest

const ATTACK_RESOLUTION_UI = preload("res://UI/AttackResolutionUI.tscn")
const TRANSFER_UNITS_UI = preload("res://UI/TransferUnitsUI.tscn")

var game_manager: Node
var map: Node3D
var ui_container: CanvasLayer
var selected_attacker: String = ""
var selected_defender: String = ""

# For territory-based interaction
var map_ref: Node3D = null

func _ready():
	game_manager = get_node("/root/GameManager")
	map = get_node("/root/Map")
	
	# Create UI container for modals
	ui_container = CanvasLayer.new()
	ui_container.layer = 100  # Above game UI
	add_child(ui_container)

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
	
	# Get initial army counts
	var attacker_armies = game_manager.get_territory_armies(from_territory)
	var defender_armies = game_manager.get_territory_armies(to_territory)
	
	var attacker_losses = 0
	var defender_losses = 0
	var attacker_rolls = []
	var defender_rolls = []
	
	if game_manager.developer_mode:
		# Developer mode: Use UI modals for manual battle resolution
		# This is handled by handle_territory_clicked() method
		print("ERROR: execute_attack() should not be called in developer mode!")
		print("Use handle_territory_clicked() for UI-based attacks")
		return {"success": false, "error": "Use UI modals in developer mode"}
	else:
		# Normal mode: Use dice rolls
		# Determine actual dice counts
		attacker_dice_count = min(attacker_dice_count, min(3, attacker_armies - 1))  # Max 3, must leave 1
		var defender_dice_count = min(2, defender_armies)  # Defender gets max 2 dice
		
		# Roll dice
		attacker_rolls = roll_dice(attacker_dice_count)
		defender_rolls = roll_dice(defender_dice_count)
		
		# Sort in descending order
		attacker_rolls.sort()
		attacker_rolls.reverse()
		defender_rolls.sort()
		defender_rolls.reverse()
		
		# Compare dice
		var comparisons = min(attacker_rolls.size(), defender_rolls.size())
		
		for i in range(comparisons):
			if attacker_rolls[i] > defender_rolls[i]:
				defender_losses += 1
			else:
				attacker_losses += 1
	
	# Apply losses
	game_manager.add_armies_to_territory(from_territory, -attacker_losses)
	game_manager.add_armies_to_territory(to_territory, -defender_losses)
	
	# Update visuals
	if map and map.color_manager:
		map.color_manager.set_territory_armies(from_territory, game_manager.get_territory_armies(from_territory))
		map.color_manager.set_territory_armies(to_territory, game_manager.get_territory_armies(to_territory))
	
	# Check if territory was conquered
	var conquered = false
	if game_manager.get_territory_armies(to_territory) == 0:
		conquered = true
		conquer_territory(from_territory, to_territory, current_player, defender)
	
	# Record battle statistics
	game_manager.record_battle(
		current_player.id,
		defender.id,
		from_territory,
		to_territory,
		attacker_armies,
		defender_armies,
		attacker_losses,
		defender_losses,
		conquered
	)
	
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

func handle_territory_clicked(territory_name: String):
	"""Handle territory clicks during attack phase for UI-based attacks"""
	if game_manager.current_phase != game_manager.GamePhase.ATTACK:
		return
	
	var current_player = game_manager.get_current_player()
	if current_player == null:
		return
	
	if selected_attacker == "":
		# First click - select attacking territory
		if not current_player.territories_owned.has(territory_name):
			print("You don't own this territory!")
			if map_ref and map_ref.game_ui:
				map_ref.game_ui.set_instruction_text("❌ You don't own this territory!")
			return
		
		if game_manager.get_territory_armies(territory_name) <= 1:
			print("Need at least 2 armies to attack!")
			if map_ref and map_ref.game_ui:
				map_ref.game_ui.set_instruction_text("❌ Need at least 2 armies to attack!")
			return
		
		selected_attacker = territory_name
		print("Selected attacker: %s" % territory_name)
		
		# Update UI instruction
		if map_ref and map_ref.game_ui:
			map_ref.game_ui.set_instruction_text("✓ Selected %s. Click enemy territory to attack" % territory_name)
	
	else:
		# Second click - select defending territory
		if current_player.territories_owned.has(territory_name):
			# Clicked own territory - reset selection
			selected_attacker = ""
			selected_defender = ""
			if map_ref and map_ref.game_ui:
				map_ref.game_ui.set_instruction_text("❌ Selection cancelled. Click your territory to attack")
			print("Selection cancelled")
			return
		
		# Check adjacency
		var from_data = game_manager.map_data.get(selected_attacker, {})
		var neighbors = from_data.get("neighbors", [])
		if not neighbors.has(territory_name):
			print("Territories are not adjacent!")
			if map_ref and map_ref.game_ui:
				map_ref.game_ui.set_instruction_text("❌ Territories are not adjacent!")
			selected_attacker = ""
			return
		
		selected_defender = territory_name
		print("Attack: %s → %s" % [selected_attacker, selected_defender])
		
		# Show attack resolution UI
		_show_attack_resolution_ui()

func _show_attack_resolution_ui():
	var resolution_ui = ATTACK_RESOLUTION_UI.instantiate()
	ui_container.add_child(resolution_ui)
	
	var attacker_color = game_manager.get_current_player().color
	var defender_owner = game_manager.get_territory_owner(selected_defender)
	var defender_color = defender_owner.color if defender_owner else Color.GRAY
	
	var attacker_units = game_manager.get_territory_armies(selected_attacker)
	var defender_units = game_manager.get_territory_armies(selected_defender)
	
	resolution_ui.setup(
		selected_attacker,
		attacker_units,
		attacker_color,
		selected_defender,
		defender_units,
		defender_color
	)
	
	resolution_ui.resolution_confirmed.connect(_on_attack_resolved)

func _on_attack_resolved(attacker_remaining: int, defender_remaining: int):
	var attacker_initial = game_manager.get_territory_armies(selected_attacker)
	var defender_initial = game_manager.get_territory_armies(selected_defender)
	
	var attacker_losses = attacker_initial - attacker_remaining
	var defender_losses = defender_initial - defender_remaining
	
	print("Battle result: Attacker lost %d, Defender lost %d" % [attacker_losses, defender_losses])
	
	var current_player = game_manager.get_current_player()
	var defender_owner = game_manager.get_territory_owner(selected_defender)
	var conquered = (defender_remaining == 0)
	
	# Record battle statistics
	if defender_owner:
		game_manager.record_battle(
			current_player.id,
			defender_owner.id,
			selected_attacker,
			selected_defender,
			attacker_initial,
			defender_initial,
			attacker_losses,
			defender_losses,
			conquered
		)
	
	# Update armies
	game_manager.set_territory_armies(selected_attacker, attacker_remaining)
	
	# Update visuals for attacker
	if map and map.color_manager:
		map.color_manager.set_territory_armies(selected_attacker, attacker_remaining)
	
	if defender_remaining == 0:
		# Territory conquered!
		_handle_conquest(attacker_remaining)
	else:
		# Defender survived
		game_manager.set_territory_armies(selected_defender, defender_remaining)
		
		# Update visuals for defender
		if map and map.color_manager:
			map.color_manager.set_territory_armies(selected_defender, defender_remaining)
		
		_reset_selection()

func _handle_conquest(attacker_remaining: int):
	print("Territory conquered: %s" % selected_defender)
	
	# Transfer ownership
	var old_owner = game_manager.get_territory_owner(selected_defender)
	var new_owner = game_manager.get_current_player()
	
	if old_owner:
		old_owner.remove_territory(selected_defender)
	new_owner.add_territory(selected_defender)
	
	# Update map ownership
	if map:
		map.set_territory_owner(selected_defender, new_owner.id)
	
	# Update color on map
	if map and map.color_manager:
		map.color_manager.update_territory_color(selected_defender, new_owner.color)
	
	# Show transfer UI
	_show_transfer_ui(attacker_remaining)

func _show_transfer_ui(attacker_remaining: int):
	var transfer_ui = TRANSFER_UNITS_UI.instantiate()
	ui_container.add_child(transfer_ui)
	
	transfer_ui.setup(selected_attacker, selected_defender, attacker_remaining)
	transfer_ui.transfer_confirmed.connect(_on_transfer_confirmed)

func _on_transfer_confirmed(units: int):
	# Transfer units from attacker to conquered territory
	var new_attacker_units = game_manager.get_territory_armies(selected_attacker) - units
	game_manager.set_territory_armies(selected_attacker, new_attacker_units)
	game_manager.set_territory_armies(selected_defender, units)
	
	print("Transferred %d units to %s" % [units, selected_defender])
	
	# Update visuals
	if map and map.color_manager:
		map.color_manager.set_territory_armies(selected_attacker, new_attacker_units)
		map.color_manager.set_territory_armies(selected_defender, units)
	
	# Check if defender was eliminated
	var old_owner = game_manager.get_territory_owner(selected_defender)
	if old_owner and old_owner.territories_owned.is_empty():
		game_manager.eliminate_player(old_owner)
	
	# Check for victory
	game_manager.check_victory()
	
	_reset_selection()

func reset_selection():
	"""Public method to reset attack selection (called by Map for right-click cancel)"""
	_reset_selection()

func _reset_selection():
	selected_attacker = ""
	selected_defender = ""
	
	if map_ref and map_ref.game_ui:
		map_ref.game_ui.set_instruction_text("Click your territory with 2+ armies to attack")

func roll_dice(count: int) -> Array[int]:
	var rolls: Array[int] = []
	for i in range(count):
		rolls.append(randi() % 6 + 1)
	return rolls

func conquer_territory(from_territory: String, to_territory: String, attacker: Player, defender: Player):
	# Transfer ownership
	defender.remove_territory(to_territory)
	attacker.add_territory(to_territory)
	
	# Update map ownership
	if map:
		map.set_territory_owner(to_territory, attacker.id)
	
	# Prompt for armies to transfer
	var available_armies = game_manager.get_territory_armies(from_territory) - 1  # Must leave 1
	var armies_to_move = available_armies  # Default: move all available
	
	print("\n=== TERRITORY CONQUERED ===")
	print("%s has %d armies (must leave 1 behind)" % [from_territory, game_manager.get_territory_armies(from_territory)])
	print("How many armies to transfer to %s? (1 to %d)" % [to_territory, available_armies])
	print("[Default: Moving all %d available armies]" % armies_to_move)
	# Note: In actual implementation, you would show a UI dialog here for user input
	
	# Move armies
	game_manager.add_armies_to_territory(from_territory, -armies_to_move)
	game_manager.set_territory_armies(to_territory, armies_to_move)
	
	# Update visuals
	if map and map.color_manager:
		map.color_manager.set_territory_armies(from_territory, game_manager.get_territory_armies(from_territory))
		map.color_manager.set_territory_armies(to_territory, game_manager.get_territory_armies(to_territory))
	
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
