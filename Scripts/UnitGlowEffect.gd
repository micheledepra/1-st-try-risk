extends Node

## UnitGlowEffect - Autoload Singleton
## Manages temporary emission glow effects on units when hit by projectiles
## Uses direct property toggling on existing material instances (zero material creation overhead)

# Active glow tracking - unit_instance_id -> Timer
var active_glows: Dictionary = {}

# Original emission state - unit_instance_id -> Array[Dictionary]
# Each dict contains: {material: StandardMaterial3D, emission_enabled: bool, emission: Color, emission_energy_multiplier: float}
var original_emission_states: Dictionary = {}

# Constants
const GLOW_DURATION: float = 5.0
const EMISSION_MULTIPLIER: float = 5.0

func _ready() -> void:
	print("UnitGlowEffect: Initialized autoload singleton")

func apply_glow(unit: Node3D, color: Color, duration: float = GLOW_DURATION) -> void:
	"""Apply emission glow effect to unit by toggling emission properties on existing materials
	Ignores request if unit already has active glow"""
	print("[UnitGlowEffect] apply_glow() called - unit: %s, color: %s, duration: %.1fs" % [unit.name if unit else "NULL", color, duration])
	
	if not is_instance_valid(unit):
		print("[UnitGlowEffect] ABORT: Unit instance not valid")
		return
	
	var unit_id = unit.get_instance_id()
	print("[UnitGlowEffect] Unit ID: %d" % unit_id)
	
	# Ignore if already glowing
	if active_glows.has(unit_id):
		print("[UnitGlowEffect] IGNORE: Unit %d already has active glow" % unit_id)
		return
	
	# Find all mesh instances in unit
	var mesh_instances = _find_mesh_instances_recursive(unit)
	print("[UnitGlowEffect] Found %d MeshInstance3D nodes in unit" % mesh_instances.size())
	
	if mesh_instances.is_empty():
		push_warning("UnitGlowEffect: No MeshInstance3D found in unit")
		print("[UnitGlowEffect] ABORT: No mesh instances found")
		return
	
	# Store original emission states and enable emission on all materials
	var emission_states: Array = []
	var material_count = 0
	
	for mesh in mesh_instances:
		# Get actual surface count from mesh geometry (not override count which may be 0)
		var surface_count = mesh.mesh.get_surface_count() if mesh.mesh else 0
		print("[UnitGlowEffect] Processing mesh '%s' with %d surfaces" % [mesh.name, surface_count])
		
		for surface_idx in range(surface_count):
			# get_active_material returns override material if set, otherwise base material
			var mat = mesh.get_active_material(surface_idx)
			
			if not mat:
				print("[UnitGlowEffect]   Surface %d: No material found (skipping)" % surface_idx)
				continue
				
			if not mat is StandardMaterial3D:
				print("[UnitGlowEffect]   Surface %d: Not StandardMaterial3D (type: %s, skipping)" % [surface_idx, mat.get_class()])
				continue
			
			# Store original emission state
			var state = {
				"material": mat,
				"emission_enabled": mat.emission_enabled,
				"emission": mat.emission,
				"emission_energy_multiplier": mat.emission_energy_multiplier
			}
			emission_states.append(state)
			
			print("[UnitGlowEffect]   Surface %d: Stored original state (emission_enabled: %s, emission: %s, energy: %.1f)" % [surface_idx, mat.emission_enabled, mat.emission, mat.emission_energy_multiplier])
			
			# Enable emission with glow color
			mat.emission_enabled = true
			mat.emission = color * EMISSION_MULTIPLIER
			mat.emission_energy_multiplier = 50.0
			
			print("[UnitGlowEffect]   Surface %d: Applied glow (emission: %s, energy: 150.0)" % [surface_idx, mat.emission])
			material_count += 1
	
	if emission_states.is_empty():
		push_warning("UnitGlowEffect: No valid StandardMaterial3D found in unit")
		print("[UnitGlowEffect] ABORT: No valid materials found")
		return
	
	original_emission_states[unit_id] = emission_states
	print("[UnitGlowEffect] Stored emission states for %d materials" % emission_states.size())
	
	# Create cleanup timer
	var timer = get_tree().create_timer(duration)
	timer.timeout.connect(_restore_emission_states.bind(unit_id))
	active_glows[unit_id] = timer
	
	print("[UnitGlowEffect] SUCCESS: Glow applied to unit %d (%d materials modified, cleanup timer set for %.1fs)" % [unit_id, material_count, duration])

func cancel_glow(unit: Node3D) -> void:
	"""Cancel active glow effect and restore original emission states
	Called when unit is despawned/returned to pool"""
	print("[UnitGlowEffect] cancel_glow() called - unit: %s" % (unit.name if unit and is_instance_valid(unit) else "NULL/INVALID"))
	
	if not is_instance_valid(unit):
		print("[UnitGlowEffect] ABORT: Unit instance not valid")
		return
	
	var unit_id = unit.get_instance_id()
	
	if not active_glows.has(unit_id):
		print("[UnitGlowEffect] IGNORE: Unit %d has no active glow" % unit_id)
		return
	
	print("[UnitGlowEffect] Cancelling glow for unit %d" % unit_id)
	# Restore immediately
	_restore_emission_states(unit_id)

func _restore_emission_states(unit_id: int) -> void:
	"""Restore original emission properties after glow duration expires"""
	print("[UnitGlowEffect] _restore_emission_states() called - unit_id: %d" % unit_id)
	
	if not original_emission_states.has(unit_id):
		print("[UnitGlowEffect] ABORT: No emission states stored for unit %d" % unit_id)
		return
	
	var emission_states = original_emission_states[unit_id]
	print("[UnitGlowEffect] Restoring %d material emission states" % emission_states.size())
	
	# Restore emission properties to each material
	var restored_count = 0
	for state in emission_states:
		var mat = state["material"]
		if not is_instance_valid(mat):
			print("[UnitGlowEffect]   Material invalid (skipping)")
			continue
		
		mat.emission_enabled = state["emission_enabled"]
		mat.emission = state["emission"]
		mat.emission_energy_multiplier = state["emission_energy_multiplier"]
		restored_count += 1
	
	print("[UnitGlowEffect] Restored %d materials to original emission state" % restored_count)
	
	# Cleanup tracking dictionaries
	active_glows.erase(unit_id)
	original_emission_states.erase(unit_id)
	print("[UnitGlowEffect] Cleanup complete for unit %d" % unit_id)

func _find_mesh_instances_recursive(node: Node) -> Array[MeshInstance3D]:
	"""Recursively find all MeshInstance3D children"""
	var meshes: Array[MeshInstance3D] = []
	
	if node is MeshInstance3D:
		meshes.append(node)
	
	for child in node.get_children():
		meshes.append_array(_find_mesh_instances_recursive(child))
	
	return meshes
