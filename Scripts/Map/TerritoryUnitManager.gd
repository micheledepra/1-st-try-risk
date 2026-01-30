extends Node

## TerritoryUnitManager (PHYSICS-FREE FORMATION SYSTEM)
## Manages 3D unit visualization using pre-designed formation templates
## - UnitGroup scenes contain 9 formation children (Formation1 through Formation9)
## - Each formation is a pre-positioned layout for that specific unit count
## - Units are parented directly to territories - move automatically with territory animations
## - Zero physics overhead: all physics bodies, scripts, and processing disabled
## - Pure visual representation using Node3D + MeshInstance3D only
## - Positioned via direct transform - no physics simulation whatsoever

# Unit scene preloads - full units for tactical mode (controllable)
const UNIT_PANTHER = preload("res://Scenes/Units/Import/Panther/Panther.tscn")
const UNIT_T34 = preload("res://Scenes/Units/Import/t34/t_34.tscn")

# Decorative unit variants for object pool (hittable but not controllable)
const UNIT_PANTHER_DECORATIVE = preload("res://Scenes/Units/Import/Panther/PantherDecorative.tscn")
const UNIT_T34_DECORATIVE = preload("res://Scenes/Units/Import/t34/t34Decorative.tscn")

# Unit group templates for formation data
const UNIT_GROUP_PANTHER = preload("res://Scenes/Units/Import/UnitGroupPanther.tscn")
const UNIT_GROUP_T34 = preload("res://Scenes/Units/Import/UnitGroupT3d.tscn")

# References
var game_manager: Node
var color_manager: Node
var territories_cache: Dictionary = {}

# Tracking spawned units - territory_name -> Array[Node3D]
var spawned_units: Dictionary = {}

# Track unit type assignments per player for consistency
var player_unit_types: Dictionary = {}  # player_name -> "panther" or "t34"

# Formation templates (extracted once at startup)
var formations_panther: Dictionary = {}  # formation_count (1-9) -> Array[Dictionary{position, rotation}]
var formations_t34: Dictionary = {}

# Object pooling for performance
var unit_pool_panther: Array[Node3D] = []
var unit_pool_t34: Array[Node3D] = []
const POOL_SIZE = 150  # Increased pool size for multiple territories

# Material pooling per player color - eliminates per-unit material duplication
var material_pools: Dictionary = {}  # player_color_hash -> Array[StandardMaterial3D] (one per surface)

# Global scale multiplier applied during fighter mode (shrinks ground units)
var fighter_scale_multiplier: float = 1.0

# Track controllable units for scale adjustments
var controllable_units: Array[Node3D] = []

# Configuration
@export var unit_scale: float = 2.0  # Fixed scale for all units
@export var formation_scale_panther: float = 3  # Scale factor for Panther formation spacing (1.0 = original design)
@export var formation_scale_t34: float = 4  # Scale factor for T34 formation spacing (1.0 = original design)
@export var unit_height_offset: float = 0.5  # Y offset above territory surface

# Unit type scale multipliers (based on collision shape sizes)
# Panther collision: Vector3(2.48, 2.12, 5.46) - length ~5.46
# T34 collision: Vector3(0.41, 0.18, 0.21) - length ~0.41
# Ratio: 5.46 / 0.41 = 13.3x difference
const PANTHER_SCALE_MULTIPLIER: float = 2.0  # Panther is reference size
const T34_SCALE_MULTIPLIER: float = 2.0  # Scale T34 up to match Panther size

func _ready():
	call_deferred("setup_unit_manager")

func setup_unit_manager():
	game_manager = get_node("/root/GameManager")
	color_manager = get_parent().get_node_or_null("TerritoryColorManager")
	
	if not game_manager:
		push_error("TerritoryUnitManager: GameManager not found!")
		return
	
	if not color_manager:
		push_error("TerritoryUnitManager: TerritoryColorManager not found!")
		return
	
	# Cache territory nodes from color manager
	territories_cache = color_manager.territories_cache
	
	# Extract formation templates from UnitGroup scenes
	extract_formation_templates()
	
	# Initialize object pools
	initialize_unit_pools()
	
	# Connect to GameManager signals for army changes
	if not game_manager.armies_changed.is_connected(_on_armies_changed):
		game_manager.armies_changed.connect(_on_armies_changed)
	
	print("TerritoryUnitManager: Initialized with %d territories" % territories_cache.size())
	print("TerritoryUnitManager: Formation templates extracted (Panther: %d, T34: %d)" % [formations_panther.size(), formations_t34.size()])
	print("TerritoryUnitManager: Physics-free unit pools initialized (%d per type, zero physics overhead)" % POOL_SIZE)

func extract_formation_templates():
	"""Extract all formation layouts (Formation1 through Formation9) from UnitGroup templates"""
	# Extract Panther formations (reference size - no normalization)
	var panther_group = UNIT_GROUP_PANTHER.instantiate()
	formations_panther = extract_formations_from_group(panther_group, PANTHER_SCALE_MULTIPLIER)
	panther_group.queue_free()
	
	# Extract T34 formations (normalize to Panther spacing)
	var t34_group = UNIT_GROUP_T34.instantiate()
	formations_t34 = extract_formations_from_group(t34_group, T34_SCALE_MULTIPLIER)
	t34_group.queue_free()

func extract_formations_from_group(unit_group: Node3D, scale_multiplier: float) -> Dictionary:
	"""Extract formation layouts from Formation1-Formation9 child nodes
	Normalizes positions based on unit scale multiplier to ensure consistent spacing"""
	var formations: Dictionary = {}
	
	# Look for Formation1 through Formation9
	for i in range(1, 10):
		var formation_name = "Formation%d" % i
		var formation_node = unit_group.get_node_or_null(formation_name)
		
		if not formation_node:
			push_warning("TerritoryUnitManager: %s not found in UnitGroup" % formation_name)
			continue
		
		# Extract unit positions from this formation
		var unit_positions: Array[Dictionary] = []
		
		# Get all children of the formation (these are the individual units)
		for unit in formation_node.get_children():
			if unit is Node3D:
				# Normalize position by scale multiplier to keep spacing consistent
				# If T34 is scaled up 13.3x, its formation positions should be scaled down 13.3x
				var normalized_position = unit.position / scale_multiplier
				unit_positions.append({
					"position": normalized_position,
					"rotation": unit.rotation
				})
		
		formations[i] = unit_positions
		print("TerritoryUnitManager: Extracted Formation%d with %d units (scale: %.2f)" % [i, unit_positions.size(), scale_multiplier])
	
	return formations

func initialize_unit_pools():
	"""Pre-create decorative unit instances for object pooling
	NOTE: Uses lightweight decorative scenes (hittable but not controllable)
	No runtime physics removal needed - scenes are pre-configured"""
	# Create Panther decorative pool
	for i in range(POOL_SIZE):
		var unit = UNIT_PANTHER_DECORATIVE.instantiate()
		unit.visible = false
		add_child(unit)
		unit_pool_panther.append(unit)
	
	# Create T34 decorative pool
	for i in range(POOL_SIZE):
		var unit = UNIT_T34_DECORATIVE.instantiate()
		unit.visible = false
		add_child(unit)
		unit_pool_t34.append(unit)
	
	print("TerritoryUnitManager: Initialized %d decorative units per type (hittable, physics-free)" % POOL_SIZE)

# =============================================================================
# PHYSICS STRIPPING FUNCTIONS REMOVED
# =============================================================================
# These functions are no longer needed because decorative scenes are
# pre-configured without heavy components. Decorative scenes include:
#   ✓ MeshInstance3D nodes (visual geometry)
#   ✓ Area3D + CollisionShape3D (lightweight hit detection)
#   ✓ DecorativeUnitHitbox script (minimal overhead)
#   ✗ NO RigidBody3D (no physics simulation)
#   ✗ NO TankController script (no movement/input processing)
#   ✗ NO Camera3D (no rendering overhead)
#   ✗ Processing disabled at scene level (zero CPU overhead)
# =============================================================================

func _on_armies_changed(territory_name: String, army_count: int):
	"""Update unit visualization when army count changes"""
	update_territory_units(territory_name)

func update_territory_units(territory_name: String):
	"""Update units on a territory based on current army count and owner"""
	var territory = territories_cache.get(territory_name)
	if not territory:
		push_warning("TerritoryUnitManager: Territory not found: %s" % territory_name)
		return
	
	var army_count = game_manager.get_territory_armies(territory_name)
	var owner = game_manager.get_territory_owner(territory_name)
	
	# Remove existing units if no armies or no owner
	if army_count <= 0 or not owner:
		despawn_territory_units(territory_name)
		return
	
	# Spawn or update units
	spawn_territory_units(territory_name, army_count, owner)

func spawn_territory_units(territory_name: String, army_count: int, owner):
	"""Spawn units using appropriate formation template"""
	var territory = territories_cache.get(territory_name)
	if not territory:
		return
	
	# Remove existing units first
	despawn_territory_units(territory_name)
	
	# Determine unit type based on player
	var player_name = owner.player_name
	var unit_type: String
	
	if player_unit_types.has(player_name):
		# Use previously assigned type for this player
		unit_type = player_unit_types[player_name]
	else:
		# Randomly assign unit type for this player (50/50 chance)
		unit_type = "panther" if randf() > 0.5 else "t34"
		player_unit_types[player_name] = unit_type
		print("TerritoryUnitManager: Assigned unit type '%s' to player %s" % [unit_type, player_name])
	
	# Get appropriate formation templates and pool
	var formations = formations_panther if unit_type == "panther" else formations_t34
	var unit_pool = unit_pool_panther if unit_type == "panther" else unit_pool_t34
	
	# Cap army count at 9 (max visual representation)
	var units_to_spawn = mini(army_count, 9)
	
	# Get the appropriate formation for this unit count
	var formation = formations.get(units_to_spawn)
	if not formation:
		push_error("TerritoryUnitManager: No formation found for %d units" % units_to_spawn)
		return
	
	# Calculate territory center for positioning
	var territory_center = calculate_territory_center(territory)
	
	# Select the appropriate formation scale based on unit type
	var active_formation_scale = formation_scale_panther if unit_type == "panther" else formation_scale_t34
	
	# Spawn units at formation positions
	var spawned_array: Array[Node3D] = []
	for unit_data in formation:
		# Get unit from pool
		var unit = get_unit_from_pool(unit_pool)
		if not unit:
			push_warning("TerritoryUnitManager: Unit pool exhausted for %s" % unit_type)
			break
		
		# Apply formation scale to maintain proper spacing
		var scaled_formation_pos = unit_data["position"] * active_formation_scale
		
		# Position unit relative to territory center
		unit.position = territory_center + scaled_formation_pos + Vector3(0, unit_height_offset, 0)
		unit.rotation = unit_data["rotation"]
		
		# Apply player color
		apply_player_color(unit, owner.color)
		
		# Reparent to territory - units become children and move with territory automatically
		# This eliminates need for physics-based following or position updates
		# Units will inherit all territory transforms, rotations, and animations
		if unit.get_parent():
			unit.get_parent().remove_child(unit)
		territory.add_child(unit)
		
		# Set scale with counteraction for parent territory scale and unit type normalization
		var territory_global_scale = territory.global_transform.basis.get_scale()
		var type_scale_multiplier = PANTHER_SCALE_MULTIPLIER if unit_type == "panther" else T34_SCALE_MULTIPLIER
		var final_scale = (unit_scale * type_scale_multiplier) / territory_global_scale.x  # Assuming uniform scale
		unit.scale = Vector3(final_scale, final_scale, final_scale)
		
		# Store effect scale metadata for projectile impact scaling
		var global_scale = final_scale * territory_global_scale.x
		unit.set_meta("effect_scale", global_scale)
		
		# Make visible
		unit.visible = true
		
		spawned_array.append(unit)
	
	# Store spawned units
	spawned_units[territory_name] = spawned_array
	
	print("TerritoryUnitManager: Spawned %d %s units on %s using Formation%d (formation_scale: %.2f)" % [spawned_array.size(), unit_type, territory_name, units_to_spawn, active_formation_scale])

func get_unit_from_pool(pool: Array[Node3D]) -> Node3D:
	"""Get a decorative unit from the pool
	NOTE: Returns lightweight decorative unit (hittable but not controllable)"""
	for unit in pool:
		if not unit.visible:
			return unit
	
	# Pool exhausted - should not happen with proper POOL_SIZE
	push_warning("TerritoryUnitManager: Pool exhausted, creating emergency decorative unit")
	return null

func return_unit_to_pool(unit: Node3D):
	"""Return unit to pool for reuse"""
	# Cancel any active glow effect before returning to pool
	if has_node("/root/UnitGlowEffect"):
		UnitGlowEffect.cancel_glow(unit)
	
	if unit.get_parent():
		unit.get_parent().remove_child(unit)
	
	add_child(unit)
	unit.visible = false
	unit.position = Vector3.ZERO
	unit.rotation = Vector3.ZERO
	
	# Clear any metadata
	for meta_key in unit.get_meta_list():
		unit.remove_meta(meta_key)

func despawn_territory_units(territory_name: String):
	"""Remove all units from a territory and return them to pool"""
	var units = spawned_units.get(territory_name, [])
	
	for unit in units:
		if is_instance_valid(unit):
			return_unit_to_pool(unit)
	
	spawned_units.erase(territory_name)

func calculate_territory_center(territory: Node3D) -> Vector3:
	"""Calculate the center point of a territory using mesh AABB"""
	var meshes = find_all_mesh_instances(territory)
	
	if meshes.is_empty():
		push_warning("TerritoryUnitManager: No meshes found in territory %s" % territory.name)
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

func apply_player_color(unit: Node3D, player_color: Color):
	"""Apply player color using pooled materials - zero duplication overhead
	Also sets player_color meta for projectile hit detection"""
	# Apply a slightly darker tint for the unit and reuse it for glow hit feedback
	var tinted_player_color := Color(player_color.r * 0.75, player_color.g * 0.75, player_color.b * 0.75, player_color.a)

	# Set meta on unit root for hit detection by projectiles (glow uses this color)
	unit.set_meta("player_color", tinted_player_color)
	
	var mesh_instances = find_all_mesh_instances_recursive(unit)
	
	# Get or create material pool for this player color
	var color_hash = tinted_player_color.to_html()
	var materials = material_pools.get(color_hash)
	
	if not materials:
		# Create material pool for this color
		materials = []
		material_pools[color_hash] = materials
	
	for mesh_instance in mesh_instances:
		var surface_count = mesh_instance.get_surface_override_material_count()
		
		for surface_idx in range(surface_count):
			# Ensure material pool has enough materials for all surfaces
			while materials.size() <= surface_idx:
				var new_mat = StandardMaterial3D.new()
				materials.append(new_mat)
			
			# Get pooled material for this surface
			var material = materials[surface_idx]
			
			# Get base material properties if not set
			if material.albedo_color == Color.WHITE:
				var base_material = mesh_instance.get_active_material(surface_idx)
				if base_material and base_material is StandardMaterial3D:
					# Copy base properties once
					material.albedo_color = base_material.albedo_color
					if base_material.albedo_texture:
						material.albedo_texture = base_material.albedo_texture
			
			# Apply player color tint (multiply with base color) using the darkened color
			var tinted_material = material.duplicate()  # Minimal duplication - only when applying tint
			tinted_material.albedo_color = material.albedo_color * tinted_player_color
			
			mesh_instance.set_surface_override_material(surface_idx, tinted_material)

func find_all_mesh_instances(territory: Node3D) -> Array[MeshInstance3D]:
	"""Find all MeshInstance3D nodes in territory (non-recursive)"""
	var meshes: Array[MeshInstance3D] = []
	for child in territory.get_children():
		if child is MeshInstance3D:
			meshes.append(child)
	return meshes

func find_all_mesh_instances_recursive(node: Node) -> Array[MeshInstance3D]:
	"""Recursively find all MeshInstance3D nodes"""
	var meshes: Array[MeshInstance3D] = []
	
	if node is MeshInstance3D:
		meshes.append(node)
	
	for child in node.get_children():
		meshes.append_array(find_all_mesh_instances_recursive(child))
	
	return meshes

# =============================================================================
# GLOBAL SCALE ADJUSTMENT (e.g., fighter mode shrink)
# =============================================================================

func set_fighter_scale_active(active: bool) -> void:
	"""Toggle fighter-mode scaling for all ground units (decorative + controllable)"""
	fighter_scale_multiplier = 0.5 if active else 1.0
	_apply_scale_multiplier_to_active_units()

func _apply_scale_multiplier_to_active_units() -> void:
	"""Re-apply the current scale multiplier to every tracked unit"""
	for territory_units in spawned_units.values():
		for unit in territory_units:
			_apply_scale_multiplier_to_unit(unit)

	for unit in controllable_units:
		_apply_scale_multiplier_to_unit(unit)

func _apply_scale_multiplier_to_unit(unit: Node3D, base_scale: float = -1.0) -> void:
	"""Scale a unit based on stored base scale and the active multiplier"""
	if not unit or not is_instance_valid(unit):
		return

	var resolved_base_scale = base_scale
	if resolved_base_scale <= 0.0:
		if unit.has_meta("base_scale"):
			resolved_base_scale = unit.get_meta("base_scale")
		else:
			# Fallback for legacy instances: derive base from current visible scale
			resolved_base_scale = unit.scale.x / max(fighter_scale_multiplier, 0.0001)

	unit.set_meta("base_scale", resolved_base_scale)
	var target_scale = resolved_base_scale * fighter_scale_multiplier
	unit.scale = Vector3(target_scale, target_scale, target_scale)

# =============================================================================
# TACTICAL MODE SUPPORT - Controllable unit spawning
# =============================================================================

func spawn_controllable_unit(territory_name: String, owner) -> Dictionary:
	"""Spawn a controllable unit on a territory (for tactical mode)
	IMPORTANT: Uses FULL scene with controller, camera, and physics.
	This is completely separate from decorative units (object pool).
	Decorative units = hittable but not controllable (Area3D only)
	Controllable units = full functionality (RigidBody3D, scripts, camera)"""
	var territory = territories_cache.get(territory_name)
	if not territory:
		push_error("TerritoryUnitManager: Territory not found: %s" % territory_name)
		return {}
	
	# Use the player's assigned unit type
	var player_name = owner.player_name
	var unit_type = player_unit_types.get(player_name, "panther")
	
	# ✓ CRITICAL: Use FULL scene for tactical mode, NOT decorative variant
	var unit_scene = UNIT_PANTHER if unit_type == "panther" else UNIT_T34
	
	# Instantiate FULL unit with controller and scripts enabled (NOT from pool)
	var unit = unit_scene.instantiate()
	
	# Disable physics interpolation to prevent deprecation warning
	unit.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	
	# Calculate position at territory center
	var center_pos = calculate_territory_center(territory)
	unit.position = center_pos + Vector3(0, unit_height_offset, 0)
	
	# Add to territory (parent it BEFORE setting scale)
	territory.add_child(unit)
	
	# Set scale with counteraction for parent territory scale and unit type normalization
	var territory_global_scale = territory.global_transform.basis.get_scale()
	var type_scale_multiplier = PANTHER_SCALE_MULTIPLIER if unit_type == "panther" else T34_SCALE_MULTIPLIER
	var base_scale = (unit_scale * type_scale_multiplier) / territory_global_scale.x  # Assuming uniform scale
	_apply_scale_multiplier_to_unit(unit, base_scale)
	
	# Store effect scale metadata for projectile impact scaling
	var global_scale = base_scale * territory_global_scale.x
	unit.set_meta("effect_scale", global_scale)
	
	# Apply player color
	apply_player_color(unit, owner.color)
	
	# Find camera in unit
	var unit_camera = find_camera_in_unit(unit)
	if not unit_camera:
		push_error("TerritoryUnitManager: No camera found in unit")
		unit.queue_free()
		return {}
	
	# Hide one decorative unit to compensate
	hide_one_decorative_unit(territory_name)

	# Track controllable units for fighter-mode scaling
	controllable_units.append(unit)
	
	print("TerritoryUnitManager: Spawned controllable %s on %s" % [owner.unit_type, territory_name])
	
	return {
		"unit": unit,
		"camera": unit_camera
	}

func despawn_controllable_unit(unit: Node3D, territory_name: String):
	"""Remove controllable unit and restore decorative unit"""
	if unit and is_instance_valid(unit):
		unit.queue_free()

	# Remove from controllable tracking
	controllable_units.erase(unit)
	
	# Restore one decorative unit
	restore_one_decorative_unit(territory_name)
	
	print("TerritoryUnitManager: Despawned controllable unit from %s" % territory_name)

func find_camera_in_unit(unit: Node3D) -> Camera3D:
	"""Recursively find Camera3D in unit hierarchy"""
	if unit is Camera3D:
		return unit
	
	for child in unit.get_children():
		var camera = find_camera_in_unit(child)
		if camera:
			return camera
	
	return null

func hide_one_decorative_unit(territory_name: String):
	"""Hide one decorative unit when spawning controllable unit"""
	var units = spawned_units.get(territory_name, [])
	
	if units.size() > 0:
		# Hide the last unit and mark it
		var unit = units[units.size() - 1]
		unit.visible = false
		unit.set_meta("hidden_for_controllable", true)

func restore_one_decorative_unit(territory_name: String):
	"""Restore hidden decorative unit after despawning controllable unit"""
	var units = spawned_units.get(territory_name, [])
	
	for unit in units:
		if is_instance_valid(unit) and unit.has_meta("hidden_for_controllable"):
			unit.visible = true
			unit.remove_meta("hidden_for_controllable")
			return

# =============================================================================
# USER-ADJUSTABLE FUNCTIONS
# =============================================================================

func set_unit_scale(new_scale: float):
	"""Adjust fixed scale for all units"""
	unit_scale = new_scale
	
	# Update all existing units
	for territory_name in spawned_units.keys():
		var units = spawned_units[territory_name]
		for unit in units:
			if is_instance_valid(unit):
				unit.scale = Vector3(unit_scale, unit_scale, unit_scale)
	
	print("TerritoryUnitManager: Unit scale set to %.2f" % unit_scale)

func set_unit_height_offset(new_offset: float):
	"""Adjust height offset for units above territory surface"""
	unit_height_offset = new_offset
	print("TerritoryUnitManager: Unit height offset set to %.2f" % unit_height_offset)
