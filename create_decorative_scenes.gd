extends SceneTree
# One-time generator script to create decorative unit scene variants
# Run via: godot --headless --script create_decorative_scenes.gd

func _init():
	print("\n=== Decorative Scene Generator ===\n")
	
	var success = true
	success = create_panther_decorative() and success
	success = create_t34_decorative() and success
	
	if success:
		print("\n✓ SUCCESS: All decorative scenes created!")
		print("  - PantherDecorative.tscn")
		print("  - t34Decorative.tscn")
		print("\nNext steps:")
		print("  1. Open Godot editor")
		print("  2. Verify scenes exist in FileSystem")
		print("  3. Run game and check for zero deprecation warnings")
	else:
		print("\n✗ FAILED: See errors above")
		quit(1)
	
	quit(0)

func create_panther_decorative() -> bool:
	print("Creating PantherDecorative.tscn...")
	
	var source_path = "res://Scenes/Units/Import/Panther/Panther.tscn"
	var target_path = "res://Scenes/Units/Import/Panther/PantherDecorative.tscn"
	
	# Load source scene
	var packed_scene = load(source_path) as PackedScene
	if not packed_scene:
		print("  ✗ ERROR: Failed to load " + source_path)
		return false
	
	var root = packed_scene.instantiate()
	if not root:
		print("  ✗ ERROR: Failed to instantiate scene")
		return false
	
	print("  Loaded source scene: " + root.name)
	
	# Remove root script (TankController.gd)
	root.set_script(null)
	print("  ✓ Removed root script")
	
	# Remove Camera3D
	var camera_removed = false
	var turret_pivot = root.find_child("TurretPivot", true, false)
	if turret_pivot:
		var turret = turret_pivot.find_child("turret", false, false)
		if turret:
			var camera = turret.find_child("Camera3D", false, false)
			if camera:
				camera.queue_free()
				camera_removed = true
	
	if camera_removed:
		print("  ✓ Removed Camera3D")
	else:
		print("  ⚠ Warning: Camera3D not found (may be OK)")
	
	# Remove RigidBody3D nodes
	var rigidbodies_removed = 0
	for child in root.get_children():
		if child is RigidBody3D:
			child.queue_free()
			rigidbodies_removed += 1
	
	print("  ✓ Removed " + str(rigidbodies_removed) + " RigidBody3D nodes")
	
	# Add Area3D hitbox
	var hitbox = Area3D.new()
	hitbox.name = "Hitbox"
	hitbox.collision_layer = 2  # Units layer
	hitbox.collision_mask = 4   # Projectiles layer
	hitbox.monitoring = true
	hitbox.monitorable = true
	root.add_child(hitbox)
	hitbox.owner = root
	
	# Add CollisionShape3D with BoxShape3D
	var collision_shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(2.5, 2.1, 5.5)  # Panther dimensions
	collision_shape.shape = box_shape
	hitbox.add_child(collision_shape)
	collision_shape.owner = root
	
	# Attach DecorativeUnitHitbox script
	var hitbox_script = load("res://Scripts/DecorativeUnitHitbox.gd")
	if hitbox_script:
		hitbox.set_script(hitbox_script)
		print("  ✓ Added Area3D hitbox with script")
	else:
		print("  ✗ ERROR: DecorativeUnitHitbox.gd not found")
		return false
	
	# Disable processing and physics interpolation
	root.process_mode = Node.PROCESS_MODE_DISABLED
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	print("  ✓ Disabled processing and physics interpolation")
	
	# Save scene
	var new_scene = PackedScene.new()
	var result = new_scene.pack(root)
	if result != OK:
		print("  ✗ ERROR: Failed to pack scene (code: " + str(result) + ")")
		root.queue_free()
		return false
	
	result = ResourceSaver.save(new_scene, target_path)
	if result != OK:
		print("  ✗ ERROR: Failed to save scene (code: " + str(result) + ")")
		root.queue_free()
		return false
	
	root.queue_free()
	print("  ✓ Saved to " + target_path + "\n")
	return true

func create_t34_decorative() -> bool:
	print("Creating t34Decorative.tscn...")
	
	var source_path = "res://Scenes/Units/Import/t34/t_34.tscn"
	var target_path = "res://Scenes/Units/Import/t34/t34Decorative.tscn"
	
	# Load source scene
	var packed_scene = load(source_path) as PackedScene
	if not packed_scene:
		print("  ✗ ERROR: Failed to load " + source_path)
		return false
	
	var root = packed_scene.instantiate()
	if not root:
		print("  ✗ ERROR: Failed to instantiate scene")
		return false
	
	print("  Loaded source scene: " + root.name)
	
	# Remove root script (TankControllerT34.gd)
	root.set_script(null)
	print("  ✓ Removed root script")
	
	# Remove Camera3D
	var camera_removed = false
	var turret_pivot = root.find_child("TurretPivot", true, false)
	if turret_pivot:
		var turret = turret_pivot.find_child("turret", false, false)
		if turret:
			var camera = turret.find_child("Camera3D", false, false)
			if camera:
				camera.queue_free()
				camera_removed = true
	
	if camera_removed:
		print("  ✓ Removed Camera3D")
	else:
		print("  ⚠ Warning: Camera3D not found (may be OK)")
	
	# Remove RigidBody3D nodes
	var rigidbodies_removed = 0
	for child in root.get_children():
		if child is RigidBody3D:
			child.queue_free()
			rigidbodies_removed += 1
	
	print("  ✓ Removed " + str(rigidbodies_removed) + " RigidBody3D nodes")
	
	# Add Area3D hitbox
	var hitbox = Area3D.new()
	hitbox.name = "Hitbox"
	hitbox.collision_layer = 2  # Units layer
	hitbox.collision_mask = 4   # Projectiles layer
	hitbox.monitoring = true
	hitbox.monitorable = true
	root.add_child(hitbox)
	hitbox.owner = root
	
	# Add CollisionShape3D with BoxShape3D
	var collision_shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(0.4, 0.35, 0.5)  # T34 dimensions (scaled up 13.3x at runtime)
	collision_shape.shape = box_shape
	hitbox.add_child(collision_shape)
	collision_shape.owner = root
	
	# Attach DecorativeUnitHitbox script
	var hitbox_script = load("res://Scripts/DecorativeUnitHitbox.gd")
	if hitbox_script:
		hitbox.set_script(hitbox_script)
		print("  ✓ Added Area3D hitbox with script")
	else:
		print("  ✗ ERROR: DecorativeUnitHitbox.gd not found")
		return false
	
	# Disable processing and physics interpolation
	root.process_mode = Node.PROCESS_MODE_DISABLED
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	print("  ✓ Disabled processing and physics interpolation")
	
	# Save scene
	var new_scene = PackedScene.new()
	var result = new_scene.pack(root)
	if result != OK:
		print("  ✗ ERROR: Failed to pack scene (code: " + str(result) + ")")
		root.queue_free()
		return false
	
	result = ResourceSaver.save(new_scene, target_path)
	if result != OK:
		print("  ✗ ERROR: Failed to save scene (code: " + str(result) + ")")
		root.queue_free()
		return false
	
	root.queue_free()
	print("  ✓ Saved to " + target_path + "\n")
	return true
