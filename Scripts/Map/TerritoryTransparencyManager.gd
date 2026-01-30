extends Node

## TerritoryTransparencyManager (Saturation-based Color Shading)
## ===============================================================
## Responsibility: Manage territory color saturation based on unit density within continents
## This is the SOLE system for adjusting territory colors to display relative army strength.
##
## How it works:
## - Saturation ranges from MIN_SATURATION (60%) to MAX_SATURATION (100%)
## - Territory with most armies in continent = 100% saturation (vivid color)
## - Territory with least armies = 60% saturation (washed out color)
## - Creates visual feedback for army distribution at a glance
##
## Replaces the previous darkening system for a cleaner, unified approach.

# Saturation configuration - adjust these to control visual effect strength
const MIN_SATURATION: float = 0.60  # 60% saturation for minimum armies (washed out)
const MAX_SATURATION: float = 1.0   # 100% saturation for maximum armies (vivid)

# Signal emitted when saturation system is ready
signal saturation_system_ready

# References to other managers
var color_manager: Node = null
var unit_manager: Node = null
var territories_cache: Dictionary = {}
var continents_cache: Dictionary = {}

# Initialization state
var is_ready: bool = false

# Material pooling optimization - shared materials by owner/saturation combination
var saturation_material_pool: Dictionary = {}  # "player_id:saturation_key" -> StandardMaterial3D
var territory_saturation: Dictionary = {}  # territory_name -> float (current saturation factor)

func _ready():
	call_deferred("setup_transparency_manager")

func setup_transparency_manager():
	var map = get_parent()
	
	# Get references to other managers
	color_manager = map.get_node_or_null("TerritoryColorManager")
	unit_manager = map.get_node_or_null("TerritoryUnitManager")
	
	if not color_manager:
		push_error("TerritoryTransparencyManager: TerritoryColorManager not found!")
		return
	
	# Unit manager is optional - we can get armies from GameManager directly
	if not unit_manager:
		push_warning("TerritoryTransparencyManager: TerritoryUnitManager not found, using GameManager for army counts")
	
	# Wait for color manager to be fully ready (proper signal-based synchronization)
	if not color_manager.is_ready:
		print("TerritoryTransparencyManager: Waiting for TerritoryColorManager to be ready...")
		await color_manager.color_system_ready
	
	print("TerritoryTransparencyManager: TerritoryColorManager is ready, continuing setup...")
	
	# Cache territory and continent data from color manager
	territories_cache = color_manager.territories_cache
	continents_cache = color_manager.continents_cache
	
	# Connect to TerritoryColorManager signal for ownership changes
	if color_manager.has_signal("territory_color_changed"):
		if not color_manager.territory_color_changed.is_connected(_on_territory_color_changed):
			color_manager.territory_color_changed.connect(_on_territory_color_changed)
	
	# Connect to GameManager signals for army changes
	var game_manager = get_node("/root/GameManager")
	if game_manager and game_manager.has_signal("armies_changed"):
		if not game_manager.armies_changed.is_connected(_on_armies_changed):
			game_manager.armies_changed.connect(_on_armies_changed)
	
	# Mark as ready before initial saturation update
	is_ready = true
	
	print("TerritoryTransparencyManager: Initialized for %d continents (saturation-based shading)" % continents_cache.size())
	
	# Initial saturation update for all continents
	for continent_name in continents_cache.keys():
		update_continent_saturation(continent_name)
	
	# Emit ready signal for other managers (like NeighborDesaturator)
	saturation_system_ready.emit()
	print("TerritoryTransparencyManager: System ready, emitted saturation_system_ready signal")

func _on_armies_changed(territory_name: String, _army_count: int):
	"""Handle army count changes - update entire continent saturation"""
	# Find which continent this territory belongs to
	var continent_name = find_territory_continent(territory_name)
	if continent_name:
		update_continent_saturation(continent_name)

func _on_territory_color_changed(territory_name: String, _base_color: Color, _player_id: int):
	"""Handle territory ownership changes - reapply saturation to new base color"""
	# Find which continent this territory belongs to and recalculate saturation
	var continent_name = find_territory_continent(territory_name)
	if continent_name:
		# Use call_deferred to ensure the base color is set before we apply saturation
		call_deferred("update_continent_saturation", continent_name)

func find_territory_continent(territory_name: String) -> String:
	"""Find which continent a territory belongs to"""
	for continent_name in continents_cache.keys():
		var territories = continents_cache[continent_name]
		if territory_name in territories:
			return continent_name
	return ""

func update_continent_saturation(continent_name: String):
	"""Update color saturation for all territories in a continent based on relative unit density"""
	var territories = continents_cache.get(continent_name, [])
	if territories.is_empty():
		return
	
	var game_manager = get_node("/root/GameManager")
	if not game_manager:
		return
	
	# Collect army counts for all territories in this continent
	var territory_armies: Dictionary = {}
	var max_armies: int = 0
	
	for territory_name in territories:
		var army_count = game_manager.get_territory_armies(territory_name)
		territory_armies[territory_name] = army_count
		if army_count > max_armies:
			max_armies = army_count
	
	# If max_armies is 0, set all to minimum saturation
	if max_armies == 0:
		for territory_name in territories:
			set_territory_saturation(territory_name, MIN_SATURATION)
		return
	
	# Calculate and apply proportional saturation for each territory
	for territory_name in territories:
		var army_count = territory_armies[territory_name]
		var saturation_factor: float
		
		if army_count == 0:
			# No units - minimum saturation
			saturation_factor = MIN_SATURATION
		else:
			# Gradual saturation: MIN_SATURATION to MAX_SATURATION
			# Formula: saturation_factor = MIN + (MAX - MIN) * (army_count / max_armies)
			# This creates a smooth gradient from 60% to 100% saturation
			var ratio = float(army_count) / float(max_armies)
			saturation_factor = MIN_SATURATION + (MAX_SATURATION - MIN_SATURATION) * ratio
		
		set_territory_saturation(territory_name, saturation_factor)

func set_territory_saturation(territory_name: String, saturation_factor: float):
	"""Set the color saturation for a territory using material pooling optimization"""
	var territory = territories_cache.get(territory_name)
	if not territory:
		return
	
	# Clamp saturation factor to ensure minimum of 60%
	var clamped_saturation = clamp(saturation_factor, MIN_SATURATION, MAX_SATURATION)
	
	# Store saturation factor for this territory
	territory_saturation[territory_name] = clamped_saturation
	
	# Get the territory's current owner
	var player_id = color_manager.territory_owners.get(territory_name, 0)
	
	# Get base player color
	var base_color = get_player_base_color(player_id)
	
	# Convert base color to HSV components and apply saturation scaling
	var base_h = base_color.h
	var base_s = base_color.s
	var base_v = base_color.v
	var base_a = base_color.a
	var scaled_s = clamp(base_s * clamped_saturation, 0.0, 1.0)
	
	# Create material pool key for this owner/saturation combination
	# Round saturation to reduce material pool size (10 saturation levels)
	var saturation_key = int(clamped_saturation * 10.0)
	var pool_key = "%d:%d" % [player_id, saturation_key]
	
	# Get or create shared material for this owner/saturation combination
	var material: StandardMaterial3D
	if saturation_material_pool.has(pool_key):
		material = saturation_material_pool[pool_key]
	else:
		# Create saturation-adjusted material using color_manager's configured material function
		# This ensures saturation materials use the same export properties (metallic, roughness, etc.)
		var saturated_color = Color.from_hsv(base_h, scaled_s, base_v, base_a)
		material = color_manager.create_configured_material(saturated_color)
		
		# Store in pool for reuse
		saturation_material_pool[pool_key] = material
	
	# Apply material to all mesh instances in territory
	var meshes = color_manager.find_all_mesh_instances(territory)
	for mesh in meshes:
		mesh.set_surface_override_material(0, material)

func get_player_base_color(player_id: int) -> Color:
	"""Get the base (unmodified) player color from TerritoryColorManager"""
	if color_manager and color_manager.has_method("get_player_color"):
		return color_manager.get_player_color(player_id)
	
	# Fallback: Try to get from GameManager directly
	var game_manager = get_node("/root/GameManager")
	if game_manager and not game_manager.players.is_empty():
		for player in game_manager.players:
			if player.id == player_id:
				return Color(player.color.r, player.color.g, player.color.b, 1.0)
	
	# Final fallback - neutral gray
	if color_manager:
		return color_manager.neutral_color
	return Color(0.7, 0.7, 0.7, 1.0)

## Returns the current saturation-adjusted color for a territory
## This is the color WITH saturation grading applied (based on army count)
## Used by TerritoryNeighborDesaturator to apply hover effects on top of saturation grading
func get_saturation_adjusted_color(territory_name: String) -> Color:
	var player_id = 0
	if color_manager:
		player_id = color_manager.territory_owners.get(territory_name, 0)
	
	var base_color = get_player_base_color(player_id)
	var saturation_factor = territory_saturation.get(territory_name, MAX_SATURATION)
	
	# Apply saturation scaling using HSV
	var h = base_color.h
	var s = base_color.s
	var v = base_color.v
	var a = base_color.a
	var scaled_s = clamp(s * saturation_factor, 0.0, 1.0)
	
	return Color.from_hsv(h, scaled_s, v, a)

## Get the current saturation factor for a territory (for external queries)
func get_territory_saturation(territory_name: String) -> float:
	return territory_saturation.get(territory_name, MAX_SATURATION)

## Force refresh all saturation values (called after bulk territory updates)
func refresh_all_saturations():
	if not is_ready:
		return
	print("TerritoryTransparencyManager: Refreshing all saturation values...")
	for continent_name in continents_cache.keys():
		update_continent_saturation(continent_name)
	print("TerritoryTransparencyManager: Saturation refresh complete")
