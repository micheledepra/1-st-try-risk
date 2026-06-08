extends Node3D

# Movement parameters
@export var movement_speed: float = 3.0
@export var rotation_speed: float = 1.1
@export var mouse_sensitivity: float = 0.002

# Barrel constraints (85 degrees max elevation for AA)
@export var barrel_max_elevation: float = 85.0
@export var barrel_max_depression: float = -10.0

# Shooting parameters
@export var projectile_speed: float = 695.0  # 20% faster than original 15.0
@export var fire_rate: float = 0.03  # Faster fire rate for AA
@export var bullet_scale: float = 0.9375  # 25% larger than original 0.75

# AA Blast timer (makes bullet explode mid-air after this duration)
@export var aa_blast_timer: float = 9.0  # Time in seconds before mid-air explosion
@export var aa_explosion_radius: float = 5.0  # Area damage radius for AA explosions
@export var aa_muzzle_blast_scale: float = 5.5  # Scale of muzzle flash effect (larger for AA)

# Standalone testing options
@export var standalone_mode: bool = true  # Set to false when used in Map.tscn
@export var show_debug_shots: bool = true  # Show visual debug for shots

# Node references
@onready var body_pivot: Node3D = $BodyPivot
@onready var turret_pivot: Node3D = $TurretPivot
@onready var barrel1: Node3D = $TurretPivot/Turret/bone29/Barrel1
@onready var barrel2: Node3D = $TurretPivot/Turret/bone49/Barrel2
@onready var muzzle1: Node3D = $TurretPivot/Turret/bone29/Barrel1/Muzzle1
@onready var muzzle2: Node3D = $TurretPivot/Turret/bone49/Barrel2/Muzzle2
@onready var fpv_camera: Camera3D = get_node_or_null("TurretPivot/Turret/bone49/Barrel2/Camera3D")  # barrel-mounted first-person camera

# State variables
var fire_cooldown: float = 0.0
var current_barrel: int = 0  # 0 = barrel1, 1 = barrel2 (alternating)
var is_standalone: bool = false

# Centralized view system (key 1 first-person, key 2 follow, RMB aim-zoom). See UnitViewController.gd
const UnitViewControllerScript = preload("res://Scripts/UnitViewController.gd")
var _view: UnitViewControllerScript = null

func _ready() -> void:
	# Check if running standalone (no GameManager) or forced standalone mode
	is_standalone = standalone_mode or get_node_or_null("/root/GameManager") == null
	
	# Verify critical nodes exist
	if not turret_pivot or not barrel1 or not barrel2 or not muzzle1 or not muzzle2:
		push_error("AAController: Missing required child nodes")
		set_process(false)
		set_process_input(false)
		return
	
	_setup_view_controller()

	# Setup standalone testing environment - only if standalone_mode was explicitly set BEFORE _ready
	# In UnitTestManager, mouse capture is handled externally after unit selection
	if standalone_mode:
		_setup_standalone_environment()

func _setup_view_controller() -> void:
	"""Attach the shared unit-view system (first-person / follow / aim-zoom)."""
	if fpv_camera == null:
		push_warning("AAController: first-person camera not found; view system disabled")
		return
	_view = UnitViewControllerScript.new()
	_view.name = "UnitViewController"
	add_child(_view)
	_view.configure(self, fpv_camera, {
		"follow_target": self,
		"forward_node": body_pivot,
		"fp_fov": 75.0,
		"follow_distance": 14.0,
		"follow_height": 7.0,
	})

func _setup_standalone_environment() -> void:
	# Capture mouse for FPS-style control - called externally or when standalone_mode is pre-set
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	print("AAController: Standalone mode active")
	print("  - W/S: Move forward/backward")
	print("  - A/D: Rotate body left/right")
	print("  - Mouse: Aim turret/barrels")
	print("  - Left Click (hold): Rapid fire")
	print("  - ESC: Release mouse")

func _input(event: InputEvent) -> void:
	# Only process in tactical mode or standalone
	if not is_standalone:
		var mode_manager = get_node_or_null("/root/ModeManager")
		if not mode_manager or mode_manager.current_mode != mode_manager.GameMode.TACTICAL:
			return
	
	# ESC to release mouse in standalone mode
	if is_standalone and event is InputEventKey:
		if event.pressed and event.keycode == KEY_ESCAPE:
			if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			else:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			return
	
	# Handle mouse motion for turret/barrel aiming
	if event is InputEventMouseMotion:
		# While free-looking in follow view, the mouse orbits the camera instead of the turret.
		if _view != null and _view.consumes_mouse_motion():
			return
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED or not is_standalone:
			# Horizontal rotation - rotate turret pivot
			turret_pivot.rotate_y(-event.relative.x * mouse_sensitivity)
			
			# Vertical rotation - rotate both barrels
			var vertical_delta = -event.relative.y * mouse_sensitivity
			_rotate_barrels(vertical_delta)

func _process(delta: float) -> void:
	# Only process in tactical mode or standalone
	if not is_standalone:
		var mode_manager = get_node_or_null("/root/ModeManager")
		if not mode_manager or mode_manager.current_mode != mode_manager.GameMode.TACTICAL:
			return
	
	# Update fire cooldown
	if fire_cooldown > 0:
		fire_cooldown -= delta

	# Handle tank-style movement (W/S forward/back, A/D rotate)
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
	
	# Apply rotation to body pivot
	if rotate_direction != 0.0:
		body_pivot.rotate_y(rotate_direction * rotation_speed * delta)
	
	# Move the unit forward/backward based on body pivot direction
	if move_direction != 0.0:
		# normalize: on the map the unit is scaled, so an un-normalized basis vector would over-speed
		var forward = -body_pivot.global_transform.basis.z.normalized()
		global_position += forward * move_direction * movement_speed * delta

	# Fire AFTER movement so the muzzle transform is current this frame (no spawn offset while driving)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if fire_cooldown <= 0:
			fire_projectile()
			fire_cooldown = fire_rate

func _rotate_barrels(vertical_delta: float) -> void:
	# Apply rotation to both barrels and clamp
	var new_rotation = barrel1.rotation.x + vertical_delta
	new_rotation = clamp(new_rotation, deg_to_rad(-barrel_max_elevation), deg_to_rad(-barrel_max_depression))

	barrel1.rotation.x = new_rotation
	barrel2.rotation.x = new_rotation
	# The first-person camera is parented under Barrel2, so it elevates with the barrel
	# automatically — no manual camera sync needed (and that old sync broke outside standalone).

func fire_projectile() -> void:
	# Get current muzzle based on alternating barrel
	var current_muzzle: Node3D
	if current_barrel == 0:
		current_muzzle = muzzle1
	else:
		current_muzzle = muzzle2
	
	# Toggle to next barrel for alternating fire
	current_barrel = 1 - current_barrel
	
	var spawn_pos = current_muzzle.global_position
	var direction = -current_muzzle.global_transform.basis.z.normalized()
	
	# Spawn muzzle blast effect (simple BlastEffect for muzzle flash)
	var blast_pool = get_node_or_null("/root/BlastEffectPool")
	if blast_pool:
		blast_pool.spawn_effect(spawn_pos, direction, aa_muzzle_blast_scale)
	elif is_standalone and show_debug_shots:
		_spawn_debug_blast(spawn_pos)
	
	# Spawn AA projectile using dedicated AAProjectilePool
	var aa_projectile_pool = get_node_or_null("/root/AAProjectilePool")
	if aa_projectile_pool:
		aa_projectile_pool.spawn_projectile(spawn_pos, direction, projectile_speed, aa_blast_timer, aa_explosion_radius)
	elif is_standalone and show_debug_shots:
		_spawn_debug_projectile(spawn_pos, direction)

func _spawn_debug_blast(pos: Vector3) -> void:
	# Create a simple flash effect for standalone testing
	var flash = OmniLight3D.new()
	flash.light_color = Color(1, 0.8, 0.2)
	flash.light_energy = 3.0
	flash.omni_range = 2.0
	get_tree().root.add_child(flash)
	flash.global_position = pos
	
	# Auto-remove after short time
	var tween = create_tween()
	tween.tween_property(flash, "light_energy", 0.0, 0.1)
	tween.tween_callback(flash.queue_free)

func _spawn_debug_projectile(pos: Vector3, dir: Vector3) -> void:
	# Create a simple sphere projectile for standalone testing
	var projectile = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.05 * bullet_scale
	sphere.height = 0.1 * bullet_scale
	projectile.mesh = sphere
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.5, 0)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.5, 0)
	mat.emission_energy_multiplier = 2.0
	projectile.material_override = mat
	
	get_tree().root.add_child(projectile)
	projectile.global_position = pos
	
	# Animate projectile movement and remove
	var tween = create_tween()
	var end_pos = pos + dir * 50.0
	tween.tween_property(projectile, "global_position", end_pos, 50.0 / projectile_speed)
	tween.tween_callback(projectile.queue_free)

func _exit_tree() -> void:
	# Restore mouse when leaving
	if is_standalone:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
