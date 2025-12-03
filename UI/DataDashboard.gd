extends Control

## DataDashboard - Comprehensive game statistics display
## Shows player stats table

var game_manager: Node

# Node references
@onready var player_table = %PlayerTable
@onready var close_button = %CloseButton

func _ready():
	game_manager = get_node("/root/GameManager")
	
	# Connect signals
	close_button.pressed.connect(_on_close_pressed)
	game_manager.stats_updated.connect(_on_stats_updated)
	
	# Initial update
	_update_player_table()

func _on_close_pressed():
	queue_free()

func _on_stats_updated():
	_update_player_table()

# ============================================================================
# PLAYER TABLE POPULATION
# ============================================================================

func _update_player_table():
	# Clear existing table
	for child in player_table.get_children():
		child.queue_free()
	
	# Create header row
	_add_table_header("Player")
	_add_table_header("Territories")
	_add_table_header("Units")
	_add_table_header("Next Reinf.")
	_add_table_header("K/D Ratio")
	_add_table_header("Strongest\nContinent")
	_add_table_header("Strongest\nTerritory")
	_add_table_header("Weakest\nTerritory")
	_add_table_header("Status")
	
	# Add data rows for each player
	for player in game_manager.players:
		_add_player_row(player)

func _add_table_header(text: String):
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color.YELLOW)
	player_table.add_child(label)

func _add_player_row(player):
	# Player name with color indicator
	var name_hbox = HBoxContainer.new()
	var color_rect = ColorRect.new()
	color_rect.color = player.color
	color_rect.custom_minimum_size = Vector2(20, 20)
	name_hbox.add_child(color_rect)
	var name_label = Label.new()
	name_label.text = " " + player.player_name
	name_hbox.add_child(name_label)
	player_table.add_child(name_hbox)
	
	# Territories owned
	var territories_count = player.get_territory_count()
	_add_table_cell(str(territories_count))
	
	# Total units deployed
	var total_units = _calculate_player_total_units(player)
	_add_table_cell(str(total_units))
	
	# Next reinforcements
	var next_reinforcements = _calculate_next_reinforcements(player)
	_add_table_cell(str(next_reinforcements))
	
	# K/D Ratio
	var kd_ratio = game_manager.get_kd_ratio(player.id)
	_add_table_cell("%.2f" % kd_ratio)
	
	# Strongest continent
	var strongest_continent = _get_strongest_continent(player)
	_add_table_cell(strongest_continent)
	
	# Strongest territory
	var strongest_territory = _get_strongest_territory(player)
	_add_table_cell(strongest_territory)
	
	# Weakest territory
	var weakest_territory = _get_weakest_territory(player)
	_add_table_cell(weakest_territory)
	
	# Status
	var status = "Eliminated" if player.is_eliminated else "Active"
	var status_label = Label.new()
	status_label.text = status
	if player.is_eliminated:
		status_label.add_theme_color_override("font_color", Color.RED)
	else:
		status_label.add_theme_color_override("font_color", Color.GREEN)
	player_table.add_child(status_label)

func _add_table_cell(text: String):
	var label = Label.new()
	label.text = text
	player_table.add_child(label)

func _calculate_player_total_units(player) -> int:
	var total = 0
	for territory_name in player.territories_owned:
		total += game_manager.get_territory_armies(territory_name)
	return total

func _calculate_next_reinforcements(player) -> int:
	if player.is_eliminated:
		return 0
	
	# Base: territories / 3 (minimum 1)
	var base = max(1, player.get_territory_count() / 3)
	
	# Add continent bonuses
	var bonus = 0
	for continent_name in game_manager.CONTINENT_BONUSES.keys():
		if game_manager.does_player_own_continent(player.id, continent_name):
			bonus += game_manager.CONTINENT_BONUSES[continent_name]
	
	return base + bonus

func _get_strongest_continent(player) -> String:
	var max_units = 0
	var strongest = "None"
	
	for continent_name in game_manager.CONTINENT_BONUSES.keys():
		var units_on_continent = _count_player_units_on_continent(player, continent_name)
		if units_on_continent > max_units:
			max_units = units_on_continent
			strongest = continent_name.capitalize()
	
	return strongest if max_units > 0 else "None"

func _count_player_units_on_continent(player, continent_name: String) -> int:
	var total = 0
	for territory_name in game_manager.map_data.keys():
		var territory_data = game_manager.map_data[territory_name]
		if territory_data.get("continent", "") == continent_name:
			if player.territories_owned.has(territory_name):
				total += game_manager.get_territory_armies(territory_name)
	return total

func _get_strongest_territory(player) -> String:
	"""Find territory with highest ratio of friendly vs strongest adjacent enemy"""
	if player.territories_owned.is_empty():
		return "None"
	
	var best_territory = ""
	var best_ratio = -1.0
	
	for territory_name in player.territories_owned:
		var friendly_units = game_manager.get_territory_armies(territory_name)
		var strongest_enemy_adjacent = _get_strongest_adjacent_enemy_units(territory_name, player)
		
		if strongest_enemy_adjacent == 0:
			# No enemies adjacent, safe territory
			if friendly_units > best_ratio:
				best_ratio = friendly_units
				best_territory = territory_name
		else:
			var ratio = float(friendly_units) / float(strongest_enemy_adjacent)
			if ratio > best_ratio:
				best_ratio = ratio
				best_territory = territory_name
	
	return best_territory if best_territory != "" else "None"

func _get_weakest_territory(player) -> String:
	"""Find territory with lowest ratio of friendly vs strongest adjacent enemy"""
	if player.territories_owned.is_empty():
		return "None"
	
	var worst_territory = ""
	var worst_ratio = 999999.0
	
	for territory_name in player.territories_owned:
		var friendly_units = game_manager.get_territory_armies(territory_name)
		var strongest_enemy_adjacent = _get_strongest_adjacent_enemy_units(territory_name, player)
		
		if strongest_enemy_adjacent > 0:
			var ratio = float(friendly_units) / float(strongest_enemy_adjacent)
			if ratio < worst_ratio:
				worst_ratio = ratio
				worst_territory = territory_name
	
	# If no territory with adjacent enemies found, return territory with fewest units
	if worst_territory == "":
		var min_units = 999999
		for territory_name in player.territories_owned:
			var units = game_manager.get_territory_armies(territory_name)
			if units < min_units:
				min_units = units
				worst_territory = territory_name
	
	return worst_territory if worst_territory != "" else "None"

func _get_strongest_adjacent_enemy_units(territory_name: String, player) -> int:
	"""Get the unit count of the strongest adjacent enemy territory"""
	var territory_data = game_manager.map_data.get(territory_name, {})
	var neighbors = territory_data.get("neighbors", [])
	
	var max_enemy_units = 0
	for neighbor_name in neighbors:
		var neighbor_owner = game_manager.get_territory_owner(neighbor_name)
		if neighbor_owner and neighbor_owner.id != player.id:
			var enemy_units = game_manager.get_territory_armies(neighbor_name)
			if enemy_units > max_enemy_units:
				max_enemy_units = enemy_units
	
	return max_enemy_units
