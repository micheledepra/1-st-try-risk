extends Node3D

# Export variables for user configuration
# Scale: ~4.3 game units per metre. Speeds below are real m/s * 4.3.
# T-34: lighter (~32 t) so quicker than the Panther, electric turret ~30 deg/s.
@export var max_speed_forward: float = 32.0   # ~7.4 m/s (~27 km/h cross-country)
@export var max_speed_reverse: float = 12.0   # reverse gear is much slower
@export var acceleration: float = 10.0        # u/s^2 - better power-to-weight than the Panther
@export var braking: float = 18.0             # u/s^2 - coast/brake to a stop (stop time scales with speed)
@export var rotation_speed: float = 0.8       # hull yaw rate (A/D), rad/s
@export var mouse_sensitivity: float = 0.002
@export var turret_traverse_speed: float = 0.52  # rad/s (~30 deg/s, T-34 electric traverse)
@export var barrel_max_elevation: float = 110.0  # degrees upward
@export var barrel_max_depression: float = 70.0  # degrees downward

# Shooting configuration
@export var projectile_speed: float = 2800.0  # T-34 76mm F-34: ~655 m/s * 4.3 u/m
@export var fire_rate: float = 0.2  # seconds between shots
@export var muzzle_blast_scale: float = 1.25  # Cannon blast size as a factor of the unit's world scale (big)
@export var bullet_scale: float = 5.0  # Cannon round size (large)

# Effect scaling (automatically detected from unit scale)
var effect_scale_multiplier: float = 1.0

# Node references
@onready var body_pivot: Node3D = $BodyPivot
@onready var turret_pivot: Node3D = $TurretPivot
@onready var barrell_pivot: Node3D = $TurretPivot/turret/BarrellPivot
@onready var barrel_tip: Marker3D = $TurretPivot/turret/BarrellPivot/BarrelTip
@onready var fpv_camera: Camera3D = get_node_or_null("TurretPivot/turret/BarrellPivot/Camera3D")  # first-person / over-gun camera

# Centralized view system (key 1 first-person, key 2 follow, RMB aim-zoom). See UnitViewController.gd
const UnitViewControllerScript = preload("res://Scripts/UnitViewController.gd")
var _view: UnitViewControllerScript = null

# Store initial positions from editor
var cylinder1_initial_pos: Vector3
var cylinder2_initial_pos: Vector3

var fire_cooldown: float = 0.0
var mode_manager: Node = null
var fire_requested: bool = false  # Set in _input, executed at end of _process (after movement) so the muzzle transform is current
var platform_velocity: Vector3 = Vector3.ZERO  # Tank's current velocity, inherited by fired rounds (moving-shooter physics)
var barrel_smoke: GPUParticles3D = null  # Lingering world-space smoke trail emitted from the moving barrel
var current_speed: float = 0.0  # Signed longitudinal speed (+forward / -reverse), ramped via accel/brake
var turret_yaw_target: float = 0.0  # Desired turret yaw; turret traverses toward it at turret_traverse_speed
const MAX_TURRET_LEAD: float = 0.4  # How far (rad) the aim target may lead the turret, so it behaves like rate control

func _ready() -> void:
	# DON'T capture mouse automatically - will be controlled by ModeManager
	# Mouse capture is handled when entering tactical mode
	
	# Get reference to ModeManager
	var map = get_tree().get_first_node_in_group("map")
	if map:
		mode_manager = map.get_node_or_null("ModeManager")

	_setup_view_controller()

	# Detect standalone mode (playing from unit scene directly)
	if _is_standalone_mode():
		_hide_territory_labels()
		effect_scale_multiplier = 1.0
		print("TankControllerT34: Running in standalone mode - territory labels hidden")
	else:
		await get_tree().process_frame
		effect_scale_multiplier = global_transform.basis.get_scale().x
		print("TankControllerT34: Effect scale multiplier set to %.2f" % effect_scale_multiplier)
	
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

	# Create the lingering barrel smoke trail (parented to the moving barrel tip)
	_create_barrel_smoke_trail()

func _input(event: InputEvent) -> void:
	# Handle mouse motion for turret rotation
	if event is InputEventMouseMotion:
		# While free-looking in follow view, the mouse orbits the camera instead of the turret.
		if _view != null and _view.consumes_mouse_motion():
			return
		# Horizontal mouse commands a turret-traverse target; the turret slews toward it
		# at a realistic max rate in _process (no instant snap).
		turret_yaw_target += -event.relative.x * mouse_sensitivity

		# Calculate new barrel rotation
		var new_rotation = barrell_pivot.rotation.y + (-event.relative.y * mouse_sensitivity)
		# Clamp in radians
		new_rotation = clamp(new_rotation, deg_to_rad(barrel_max_depression), deg_to_rad(barrel_max_elevation))
		# Set the rotation directly
		barrell_pivot.rotation.y = new_rotation
	
	# Handle shooting (left mouse button) - defer the actual shot to end of _process
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			fire_requested = true


func _process(delta: float) -> void:
	# Capture position before movement so we can derive the platform velocity this frame
	var prev_position: Vector3 = global_position

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
	
	# Turret traverse: slew toward the aim target at a realistic max rate (not instant).
	turret_yaw_target = clamp(turret_yaw_target, turret_pivot.rotation.y - MAX_TURRET_LEAD, turret_pivot.rotation.y + MAX_TURRET_LEAD)
	var max_yaw_step = turret_traverse_speed * delta
	turret_pivot.rotation.y += clamp(turret_yaw_target - turret_pivot.rotation.y, -max_yaw_step, max_yaw_step)

	# Apply rotation to body (hull yaw)
	if rotate_direction != 0.0:
		body_pivot.rotate_y(rotate_direction * rotation_speed * delta)

	# Longitudinal speed with acceleration / braking - no instant start or halt.
	var target_speed: float = 0.0
	if move_direction > 0.0:
		target_speed = max_speed_forward
	elif move_direction < 0.0:
		target_speed = -max_speed_reverse
	var accelerating: bool = target_speed != 0.0 and abs(target_speed) > abs(current_speed) and current_speed * target_speed >= 0.0
	var rate: float = acceleration if accelerating else braking
	current_speed = move_toward(current_speed, target_speed, rate * delta)
	if absf(current_speed) > 0.0001:
		# normalize: on the map the unit is scaled (~4x), so the un-normalized basis
		# vector would move the tank ~4x too fast
		var forward = -body_pivot.global_transform.basis.z.normalized()
		global_position += forward * current_speed * delta

	# Derive the platform (tank) velocity from this frame's actual displacement
	if delta > 0.0:
		platform_velocity = (global_position - prev_position) / delta
	else:
		platform_velocity = Vector3.ZERO

	# Fire AFTER movement/rotation so the barrel transform is current this frame.
	# Reading the muzzle position before movement spawned the round at the previous
	# frame's barrel position, making it appear offset when driving.
	if fire_requested:
		fire_requested = false
		fire_projectile()

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
	
	# Spawn muzzle blast effect, sized to the unit and the cannon factor
	BlastEffectPool.spawn_effect(spawn_pos, direction, effect_scale_multiplier * muzzle_blast_scale)

	# Kick off the lingering barrel smoke trail
	_activate_barrel_smoke()
	
	# Spawn projectile through pool or fallback
	if has_node("/root/ProjectilePool"):
		ProjectilePool.spawn_projectile(spawn_pos, direction, projectile_speed, effect_scale_multiplier, platform_velocity, bullet_scale)
	else:
		# Fallback for standalone mode (no ProjectilePool autoload)
		push_warning("TankControllerT34: ProjectilePool not found, using fallback instantiation")
		var projectile_scene = load("res://Scenes/Units/Projectile.tscn")
		if projectile_scene:
			var projectile = projectile_scene.instantiate()
			get_tree().root.add_child(projectile)
			projectile.effect_scale = effect_scale_multiplier
			projectile.initialize(spawn_pos, direction, projectile_speed, platform_velocity, bullet_scale)

	# Set cooldown
	fire_cooldown = fire_rate

func _create_barrel_smoke_trail() -> void:
	"""Instance a world-space smoke emitter parented to the barrel tip.
	local_coords=false means emitted puffs stay in world space, so when the tank
	drives the barrel leaves a trail of smoke behind it."""
	if barrel_tip == null:
		return
	var smoke_scene = load("res://Scenes/Effects/BarrelSmoke.tscn")
	if smoke_scene == null:
		push_warning("TankControllerT34: BarrelSmoke.tscn not found")
		return
	barrel_smoke = smoke_scene.instantiate() as GPUParticles3D
	barrel_smoke.emitting = false
	barrel_tip.add_child(barrel_smoke)

func _activate_barrel_smoke() -> void:
	"""Emit the lingering barrel smoke for ~1 second after firing."""
	if not is_instance_valid(barrel_smoke):
		return
	barrel_smoke.emitting = true
	get_tree().create_timer(1.0).timeout.connect(func():
		if is_instance_valid(barrel_smoke):
			barrel_smoke.emitting = false)

func _setup_view_controller() -> void:
	"""Attach the shared unit-view system (first-person / follow / aim-zoom)."""
	if fpv_camera == null:
		push_warning("TankControllerT34: first-person camera not found; view system disabled")
		return
	_view = UnitViewControllerScript.new()
	_view.name = "UnitViewController"
	add_child(_view)
	_view.configure(self, fpv_camera, {
		"follow_target": self,
		"forward_node": body_pivot,
		"fp_fov": 75.0,
		"follow_distance": 12.0,
		"follow_height": 6.0,
	})

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
