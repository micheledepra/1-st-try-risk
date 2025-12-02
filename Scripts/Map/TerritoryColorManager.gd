extends Node

## TerritoryColorManager
## Responsibility: Manage visual state of territories
## - Territory colors (owner-based)
## - Army count labels
## - Ownership tracking
## NO INPUT HANDLING - All input handled by TerritoryInputManager

# Color configuration
@export var neutral_color: Color = Color(0.7, 0.7, 0.7, 1.0)
@export var player_colors: Array[Color] = [
	Color(0.8, 0.2, 0.2, 1.0),
	Color(0.2, 0.2, 0.8, 1.0),
	Color(0.2, 0.8, 0.2, 1.0),
	Color(0.8, 0.8, 0.2, 1.0),
	Color(0.8, 0.2, 0.8, 1.0),
	Color(0.2, 0.8, 0.8, 1.0),
]

# State tracking - Visual state only
var territory_owners: Dictionary = {}
var territory_armies: Dictionary = {}  # territory_name -> army count
var territories_cache: Dictionary = {}
var continents_cache: Dictionary = {}

# Object pool for Label3D nodes (Performance Improvement 1)
var label_pool: Array[Label3D] = []
var label_pool_max_size: int = 50  # Max labels to keep in pool

# Material cache to avoid duplicating materials (Performance Improvement 3)
var material_cache: Dictionary = {}  # Color -> StandardMaterial3D

# Batch update system (Performance Improvement 4)
var pending_visual_updates: Dictionary = {}  # territory_name -> bool
var update_scheduled: bool = false

# Visibility optimization (Performance Improvement 5)
var camera: Camera3D = null
var visibility_check_enabled: bool = true
var max_visible_distance: float = 100.0  # Distance beyond which territories are simplified

func _ready():
	call_deferred("setup_color_system")

func setup_color_system():
	var map = get_parent()
	# Validate parent is a Node3D (Map)
	if not map is Node3D:
		push_error("TerritoryColorManager: Parent is not a Node3D/Map node!")
		return
	
	var continents_node = map.get_node_or_null("Continents")
	
	if continents_node == null:
		push_error("TerritoryColorManager: No 'Continents' node found in Map!")
		return
	
	# Try to find the camera for visibility checks (Performance Improvement 5)
	camera = get_viewport().get_camera_3d()
	
	var total_territories = 0
	for continent in continents_node.get_children():
		var continent_territories = []
		
		for territory in continent.get_children():
			territories_cache[territory.name] = territory
			continent_territories.append(territory.name)
			set_territory_color(territory, neutral_color)
			# Initialize army count to 0
			territory_armies[territory.name] = 0
			total_territories += 1
		
		continents_cache[continent.name] = continent_territories
	
	print("TerritoryColorManager: Initialized with %d territories across %d continents" % [total_territories, continents_cache.size()])

func set_territory_owner(territory_name: String, player_id: int):
	territory_owners[territory_name] = player_id
	
	var territory = territories_cache.get(territory_name)
	if territory == null:
		push_warning("Territory not found: %s" % territory_name)
		return
	
	var color = neutral_color if player_id == 0 else get_player_color(player_id)
	set_territory_color(territory, color)
	print("Territory %s assigned to player %d" % [territory_name, player_id])

func set_continent_owner(continent_name: String, player_id: int):
	var territories = continents_cache.get(continent_name)
	if territories == null:
		push_warning("Continent not found: %s" % continent_name)
		return
	
	for territory_name in territories:
		set_territory_owner(territory_name, player_id)
	
	print("Continent %s assigned to player %d (%d territories)" % [continent_name, player_id, territories.size()])

func get_continent_owner(continent_name: String) -> int:
	var territories = continents_cache.get(continent_name, [])
	if territories.is_empty():
		return -1
	
	var first_owner = territory_owners.get(territories[0], 0)
	for territory_name in territories:
		if territory_owners.get(territory_name, 0) != first_owner:
			return -1
	
	return first_owner

func get_player_color(player_id: int) -> Color:
	# Try to get the actual color from the player in GameManager
	if GameManager and not GameManager.players.is_empty():
		for player in GameManager.players:
			if player.id == player_id:
				return player.color
	
	# Fallback to default colors if player not found
	var index = (player_id - 1) % player_colors.size()
	return player_colors[index]

func set_territory_color(territory: Node3D, color: Color):
	# Find ALL mesh instances in the territory (for multi-mesh territories like Great Britain)
	var meshes = find_all_mesh_instances(territory)
	
	if meshes.is_empty():
		push_warning("No MeshInstance3D found in territory: %s" % territory.name)
		return
	
	# Get or create cached material (Performance Improvement 3)
	var material = _get_or_create_material(color)
	
	# Apply cached material to all meshes
	for mesh in meshes:
		# Check surface exists before accessing it
		if mesh.get_surface_override_material_count() > 0 or mesh.mesh != null:
			mesh.set_surface_override_material(0, material)

# Material cache management (Performance Improvement 3)
func _get_or_create_material(color: Color) -> StandardMaterial3D:
	# Use color as key (convert to string for dictionary key)
	var color_key = color.to_html()
	
	if material_cache.has(color_key):
		return material_cache[color_key]
	
	# Create new material and cache it
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material_cache[color_key] = material
	
	return material

func find_mesh_instance(territory: Node3D) -> MeshInstance3D:
	for child in territory.get_children():
		if child is MeshInstance3D:
			return child
	return null

func find_all_mesh_instances(territory: Node3D) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	for child in territory.get_children():
		if child is MeshInstance3D:
			meshes.append(child)
	return meshes

func reset_all_territories():
	for territory_name in territories_cache.keys():
		set_territory_owner(territory_name, 0)

func get_territories_in_continent(continent_name: String) -> Array:
	return continents_cache.get(continent_name, [])

func get_all_continents() -> Array:
	return continents_cache.keys()

# Army management functions
func set_territory_armies(territory_name: String, count: int):
	territory_armies[territory_name] = count
	# Schedule batched update (Performance Improvement 4)
	_schedule_territory_update(territory_name)

func get_territory_armies(territory_name: String) -> int:
	return territory_armies.get(territory_name, 0)

func add_armies_to_territory(territory_name: String, count: int):
	var current = get_territory_armies(territory_name)
	set_territory_armies(territory_name, current + count)

func remove_armies_from_territory(territory_name: String, count: int) -> bool:
	var current = get_territory_armies(territory_name)
	if current >= count:
		set_territory_armies(territory_name, current - count)
		return true
	return false

func move_armies(from_territory: String, to_territory: String, count: int) -> bool:
	if remove_armies_from_territory(from_territory, count):
		add_armies_to_territory(to_territory, count)
		return true
	return false

func update_territory_label(territory_name: String):
	var territory = territories_cache.get(territory_name)
	if territory == null:
		return
	
	var label = find_label_3d(territory)
	if label == null:
		# Get label from pool or create new one
		label = _get_label_from_pool()
		label.name = "ArmyLabel"
		territory.add_child(label)
		label.position = Vector3(0, 0.05, 0)  # Slightly above territory
	
	var army_count = get_territory_armies(territory_name)
	label.text = str(army_count)
	
	# Apply visibility based on army count AND camera distance (Performance Improvement 5)
	if army_count > 0:
		# Check visibility only if label should be shown
		if visibility_check_enabled and camera and not _is_territory_near_camera(territory):
			label.visible = false
		else:
			label.visible = true
	else:
		label.visible = false

# Object pool management for Label3D (Performance Improvement 1)
func _get_label_from_pool() -> Label3D:
	if label_pool.size() > 0:
		return label_pool.pop_back()
	else:
		# Create new label with standard configuration
		var label = Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 32
		label.outline_size = 4
		label.outline_modulate = Color.BLACK
		return label

func _return_label_to_pool(label: Label3D):
	if label_pool.size() < label_pool_max_size:
		label.get_parent().remove_child(label)
		label_pool.append(label)
	else:
		label.queue_free()

func find_label_3d(territory: Node3D) -> Label3D:
	for child in territory.get_children():
		if child is Label3D:
			return child
	return null

# Batch update system (Performance Improvement 4)
func _schedule_territory_update(territory_name: String):
	pending_visual_updates[territory_name] = true
	
	if not update_scheduled:
		update_scheduled = true
		# Defer update to next frame to batch multiple changes
		call_deferred("_process_pending_updates")

func _process_pending_updates():
	for territory_name in pending_visual_updates.keys():
		update_territory_label(territory_name)
	
	pending_visual_updates.clear()
	update_scheduled = false

# Visibility optimization helpers (Performance Improvement 5)
func _is_territory_near_camera(territory: Node3D) -> bool:
	if not camera:
		return true  # If no camera, assume visible
	
	var distance = camera.global_position.distance_to(territory.global_position)
	return distance <= max_visible_distance

func set_visibility_optimization(enabled: bool):
	visibility_check_enabled = enabled

func set_max_visible_distance(distance: float):
	max_visible_distance = distance
