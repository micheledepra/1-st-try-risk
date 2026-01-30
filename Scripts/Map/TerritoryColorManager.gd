extends Node

## TerritoryColorManager
## Responsibility: Manage visual state of territories
## - Territory colors (owner-based)
## - Army count labels via 2D UI overlay (performance optimized)
## - Ownership tracking
## NO INPUT HANDLING - All input handled by TerritoryInputManager

# Template material - cloned for each player color, inherits all properties (texture, metallic, roughness, etc.)
const TERRITORY_MATERIAL_TEMPLATE = preload("res://materials/Map/territory_material_1.tres")

# Color configuration
@export var neutral_color: Color = Color(0.7, 0.7, 0.7, 1.0)  # Fully opaque
@export var player_colors: Array[Color] = [
	Color(0.8, 0.2, 0.2, 1.0),
	Color(0.2, 0.2, 0.8, 1.0),
	Color(0.199, 0.596, 0.199, 1.0),
	Color(0.8, 0.8, 0.2, 1.0),
	Color(0.8, 0.2, 0.8, 1.0),
	Color(0.2, 0.8, 0.8, 1.0),
]

# Material properties - configurable from inspector
@export_group("Material Properties")
@export_range(0.0, 1.0) var material_metallic: float = 1.0
@export_range(0.0, 1.0) var material_roughness: float = 0.5
@export_range(0.0, 1.0) var material_specular: float = 1.0
@export_range(0.0, 1.0) var material_transparency: float = 0.0

# State tracking - Visual state only
var territory_owners: Dictionary = {}
var territory_armies: Dictionary = {}  # territory_name -> army count
var territories_cache: Dictionary = {}
var continents_cache: Dictionary = {}

# Material pooling - per-continent-per-player (for independent transparency per continent)
var material_pool: Dictionary = {}  # continent_name -> Dictionary[player_id -> StandardMaterial3D]
var territory_materials: Dictionary = {}  # territory_name -> StandardMaterial3D (individual material reference)
var camera: Camera3D = null
var ui_overlay_layer: CanvasLayer = null
var territory_labels: Dictionary = {}  # territory_name -> Label (2D UI)

# Performance optimization: Cache territory centers (calculated once at startup)
var territory_centers_cache: Dictionary = {}  # territory_name -> Vector3
var label_update_counter: int = 0  # Frame counter for throttling label updates

func _ready():
	call_deferred("setup_color_system")

func setup_color_system():
	var map = get_parent()
	var continents_node = map.get_node_or_null("Continents")
	
	if continents_node == null:
		push_error("TerritoryColorManager: No 'Continents' node found in Map!")
		return
	
	# Find camera for 2D label projection
	camera = map.get_node_or_null("Camera3D")
	if not camera:
		push_error("TerritoryColorManager: No Camera3D found in Map!")
		return
	
	# Create or find UI overlay layer
	var canvas_layer = map.get_node_or_null("CanvasLayer")
	if not canvas_layer:
		canvas_layer = CanvasLayer.new()
		canvas_layer.name = "CanvasLayer"
		map.add_child(canvas_layer)
	
	# Create overlay container for labels
	ui_overlay_layer = canvas_layer
	var label_container = Control.new()
	label_container.name = "TerritoryLabels"
	label_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_overlay_layer.add_child(label_container)
	
	# FIRST PASS: Build caches only (no coloring yet)
	var total_territories = 0
	for continent in continents_node.get_children():
		# Skip any non-Node3D children (cameras, lights, etc.)
		if not continent is Node3D:
			continue
		
		var continent_territories = []
		
		for territory in continent.get_children():
			# Only process Node3D children that represent actual territories
			if not territory is Node3D:
				continue
			
			territories_cache[territory.name] = territory
			continent_territories.append(territory.name)
			# Initialize army count to 0
			territory_armies[territory.name] = 0
			total_territories += 1
		
		continents_cache[continent.name] = continent_territories
	
	print("TerritoryColorManager: Initialized with %d territories across %d continents" % [total_territories, continents_cache.size()])
	
	# Initialize material pool structure after caches are ready
	initialize_material_pool()
	
	# SECOND PASS: Apply initial neutral colors only if game hasn't started yet
	# If players already exist (from PlayerSetup), Map.gd will set correct colors immediately
	var skip_neutral_pass = GameManager and not GameManager.players.is_empty()
	if not skip_neutral_pass:
		for territory_name in territories_cache.keys():
			var territory = territories_cache[territory_name]
			set_territory_color(territory, neutral_color, 0)
		print("TerritoryColorManager: Applied neutral colors to all territories")
	else:
		print("TerritoryColorManager: Skipping neutral colors (players already exist)")
	
	# Initialize 2D UI labels for all territories
	initialize_all_territory_labels()
	
	# Pre-calculate territory centers once at startup (PERFORMANCE FIX)
	precalculate_territory_centers()
	
	print("TerritoryColorManager: System ready")

func initialize_material_pool():
	"""Initialize material pool structure - materials created per-continent-per-player on demand"""
	# Initialize empty pool structure for each continent
	for continent_name in continents_cache.keys():
		material_pool[continent_name] = {}
	
	print("TerritoryColorManager: Material pool structure initialized for %d continents" % continents_cache.size())

func set_territory_owner(territory_name: String, player_id: int):
	territory_owners[territory_name] = player_id
	
	var territory = territories_cache.get(territory_name)
	if territory == null:
		push_warning("Territory not found: %s" % territory_name)
		return
	
	var base_color = neutral_color if player_id == 0 else get_player_color(player_id)
	set_territory_color(territory, base_color, player_id)
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
	"""Get the color for a player from the player_colors array defined in this manager"""
	if player_id <= 0:
		return neutral_color
	
	# Use the player_colors array defined in TerritoryColorManager
	var index = (player_id - 1) % player_colors.size()
	return player_colors[index]

func get_territory_base_color(territory_name: String) -> Color:
	"""Get the base (unmodified) color for a territory based on owner"""
	var player_id = territory_owners.get(territory_name, 0)
	if player_id == 0:
		return neutral_color
	return get_player_color(player_id)

func set_territory_color(territory: Node3D, color: Color, player_id: int):
	"""Apply color using per-territory material for independent transparency control"""
	# Find ALL mesh instances in the territory (for multi-mesh territories like Great Britain)
	var meshes = find_all_mesh_instances(territory)
	
	if meshes.is_empty():
		push_warning("No MeshInstance3D found in territory: %s" % territory.name)
		return
	
	# Find which continent this territory belongs to
	var continent_name = find_territory_continent(territory.name)
	if continent_name.is_empty():
		push_warning("Territory %s not found in any continent" % territory.name)
		return
	
	# Try to get pre-created material from GameManager first (FAST PATH)
	var color_hash = color.to_html()
	var material: StandardMaterial3D = null
	
	if GameManager.has_meta("territory_materials"):
		var materials_dict = GameManager.get_meta("territory_materials")
		material = materials_dict.get(color_hash)
		
		if material:
			# Use pre-created material (inherits all template properties + player color)
			territory_materials[territory.name] = material
			for mesh in meshes:
				mesh.set_surface_override_material(0, material)
			return
	
	# FALLBACK: Get or create material for this territory (neutral color or edge cases)
	material = get_territory_material(territory.name, continent_name, player_id)
	if not material:
		var textures_enabled = SettingsManager.get_territory_textures_enabled()
		
		if textures_enabled:
			# Clone template (keeps texture) and apply export properties
			material = TERRITORY_MATERIAL_TEMPLATE.duplicate()
			material.albedo_color = Color(color.r, color.g, color.b, 1.0)
			
			# Apply export variable properties (override template defaults)
			material.metallic = material_metallic
			material.roughness = material_roughness
			material.metallic_specular = material_specular
			
			# Handle transparency based on export value
			if material_transparency > 0.0:
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				material.albedo_color.a = 1.0 - material_transparency
			else:
				material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
				material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
		else:
			# No textures - use clean material with export properties
			material = create_configured_material(Color(color.r, color.g, color.b, 1.0))
		
		# Store in continent pool and territory cache
		if not material_pool.has(continent_name):
			material_pool[continent_name] = {}
		material_pool[continent_name][player_id] = material
		territory_materials[territory.name] = material
	else:
		# Update existing material color (fully opaque)
		material.albedo_color = Color(color.r, color.g, color.b, 1.0)
		# Ensure opaque rendering flags are set
		if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		if material.depth_draw_mode != BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY:
			material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	
	# Apply material to all meshes
	for mesh in meshes:
		mesh.set_surface_override_material(0, material)

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

func find_territory_continent(territory_name: String) -> String:
	"""Find which continent a territory belongs to"""
	for continent_name in continents_cache.keys():
		var territories = continents_cache[continent_name]
		if territory_name in territories:
			return continent_name
	return ""

func create_configured_material(albedo_color: Color) -> StandardMaterial3D:
	"""Create a new StandardMaterial3D with export variable properties applied.
	Used for both standard territory materials and brightness materials."""
	var material = StandardMaterial3D.new()
	material.albedo_color = albedo_color
	
	# Apply export variable properties
	material.metallic = material_metallic
	material.roughness = material_roughness
	material.metallic_specular = material_specular
	
	# Handle transparency based on export value
	if material_transparency > 0.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color.a = 1.0 - material_transparency
	else:
		material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	
	return material

func get_territory_material(territory_name: String, continent_name: String, player_id: int) -> StandardMaterial3D:
	"""Get or create material for a specific territory in a continent"""
	# Check if territory already has a material
	if territory_materials.has(territory_name):
		var mat = territory_materials[territory_name]
		# Ensure opaque rendering flags are set
		if mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		if mat.depth_draw_mode != BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY:
			mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
		if mat.cull_mode != BaseMaterial3D.CULL_BACK:
			mat.cull_mode = BaseMaterial3D.CULL_BACK
		# Ensure full opacity
		if mat.albedo_color.a < 1.0:
			mat.albedo_color.a = 1.0
		return mat
	
	# Check if continent pool has a material for this player
	if material_pool.has(continent_name) and material_pool[continent_name].has(player_id):
		# Create a duplicate material for this territory
		var base_material = material_pool[continent_name][player_id]
		var new_material = base_material.duplicate()
		# Ensure opaque rendering flags
		new_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		new_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
		new_material.cull_mode = BaseMaterial3D.CULL_BACK
		new_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		# Ensure full opacity
		if new_material.albedo_color.a < 1.0:
			new_material.albedo_color.a = 1.0
		territory_materials[territory_name] = new_material
		return new_material
	
	return null

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
	update_territory_label(territory_name)

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
	"""Update 2D UI label position and text"""
	var territory = territories_cache.get(territory_name)
	if territory == null:
		return
	
	# Find or create 2D label
	var label = territory_labels.get(territory_name)
	if label == null:
		# Create 2D label in UI overlay
		var label_container = ui_overlay_layer.get_node_or_null("TerritoryLabels")
		if not label_container:
			return
		
		# Create background panel
		var panel = PanelContainer.new()
		panel.name = territory_name + "_Panel"
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label_container.add_child(panel)
		
		# Style panel with transparent background (no visible background)
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0)  # Fully transparent
		style.corner_radius_top_left = 20
		style.corner_radius_top_right = 20
		style.corner_radius_bottom_left = 20
		style.corner_radius_bottom_right = 20
		panel.add_theme_stylebox_override("panel", style)
		
		# Create label
		label = Label.new()
		label.name = territory_name + "_Label"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
		# Style label
		label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_font_size_override("font_size", 16)
		
		panel.add_child(label)
		panel.custom_minimum_size = Vector2(40, 40)
		
		territory_labels[territory_name] = {"label": label, "panel": panel}
	else:
		label = label["label"]
	
	# Update label text
	var army_count = get_territory_armies(territory_name)
	var display_count = max(1, army_count)
	label.text = str(display_count)

func _process(_delta: float):
	"""Update 2D label positions to follow 3D territories (OPTIMIZED)"""
	if not camera:
		return
	
	# Throttle updates: Only update every 3rd frame (~20 FPS instead of 60 FPS)
	label_update_counter += 1
	if label_update_counter % 3 != 0:
		return
	
	for territory_name in territory_labels.keys():
		var territory = territories_cache.get(territory_name)
		if not territory:
			continue
		
		var label_data = territory_labels[territory_name]
		var panel = label_data["panel"]
		
		# Use pre-calculated territory center (CACHED - no expensive AABB calculation!)
		var territory_center = territory_centers_cache.get(territory_name, Vector3.ZERO)
		var world_pos = territory.global_transform * (territory_center + Vector3(0, 0.3, 0))
		
		# Visibility culling: Quick check if territory is in camera frustum
		if not camera.is_position_in_frustum(world_pos):
			panel.visible = false
			continue
		
		# Project to 2D screen space
		var screen_pos = camera.unproject_position(world_pos)
		
		# Update panel position (centered)
		panel.position = screen_pos - panel.size / 2
		
		# Hide if behind camera
		var cam_to_pos = world_pos - camera.global_position
		var is_behind = cam_to_pos.dot(camera.global_transform.basis.z) > 0
		panel.visible = not is_behind

func calculate_territory_center(territory: Node3D) -> Vector3:
	"""Calculate the center point of a territory using mesh AABB"""
	var meshes = find_all_mesh_instances(territory)
	
	if meshes.is_empty():
		return Vector3.ZERO
	
	# Get combined AABB of all meshes in territory local space
	var combined_aabb: AABB
	var first = true
	
	for mesh_instance in meshes:
		var mesh_aabb = mesh_instance.get_aabb()
		
		# Transform mesh AABB to territory local space
		var mesh_to_territory = territory.global_transform.affine_inverse() * mesh_instance.global_transform
		
		# Transform AABB corners to territory space
		var corners = [
			mesh_to_territory * (mesh_aabb.position),
			mesh_to_territory * (mesh_aabb.position + Vector3(mesh_aabb.size.x, 0, 0)),
			mesh_to_territory * (mesh_aabb.position + Vector3(0, mesh_aabb.size.y, 0)),
			mesh_to_territory * (mesh_aabb.position + Vector3(0, 0, mesh_aabb.size.z)),
			mesh_to_territory * (mesh_aabb.position + Vector3(mesh_aabb.size.x, mesh_aabb.size.y, 0)),
			mesh_to_territory * (mesh_aabb.position + Vector3(mesh_aabb.size.x, 0, mesh_aabb.size.z)),
			mesh_to_territory * (mesh_aabb.position + Vector3(0, mesh_aabb.size.y, mesh_aabb.size.z)),
			mesh_to_territory * (mesh_aabb.position + mesh_aabb.size)
		]
		
		# Create AABB from transformed corners
		var transformed_aabb = AABB(corners[0], Vector3.ZERO)
		for corner in corners:
			transformed_aabb = transformed_aabb.expand(corner)
		
		if first:
			combined_aabb = transformed_aabb
			first = false
		else:
			combined_aabb = combined_aabb.merge(transformed_aabb)
	
	return combined_aabb.get_center()

func precalculate_territory_centers():
	"""Pre-calculate territory centers once at startup (PERFORMANCE FIX)"""
	for territory_name in territories_cache.keys():
		var territory = territories_cache[territory_name]
		territory_centers_cache[territory_name] = calculate_territory_center(territory)
	print("TerritoryColorManager: Pre-calculated centers for %d territories" % territory_centers_cache.size())

func initialize_all_territory_labels():
	"""Create 2D UI labels for all territories at startup"""
	for territory_name in territories_cache.keys():
		update_territory_label(territory_name)
	print("TerritoryColorManager: Initialized 2D UI labels for %d territories (performance optimized)" % territories_cache.size())

func set_labels_visible(visible: bool):
	"""Show or hide all territory labels (useful for standalone unit testing)"""
	if ui_overlay_layer:
		var label_container = ui_overlay_layer.get_node_or_null("TerritoryLabels")
		if label_container:
			label_container.visible = visible
