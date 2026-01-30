extends Node3D

# Export variables for user configuration
@export var movement_speed: float = 3
@export var rotation_speed: float = 1.1
@export var mouse_sensitivity: float = 0.002
@export var barrel_max_elevation: float = 20.0  # degrees upward
@export var barrel_max_depression: float = -10.0  # degrees downward

# Shooting configuration
@export var projectile_speed: float = 150.0
@export var fire_rate: float = 0.2  # seconds between shots

# Effect scaling (automatically detected from unit scale)
var effect_scale_multiplier: float = 1.0

# Node references
@onready var body_pivot: Node3D = $BodyPivot
@onready var turret_pivot: Node3D = $TurretPivot
@onready var barrell_pivot: Node3D = $TurretPivot/BarrellPivot
@onready var barrel_tip: Marker3D = $TurretPivot/BarrellPivot/BarrelTip

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
		effect_scale_multiplier = 1.0
		print("TankController: Running in standalone mode - territory labels hidden")
	else:
		await get_tree().process_frame
		effect_scale_multiplier = global_transform.basis.get_scale().x
		print("TankController: Effect scale multiplier set to %.2f" % effect_scale_multiplier)

func _input(event: InputEvent) -> void:
	# Handle mouse motion for turret rotation
	if event is InputEventMouseMotion:
		# Rotate turret on Y-axis based on horizontal mouse movement
		turret_pivot.rotate_y(-event.relative.x * mouse_sensitivity)
		
		# Calculate new barrel rotation
		var new_rotation = barrell_pivot.rotation.x + (-event.relative.y * mouse_sensitivity)
		# Clamp in radians
		new_rotation = clamp(new_rotation, deg_to_rad(barrel_max_depression), deg_to_rad(barrel_max_elevation))
		# Set the rotation directly
		barrell_pivot.rotation.x = new_rotation
	
	# Handle shooting (left mouse button)
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
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		move_direction = 1.0
	elif Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
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
		push_warning("TankController: BarrelTip marker not found!")
		return
	
	# Get spawn position and direction
	var spawn_pos = barrel_tip.global_position
	var direction = -barrel_tip.global_transform.basis.z
	
	# Spawn muzzle blast effect with scale (autoload - call directly)
	BlastEffectPool.spawn_effect(spawn_pos, direction, effect_scale_multiplier)
	
	# Spawn projectile through pool or fallback
	if has_node("/root/ProjectilePool"):
		ProjectilePool.spawn_projectile(spawn_pos, direction, projectile_speed)
	else:
		# Fallback for standalone mode (no ProjectilePool autoload)
		push_warning("TankController: ProjectilePool not found, using fallback instantiation")
		var projectile_scene = load("res://Scenes/Units/Projectile.tscn")
		if projectile_scene:
			var projectile = projectile_scene.instantiate()
			get_tree().root.add_child(projectile)
			projectile.initialize(spawn_pos, direction, projectile_speed)
	
	# Set cooldown
	fire_cooldown = fire_rate
	
	# Optional: Add muzzle flash effect here in the future

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
