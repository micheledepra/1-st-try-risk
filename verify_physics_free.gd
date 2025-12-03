"""
Physics-Free Unit Verification Script
Run this in Godot to verify that decorative units have no physics components.
"""

extends Node

func _ready():
	verify_units()

func verify_units():
	print("=== PHYSICS-FREE UNIT VERIFICATION ===")
	
	var unit_manager = get_node_or_null("/root/Map/TerritoryUnitManager")
	if not unit_manager:
		print("ERROR: TerritoryUnitManager not found!")
		return
	
	print("Found TerritoryUnitManager")
	
	# Check pool units
	var panther_pool = unit_manager.get("unit_pool_panther")
	var t34_pool = unit_manager.get("unit_pool_t34")
	
	if panther_pool:
		print("\nChecking Panther Pool (%d units):" % panther_pool.size())
		check_pool(panther_pool, "Panther")
	
	if t34_pool:
		print("\nChecking T34 Pool (%d units):" % t34_pool.size())
		check_pool(t34_pool, "T34")
	
	# Check spawned units
	var spawned_units = unit_manager.get("spawned_units")
	if spawned_units:
		print("\nChecking Spawned Units (%d territories):" % spawned_units.size())
		for territory_name in spawned_units.keys():
			var units = spawned_units[territory_name]
			print("  Territory '%s': %d units" % [territory_name, units.size()])
			for i in range(min(units.size(), 3)):  # Check first 3
				check_unit(units[i], "  Unit %d" % i)
	
	print("\n=== VERIFICATION COMPLETE ===")

func check_pool(pool: Array, pool_name: String):
	var sample_size = min(5, pool.size())
	print("  Checking %d sample units from %s pool..." % [sample_size, pool_name])
	
	for i in range(sample_size):
		var unit = pool[i]
		check_unit(unit, "  Pool Unit %d" % i)

func check_unit(unit: Node3D, label: String):
	var issues = []
	
	# Check for scripts
	if unit.get_script() != null:
		issues.append("HAS SCRIPT")
	
	# Check for physics bodies
	var physics_nodes = find_physics_nodes(unit)
	if physics_nodes.size() > 0:
		issues.append("HAS PHYSICS: %s" % str(physics_nodes))
	
	# Check processing
	if unit.is_processing():
		issues.append("PROCESSING ENABLED")
	if unit.is_physics_processing():
		issues.append("PHYSICS PROCESSING ENABLED")
	if unit.is_processing_input():
		issues.append("INPUT PROCESSING ENABLED")
	if unit.is_processing_unhandled_input():
		issues.append("UNHANDLED INPUT PROCESSING ENABLED")
	
	# Check process mode
	if unit.process_mode != Node.PROCESS_MODE_DISABLED:
		issues.append("PROCESS MODE NOT DISABLED")
	
	# Report
	if issues.size() > 0:
		print("    ❌ %s: ISSUES FOUND - %s" % [label, ", ".join(issues)])
	else:
		print("    ✅ %s: CLEAN (no physics, no scripts, no processing)" % label)

func find_physics_nodes(node: Node) -> Array:
	"""Find all physics-related nodes in tree"""
	var found = []
	
	# Check current node
	if node is RigidBody3D or node is StaticBody3D or node is CharacterBody3D:
		found.append(node.get_class())
	elif node is CollisionShape3D or node is CollisionPolygon3D:
		found.append(node.get_class())
	elif node is Area3D:
		found.append("Area3D")
	elif node.get_class() == "AnimatableBody3D":
		found.append("AnimatableBody3D")
	
	# Check children
	for child in node.get_children():
		found.append_array(find_physics_nodes(child))
	
	return found
