extends Node3D

# Export variables for user configuration
@export var movement_speed: float = 0.8
@export var rotation_speed: float = 1.0
@export var mouse_sensitivity: float = 0.002
@export var barrel_max_elevation: float = 110.0  # degrees upward
@export var barrel_max_depression: float = 70.0  # degrees downward

# Shooting configuration
@export var projectile_speed: float = 15.0
@export var fire_rate: float = 0.2  # seconds between shots

# Node references
@onready var body_pivot: Node3D = $BodyPivot
@onready var turret_pivot: Node3D = $TurretPivot
@onready var barrell_pivot: Node3D = $TurretPivot/turret/BarrellPivot
@onready var barrel_tip: Marker3D = $TurretPivot/turret/BarrellPivot/BarrelTip

# Store initial positions from editor
var cylinder1_initial_pos: Vector3
var cylinder2_initial_pos: Vector3

var fire_cooldown: float = 0.0
var mode_manager: Node = null

func _ready() -> void:
	# DON'T capture mouse automatically - will be controlled by ModeManager
	# Mouse capture is handled when entering tactical mode
	
	# Get reference to ModeManager
	var map = get_tree().get_first_node_in_group("map")
	if map:
		mode_manager = map.get_node_or_null("ModeManager")
	
	# Detect standalone mode (playing from unit scene directly)
	if _is_standalone_mode():
		_hide_territory_labels()
		print("TankControllerT34: Running in standalone mode - territory labels hidden")
	
	# Store initial positions and reset only rotations of children
	if has_node("TurretPivot/BarrellPivot/Cylinder001"):
		var cyl1 = $TurretPivot/turret/BarrellPivot/Cylinder001
		cylinder1_initial_pos = cyl1.position  # Store editor position
		cyl1.rotation = Vector3.ZERO  # Reset rotation only
		cyl1.top_level = false  # Ensure it follows parent
		
	if has_node("TurretPivot/BarrellPivot/Cylinder002"):
		var cyl2 = $TurretPivot/turret/BarrellPivot/Cylinder002
		cylinder2_initial_pos = cyl2.position  # Store editor position
		cyl2.rotation = Vector3.ZERO  # Reset rotation only
		cyl2.top_level = false  # Ensure it follows parent

func _input(event: InputEvent) -> void:
	# Handle mouse motion for turret rotation
	if event is InputEventMouseMotion:
		# Rotate turret on Y-axis based on horizontal mouse movement
		turret_pivot.rotate_y(-event.relative.x * mouse_sensitivity)
		
		# Calculate new barrel rotation
		var new_rotation = barrell_pivot.rotation.y + (-event.relative.y * mouse_sensitivity)
		# Clamp in radians
		new_rotation = clamp(new_rotation, deg_to_rad(barrel_max_depression), deg_to_rad(barrel_max_elevation))
		# Set the rotation directly
		barrell_pivot.rotation.y = new_rotation
	
	# Handle shooting (right mouse button)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			fire_projectile()


func _process(delta: float) -> void:
	# Update fire cooldown
	if fire_cooldown > 0.0:
		fire_cooldown -= delta
	
	# Handle keyboard input for body movement and rotation
	var move_direction: float = 0.0
	var rotate_direction: float = 0.0
	
	# Forward/Backward movement (W/S keys)
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_S):
		move_direction = 1.0
	elif Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_W):
		move_direction = -1.0
	
	# Left/Right rotation (A/D keys)
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		rotate_direction = 1.0
	elif Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		rotate_direction = -1.0
	
	# Apply rotation to body
	if rotate_direction != 0.0:
		body_pivot.rotate_y(rotate_direction * rotation_speed * delta)
	
	# Apply movement in the direction the body is facing
	if move_direction != 0.0:
		var forward = -body_pivot.global_transform.basis.z
		global_position += forward * move_direction * movement_speed * delta

func fire_projectile() -> void:
	"""Fire a projectile from the barrel tip"""
	# Allow firing in standalone mode or tactical mode
	var can_fire = false
	if _is_standalone_mode():
		can_fire = true
	elif mode_manager != null and mode_manager.current_mode == mode_manager.GameMode.TACTICAL:
		can_fire = true
	
	if not can_fire:
		return
	
	# Check fire cooldown
	if fire_cooldown > 0.0:
		return
	
	# Check if barrel tip exists
	if barrel_tip == null:
		push_warning("TankControllerT34: BarrelTip marker not found!")
		return
	
	# Get spawn position and direction
	var spawn_pos = barrel_tip.global_position
	var direction = -barrel_tip.global_transform.basis.z
	
	# Spawn projectile through pool or fallback
	if has_node("/root/ProjectilePool"):
		ProjectilePool.spawn_projectile(spawn_pos, direction, projectile_speed)
	else:
		# Fallback for standalone mode (no ProjectilePool autoload)
		push_warning("TankControllerT34: ProjectilePool not found, using fallback instantiation")
		var projectile_scene = load("res://Scenes/Units/Projectile.tscn")
		if projectile_scene:
			var projectile = projectile_scene.instantiate()
			get_tree().root.add_child(projectile)
			projectile.initialize(spawn_pos, direction, projectile_speed)
	
	# Set cooldown
	fire_cooldown = fire_rate
	
	# Optional: Add muzzle flash effect here in the future

func _is_standalone_mode() -> bool:
	"""Check if running standalone (not in main game)"""
	# If GameManager doesn't exist, we're running the unit scene directly
	return get_node_or_null("/root/GameManager") == null

func _hide_territory_labels():
	"""Hide all territory labels when in standalone mode"""
	var map = get_node_or_null("/root/Map")
	if map:
		var color_manager = map.get_node_or_null("TerritoryColorManager")
		if color_manager and color_manager.has_method("set_labels_visible"):
			color_manager.set_labels_visible(false)

func _unhandled_input(event: InputEvent) -> void:
	# Handle Ctrl+U to exit tactical mode and return to map
	if event.is_action_pressed("toggle_unit_control"):
		if mode_manager != null and mode_manager.current_mode == mode_manager.GameMode.TACTICAL:
			# Get reference to Map to trigger exit
			var map = get_tree().get_first_node_in_group("map")
			if map and map.has_method("exit_tactical_mode"):
				map.exit_tactical_mode()
				get_viewport().set_input_as_handled()
				return
	
	# Allow player to release mouse with ESC key
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
