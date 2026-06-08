extends Node

## TerritoryTransparencyManager (now handles brightness-based color shading)
## Responsibility: Manage territory color brightness based on unit density within continents
## - Adjusts material color brightness from 60% (min units) to 100% (max units) per continent
## - Uses non-linear brightness curve for dark colors to maintain visibility
## - Updates automatically when army counts change
## - Coordinates with TerritoryColorManager for material management
## - Implements material pooling by owner/brightness combination for optimization

# Brightness configuration
const MIN_BRIGHTNESS: float = 0.60  # 60% brightness minimum
const MAX_BRIGHTNESS: float = 1.0   # 100% brightness maximum

# References
var color_manager: Node
var unit_manager: Node
var territories_cache: Dictionary = {}
var continents_cache: Dictionary = {}

# Material pooling optimization - shared materials by owner/brightness combination
var brightness_material_pool: Dictionary = {}  # "player_id:brightness_key" -> StandardMaterial3D
var territory_brightness: Dictionary = {}  # territory_name -> float (current brightness value)

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
	
	if not unit_manager:
		push_error("TerritoryTransparencyManager: TerritoryUnitManager not found!")
		return
	
	# Wait for color manager to initialize
	await get_tree().process_frame
	
	# Cache territory and continent data from color manager
	territories_cache = color_manager.territories_cache
	continents_cache = color_manager.continents_cache
	
	# Connect to GameManager signals for army changes
	var game_manager = get_node("/root/GameManager")
	if game_manager and game_manager.has_signal("armies_changed"):
		if not game_manager.armies_changed.is_connected(_on_armies_changed):
			game_manager.armies_changed.connect(_on_armies_changed)
	
	print("TerritoryTransparencyManager: Initialized for %d continents (brightness-based shading)" % continents_cache.size())
	
	# Initial brightness update for all continents
	for continent_name in continents_cache.keys():
		update_continent_brightness(continent_name)

func _on_armies_changed(territory_name: String, _army_count: int):
	"""Handle army count changes - update entire continent brightness"""
	# Find which continent this territory belongs to
	var continent_name = find_territory_continent(territory_name)
	if continent_name:
		update_continent_brightness(continent_name)

func find_territory_continent(territory_name: String) -> String:
	"""Find which continent a territory belongs to"""
	for continent_name in continents_cache.keys():
		var territories = continents_cache[continent_name]
		if territory_name in territories:
			return continent_name
	return ""

func update_continent_brightness(continent_name: String):
	"""Update color brightness for all territories in a continent based on relative unit density"""
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
	
	# If max_armies is 0, set all to minimum brightness
	if max_armies == 0:
		for territory_name in territories:
			set_territory_brightness(territory_name, MIN_BRIGHTNESS)
		return
	
	# Calculate and apply proportional brightness for each territory
	for territory_name in territories:
		var army_count = territory_armies[territory_name]
		var brightness: float
		
		if army_count == 0:
			# No units - minimum brightness
			brightness = MIN_BRIGHTNESS
		else:
			# Gradual brightness: MIN_BRIGHTNESS to MAX_BRIGHTNESS
			# Formula: brightness = MIN + (MAX - MIN) * (army_count / max_armies)
			# This creates a smooth gradient from 60% to 100% brightness
			var ratio = float(army_count) / float(max_armies)
			brightness = MIN_BRIGHTNESS + (MAX_BRIGHTNESS - MIN_BRIGHTNESS) * ratio
		
		set_territory_brightness(territory_name, brightness)

func set_territory_brightness(territory_name: String, brightness: float):
	"""Set the color brightness for a territory using material pooling optimization"""
	var territory = territories_cache.get(territory_name)
	if not territory:
		return
	
	# Clamp brightness to ensure minimum of 60%
	var clamped_brightness = clamp(brightness, MIN_BRIGHTNESS, MAX_BRIGHTNESS)
	
	# Store brightness for this territory
	territory_brightness[territory_name] = clamped_brightness
	
	# Get the territory's current owner
	var player_id = color_manager.territory_owners.get(territory_name, 0)
	
	# Get base player color
	var base_color = get_player_base_color(player_id)
	
	# Apply non-linear brightness curve for dark colors
	var adjusted_brightness = apply_brightness_curve(base_color, clamped_brightness)
	
	# Create material pool key for this owner/brightness combination
	# Round brightness to reduce material pool size (10 brightness levels)
	var brightness_key = int(adjusted_brightness * 10.0)
	var pool_key = "%d:%d" % [player_id, brightness_key]
	
	# Get or create shared material for this owner/brightness combination
	var material: StandardMaterial3D
	if brightness_material_pool.has(pool_key):
		material = brightness_material_pool[pool_key]
	else:
		# Create new material with brightened color
		material = StandardMaterial3D.new()
		material.albedo_color = Color(
			base_color.r * adjusted_brightness,
			base_color.g * adjusted_brightness,
			base_color.b * adjusted_brightness,
			1.0  # Always fully opaque
		)
		
		# Configure material for opaque rendering (no transparency)
		material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
		material.cull_mode = BaseMaterial3D.CULL_BACK
		material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		
		# Store in pool for reuse
		brightness_material_pool[pool_key] = material
	
	# Apply material to all mesh instances in territory
	var meshes = color_manager.find_all_mesh_instances(territory)
	for mesh in meshes:
		mesh.set_surface_override_material(0, material)

func get_player_base_color(player_id: int) -> Color:
	"""Get the base (unmodified) player color"""
	# Try to get from GameManager first
	var game_manager = get_node("/root/GameManager")
	if game_manager and not game_manager.players.is_empty():
		for player in game_manager.players:
			if player.id == player_id:
				return Color(player.color.r, player.color.g, player.color.b, 1.0)
	
	# Fallback to color manager's defaults
	return color_manager.get_player_color(player_id)

func apply_brightness_curve(base_color: Color, brightness: float) -> float:
	"""Apply non-linear brightness curve for dark colors to maintain visibility"""
	# Calculate perceived luminance of the base color
	# Using standard luminance formula: 0.299*R + 0.587*G + 0.114*B
	var luminance = 0.299 * base_color.r + 0.587 * base_color.g + 0.114 * base_color.b
	
	# For dark colors (low luminance), use less aggressive darkening
	# This prevents dark colors from becoming invisible at low brightness
	if luminance < 0.5:
		# Non-linear curve: sqrt interpolation for dark colors
		# This makes the darkening more gradual
		var adjusted = MIN_BRIGHTNESS + (brightness - MIN_BRIGHTNESS) * sqrt((brightness - MIN_BRIGHTNESS) / (MAX_BRIGHTNESS - MIN_BRIGHTNESS))
		return clamp(adjusted, MIN_BRIGHTNESS, MAX_BRIGHTNESS)
	else:
		# For bright colors, use linear brightness (original behavior)
		return brightness
