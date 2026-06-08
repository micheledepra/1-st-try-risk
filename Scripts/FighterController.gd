extends Node3D
class_name FighterController

signal hud_state(throttle: float, pitch_deg: float, roll_deg: float, yaw_deg: float)

## WW1 Fighter Plane Controller
## Implements realistic flight physics with throttle, stall, lift, drag
## Features: alternating muzzle fire, ground landing/crash detection, R to respawn
## Uses fixed chase camera

# === Flight Parameters (Adjustable) ===
@export_group("Flight Physics")
@export var max_speed: float = 30.0  # Maximum speed at full throttle
@export var min_speed: float = 10.75  # Stall speed - below this, plane loses lift
@export var acceleration: float = 1  # Speed change rate
@export var pitch_speed: float = 2.5  # Nose up/down rate
@export var roll_speed: float = 2.25  # Banking rate
@export var yaw_speed: float = 0.6  # Rudder rate
@export var lift_coefficient: float = 0.5  # Lift force multiplier
@export var drag_coefficient: float = 0.01  # Air resistance
@export var gravity: float = 3.8  # Gravity strength

@export_group("Landing")
@export var safe_landing_speed: float = 1.5  # Max speed for safe landing
@export var landing_gear_height: float = 1.5  # Height offset when landed
@export var ground_raycast_length: float = 3.0  # Raycast distance for ground detection

@export_group("Combat")
@export var fire_rate: float = 0.1  # Seconds between shots
@export var projectile_speed: float = 200.0  # Air projectile speed
@export var mg_muzzle_blast_scale: float = 0.5  # Machine-gun blast size (small, vs the tank cannon)

@export_group("Mode")
@export var standalone_mode: bool = false  # Set true for test scene

@export_group("Mouse Flight Controls")
@export var instructor_pitch_response: float = 2.0  # How fast plane pitches toward target
@export var instructor_roll_response: float = 3.0   # How fast plane rolls toward target
@export var instructor_yaw_response: float = 0.5    # Slight coordinated yaw with roll
@export var mouse_aim_range: float = 400.0          # Max cursor distance from center (pixels)

# === Node References ===
@onready var gltf_root: Node3D = $GLTF_SceneRootNode
@onready var frame: Node3D = $GLTF_SceneRootNode/Frame
@onready var propeller: Node3D = $GLTF_SceneRootNode/Propeller
@onready var muzzle1: Node3D = $GLTF_SceneRootNode/Frame/Muzzle1
@onready var muzzle2: Node3D = $GLTF_SceneRootNode/Frame/Muzzle2
@onready var camera: Camera3D = $GLTF_SceneRootNode/Camera3D
@onready var third_view_camera: Camera3D = $ThirdViewCamera3D
@onready var ground_raycast: RayCast3D = $GroundRayCast

# === State Variables ===
var current_speed: float = 1.0  # Current forward speed
var throttle: float = 0.5  # 0.0 to 1.0
var velocity: Vector3 = Vector3.ZERO
var is_grounded: bool = false
var is_crashed: bool = false
var is_standalone: bool = false

# Combat state
var current_muzzle: int = 0  # Alternates between 0 (Muzzle1) and 1 (Muzzle2)
var fire_cooldown: float = 0.0

# Camera state
var is_third_person_view: bool = false
var camera_transition_tween: Tween
var orbit_yaw: float = 0.0
var orbit_pitch: float = 0.0
var orbit_distance: float = 12.0
var is_orbiting: bool = false  # True when middle mouse held
var third_view_default_local_transform: Transform3D  # Stores scene-defined camera position

# Mouse flight state (War Thunder style)
var mouse_screen_offset: Vector2 = Vector2.ZERO  # Cursor offset from screen center

# Spawn position for respawn
var spawn_position: Vector3
var spawn_rotation: Vector3

func _ready() -> void:
	# Detect standalone mode
	is_standalone = standalone_mode or get_node_or_null("/root/GameManager") == null
	
	# Store spawn position for respawn
	spawn_position = global_position
	spawn_rotation = rotation
	
	# Store default third-person camera transform (as defined in scene)
	if third_view_camera:
		third_view_default_local_transform = third_view_camera.transform
		# Calculate orbit distance from scene position
		orbit_distance = third_view_camera.position.length()
	
	# Configure ground raycast
	if ground_raycast:
		ground_raycast.target_position = Vector3(0, -ground_raycast_length, 0)
		ground_raycast.collision_mask = 1  # Layer 1: Terrain
		ground_raycast.enabled = true
	
	# Activate camera and set mouse mode appropriately
	if is_standalone and camera:
		camera.current = true
	
	# Set mouse mode for flight controls (both standalone and spawned from map)
	if _can_process_input():
		# War Thunder style: visible cursor confined to window
		Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)
		# Center the virtual cursor at screen center
		mouse_screen_offset = Vector2.ZERO
		# Warp mouse to screen center to establish baseline
		var viewport = get_viewport()
		if viewport:
			var screen_center = viewport.get_visible_rect().size / 2.0
			Input.warp_mouse(screen_center)
	
	print("FighterController: Initialized (standalone=%s)" % is_standalone)
	_emit_hud_state()

func _input(event: InputEvent) -> void:
	# Handle mouse capture toggle with Escape
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CONFINED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)
			mouse_screen_offset = Vector2.ZERO  # Reset virtual cursor to center
			# Warp mouse to physical screen center
			var viewport = get_viewport()
			if viewport:
				var screen_center = viewport.get_visible_rect().size / 2.0
				Input.warp_mouse(screen_center)
	
	# Camera view switching
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1 and is_third_person_view:
			# Switch to first-person (chase) camera
			_switch_to_chase_camera()
		elif event.keycode == KEY_3:
			if is_third_person_view:
				# Reset orbit to default position
				_reset_orbit_position()
			else:
				# Switch to third-person camera
				_switch_to_third_person_camera()
	
	# Middle mouse button for orbit control
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			is_orbiting = event.pressed
			if not event.pressed and is_third_person_view:
				# Released middle mouse - reset to default view
				_reset_orbit_position()
	
	# Mouse motion for orbit when middle button held
	if event is InputEventMouseMotion and is_orbiting and is_third_person_view:
		orbit_yaw -= event.relative.x * 0.005
		orbit_pitch -= event.relative.y * 0.005
		# Clamp pitch to prevent flipping (-80 to +20 degrees)
		orbit_pitch = clamp(orbit_pitch, deg_to_rad(-80), deg_to_rad(20))
	
	# Mouse motion for flight controls (when not orbiting camera)
	if event is InputEventMouseMotion and not is_orbiting:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CONFINED:
			# Accumulate mouse offset from center (War Thunder style)
			mouse_screen_offset.x += event.relative.x
			mouse_screen_offset.y += event.relative.y
			# Clamp to max range (circular)
			if mouse_screen_offset.length() > mouse_aim_range:
				mouse_screen_offset = mouse_screen_offset.normalized() * mouse_aim_range

func _process(delta: float) -> void:
	# Skip if not in control
	if not _can_process_input():
		return
	
	# Update third-person camera position
	if is_third_person_view and third_view_camera:
		if is_orbiting:
			# Orbiting - use calculated orbit position
			_update_orbit_camera()
		else:
			# Not orbiting - keep camera in default fixed position relative to plane
			_update_default_third_person_camera()
	
	# Handle respawn
	if Input.is_key_pressed(KEY_R):
		_respawn()
		return
	
	# Skip flight controls if crashed
	if is_crashed:
		return
	
	# Handle firing
	_handle_firing(delta)

func _physics_process(delta: float) -> void:
	# Skip if not in control or crashed
	if not _can_process_input() or is_crashed:
		return
	
	# Handle input
	_handle_flight_input(delta)
	
	# Apply physics
	_apply_flight_physics(delta)
	
	# Check ground collision
	_check_ground_collision()
	
	# Spin propeller based on speed
	_spin_propeller(delta)

	_emit_hud_state()

func _can_process_input() -> bool:
	"""Check if controller should process input"""
	if is_standalone:
		return true
	
	# Check ModeManager for fighter mode
	var mode_manager = get_node_or_null("/root/ModeManager")
	if mode_manager and mode_manager.current_mode == mode_manager.GameMode.FIGHTER:
		return true
	
	return false

func _handle_flight_input(delta: float) -> void:
	"""Process flight control inputs (War Thunder style instructor)"""
	if is_grounded:
		# Ground controls - limited
		_handle_ground_input(delta)
		return
	
	# Calculate speed-based control effectiveness
	# At low speeds, controls are more responsive (tighter turns)
	# At high speeds, controls are less responsive (wider turns)
	var speed_ratio = clamp(current_speed / max_speed, 0.0, 1.0)
	var control_effectiveness = lerp(1.5, 0.5, speed_ratio)  # 1.5x at low speed, 0.5x at high speed
	
	# === WAR THUNDER STYLE: Calculate target direction from cursor offset ===
	# Normalize cursor offset to -1 to 1 range
	var aim_x = mouse_screen_offset.x / mouse_aim_range  # -1 (left) to 1 (right)
	var aim_y = mouse_screen_offset.y / mouse_aim_range  # -1 (up) to 1 (down)
	
	# === PITCH: Cursor below center = pitch down, cursor above = pitch up ===
	# (Inverted: positive aim_y means cursor is below center, so pitch down)
	var pitch_input: float = 0.0
	
	# Instructor pitch: fly toward where cursor points
	pitch_input = -aim_y * instructor_pitch_response
	
	# Keyboard pitch override (W/S) - adds to instructor
	if Input.is_key_pressed(KEY_S):
		pitch_input -= 1.0
	if Input.is_key_pressed(KEY_W):
		pitch_input += 1.0
	
	# Apply pitch
	rotate_object_local(Vector3.RIGHT, pitch_input * pitch_speed * control_effectiveness * delta)
	
	# === ROLL: Cursor to right = roll right to turn, cursor to left = roll left ===
	var roll_input: float = 0.0
	
	# Instructor roll: bank toward where cursor points
	roll_input = -aim_x * instructor_roll_response
	
	# Keyboard roll override (A/D) - adds to instructor
	if Input.is_key_pressed(KEY_A):
		roll_input += 1.0
	if Input.is_key_pressed(KEY_D):
		roll_input -= 1.0
	
	# Apply roll
	rotate_object_local(Vector3.FORWARD, roll_input * roll_speed * control_effectiveness * delta)
	
	# === YAW: Slight coordinated yaw with cursor (helps turns feel natural) ===
	var yaw_input: float = 0.0
	
	# Instructor yaw: slight coordination with roll direction
	yaw_input = -aim_x * instructor_yaw_response
	
	# Keyboard yaw override (Q/E) - adds to instructor
	if Input.is_key_pressed(KEY_Q):
		yaw_input += 1.0
	if Input.is_key_pressed(KEY_E):
		yaw_input -= 1.0
	
	# Apply yaw
	rotate_object_local(Vector3.UP, yaw_input * yaw_speed * control_effectiveness * delta)
	
	# === Throttle (Shift/Ctrl) ===
	if Input.is_key_pressed(KEY_SHIFT):
		throttle = min(throttle + delta * 0.5, 1.0)
	if Input.is_key_pressed(KEY_CTRL):
		throttle = max(throttle - delta * 0.5, 0.0)

func _handle_ground_input(delta: float) -> void:
	"""Handle controls while on ground"""
	# Throttle still works
	if Input.is_key_pressed(KEY_SHIFT):
		throttle = min(throttle + delta * 0.5, 1.0)
	if Input.is_key_pressed(KEY_CTRL):
		throttle = max(throttle - delta * 0.5, 0.0)
	
	# Yaw for ground steering
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_A):
		rotate_y(yaw_speed * delta)
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_D):
		rotate_y(-yaw_speed * delta)
	
	# Takeoff: increase speed on ground, lift off when fast enough
	var target_speed = lerp(0.0, max_speed * 0.8, throttle)
	current_speed = move_toward(current_speed, target_speed, acceleration * delta)
	
	# Move forward on ground
	var forward = global_transform.basis.z
	global_position += forward * current_speed * delta
	
	# Check for takeoff (speed exceeds stall speed with some margin)
	if current_speed > min_speed * 1.2:
		is_grounded = false
		print("FighterController: Takeoff!")

func _apply_flight_physics(delta: float) -> void:
	"""Apply flight physics simulation"""
	if is_grounded:
		return
	
	# Get orientation vectors
	var forward = global_transform.basis.z
	var up = global_transform.basis.y
	
	# === Climb/Dive Speed Effect ===
	# Calculate pitch angle: positive = climbing, negative = diving
	# forward.y gives us the sine of the pitch angle (-1 to 1)
	var climb_factor = forward.y  # -1 (straight down) to +1 (straight up)
	
	# Gravitational speed change: climbing loses speed, diving gains speed
	# Using real gravity (9.81 m/s²) projected onto flight path
	var gravity_speed_effect = -climb_factor * 3.81 * delta
	
	# Calculate target speed from throttle (engine power)
	var target_speed = lerp(min_speed * 0.5, max_speed, throttle)
	
	# Apply engine acceleration toward target speed
	var engine_accel = acceleration * delta
	if current_speed < target_speed:
		current_speed = min(current_speed + engine_accel, target_speed)
	elif current_speed > target_speed:
		current_speed = max(current_speed - engine_accel * 0.5, target_speed)  # Slower decel
	
	# Apply gravitational speed change (climb loses speed, dive gains speed)
	current_speed += gravity_speed_effect
	
	# Clamp speed to reasonable bounds
	current_speed = max(current_speed, 0.0)  # Can't go negative
	current_speed = min(current_speed, max_speed * 1.5)  # Allow some overspeed in dives
	
	# === Lift Force ===
	# Lift depends on speed and how level the wings are
	var lift_effectiveness = max(0.0, up.dot(Vector3.UP))
	var lift_force = up * lift_coefficient * current_speed * lift_effectiveness
	
	# === Stall Effect ===
	# Below min_speed, plane loses lift and nose drops
	if current_speed < min_speed:
		var stall_factor = (min_speed - current_speed) / min_speed
		# Progressive nose drop - faster drop at lower speeds
		var stall_rotation = stall_factor * 2.0 * delta
		rotate_object_local(Vector3.RIGHT, stall_rotation)
		# Reduce lift during stall
		lift_force *= (1.0 - stall_factor * 0.8)
	
	# === Gravity ===
	var gravity_force = Vector3.DOWN * gravity
	
	# === Drag ===
	var speed_squared = velocity.length_squared()
	var drag_force = Vector3.ZERO
	if speed_squared > 0.01:
		drag_force = -velocity.normalized() * drag_coefficient * speed_squared
	
	# === Combine Forces ===
	# Base velocity is forward movement
	velocity = forward * current_speed
	
	# Add vertical forces
	velocity += (gravity_force + lift_force + drag_force) * delta
	
	# Apply movement
	global_position += velocity * delta

func _check_ground_collision() -> void:
	"""Check for ground collision using raycast"""
	if not ground_raycast or is_grounded:
		return
	
	ground_raycast.force_raycast_update()
	
	if ground_raycast.is_colliding():
		var collision_point = ground_raycast.get_collision_point()
		var distance_to_ground = global_position.y - collision_point.y
		
		# Check if close enough to ground
		if distance_to_ground <= landing_gear_height:
			# Check landing speed
			if current_speed <= safe_landing_speed:
				# Safe landing
				_land_safely(collision_point)
			else:
				# Crash!
				_crash(collision_point)

func _land_safely(ground_point: Vector3) -> void:
	"""Handle safe landing"""
	is_grounded = true
	global_position.y = ground_point.y + landing_gear_height
	
	# Level out the plane
	var current_y_rotation = rotation.y
	rotation = Vector3.ZERO
	rotation.y = current_y_rotation
	
	# Reduce speed on ground
	current_speed = min(current_speed, safe_landing_speed)
	velocity = Vector3.ZERO
	
	print("FighterController: Landed safely at speed %.1f" % current_speed)

func _crash(ground_point: Vector3) -> void:
	"""Handle crash landing"""
	is_crashed = true
	is_grounded = true
	global_position.y = ground_point.y + 0.5  # Slight offset
	
	# Stop all movement
	current_speed = 0.0
	velocity = Vector3.ZERO
	throttle = 0.0
	
	# Tilt plane to show crash
	rotation.x = deg_to_rad(15)
	rotation.z = deg_to_rad(randf_range(-20, 20))
	
	# Spawn crash effect
	var pool = get_node_or_null("/root/AirImpactEffectPool")
	if pool:
		pool.spawn_effect(ground_point, Color.ORANGE, true)
	
	print("FighterController: CRASHED at speed %.1f (safe landing requires <= %.1f)" % [current_speed, safe_landing_speed])

func _respawn() -> void:
	"""Respawn the aircraft at starting position"""
	# Reset position and rotation
	global_position = spawn_position
	rotation = spawn_rotation
	
	# Reset state
	is_crashed = false
	is_grounded = false
	current_speed = 15.0
	throttle = 0.5
	velocity = Vector3.ZERO
	
	print("FighterController: Respawned!")

func _spin_propeller(delta: float) -> void:
	"""Spin propeller based on current speed"""
	if propeller:
		# Propeller speed scales with current speed (and a bit with throttle when grounded)
		var spin_speed = current_speed * 2.0
		if is_grounded:
			spin_speed = max(spin_speed, throttle * max_speed * 1.5)
		propeller.rotate_z(spin_speed * delta)

func _handle_firing(delta: float) -> void:
	"""Handle weapon firing with alternating muzzles"""
	# Decrease cooldown
	fire_cooldown = max(0.0, fire_cooldown - delta)
	
	# Fire on left mouse button
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and fire_cooldown <= 0.0:
		_fire_projectile()
		fire_cooldown = fire_rate

func _fire_projectile() -> void:
	"""Fire a projectile from the current muzzle"""
	var pool = get_node_or_null("/root/AirProjectilePool")
	if not pool:
		return
	
	# Get current muzzle
	var muzzle: Node3D = muzzle1 if current_muzzle == 0 else muzzle2
	if not muzzle:
		return
	
	# Spawn projectile
	var spawn_pos = muzzle.global_position
	
	# Firing direction follows the muzzle (angled upward ~3 degrees)
	var firing_direction = muzzle.global_transform.basis.z.normalized()
	
	# Add aircraft velocity to projectile direction
	var final_direction = (firing_direction * projectile_speed + velocity).normalized()
	
	# Bullet orientation: parallel to plane's frame (body), not muzzle direction
	# Use the plane's forward direction (frame basis Z) for visual orientation
	var orientation_direction = frame.global_transform.basis.z.normalized()
	
	# Pass frame's up-vector to preserve plane's roll angle
	var frame_up = frame.global_transform.basis.y.normalized()
	
	pool.spawn_projectile(spawn_pos, final_direction, projectile_speed, orientation_direction, frame_up)
	
	# Spawn muzzle flash
	var blast_pool = get_node_or_null("/root/BlastEffectPool")
	if blast_pool:
		blast_pool.spawn_effect(spawn_pos, firing_direction, mg_muzzle_blast_scale)
	
	# Alternate muzzle for next shot
	current_muzzle = 1 - current_muzzle

func _emit_hud_state() -> void:
	var euler: Vector3 = global_transform.basis.get_euler()
	var pitch_deg: float = rad_to_deg(euler.x)
	var yaw_deg: float = rad_to_deg(euler.y)
	var roll_deg: float = rad_to_deg(euler.z)

	emit_signal("hud_state", throttle, pitch_deg, roll_deg, yaw_deg)

# === Camera System ===

func _switch_to_chase_camera() -> void:
	"""Switch from third-person to chase (first-person) camera with smooth transition"""
	if not camera or not third_view_camera:
		return
	
	_transition_camera(third_view_camera, camera)
	is_third_person_view = false
	print("FighterController: Switched to chase camera (1)")

func _switch_to_third_person_camera() -> void:
	"""Switch from chase to third-person camera with smooth transition"""
	if not camera or not third_view_camera:
		return
	
	# Reset orbit angles
	orbit_yaw = 0.0
	orbit_pitch = 0.0
	
	# Set camera to default position before transition
	_update_default_third_person_camera()
	
	_transition_camera(camera, third_view_camera)
	is_third_person_view = true
	print("FighterController: Switched to third-person camera (3)")

func _reset_orbit_position() -> void:
	"""Reset orbit camera to default position"""
	orbit_yaw = 0.0
	orbit_pitch = 0.0
	# Camera will be updated to default in next _process

func _transition_camera(source_camera: Camera3D, target_camera: Camera3D, duration: float = 0.4) -> void:
	"""Smooth transition from source camera to target camera"""
	if not source_camera or not target_camera:
		if target_camera:
			target_camera.current = true
		return
	
	if source_camera == target_camera:
		target_camera.current = true
		return
	
	# Cancel existing transition
	if camera_transition_tween:
		camera_transition_tween.kill()
	
	# Store transform data
	var start_transform = source_camera.global_transform
	var end_transform = target_camera.global_transform
	var start_fov = source_camera.fov
	var end_fov = target_camera.fov
	
	# Create transition camera
	var transition_cam = Camera3D.new()
	add_child(transition_cam)
	transition_cam.global_transform = start_transform
	transition_cam.fov = start_fov
	transition_cam.current = true
	
	# Animate transition
	camera_transition_tween = create_tween()
	camera_transition_tween.set_parallel(true)
	camera_transition_tween.tween_property(transition_cam, "global_transform", end_transform, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	camera_transition_tween.tween_property(transition_cam, "fov", end_fov, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	
	# Clean up after transition
	camera_transition_tween.chain().tween_callback(func():
		target_camera.current = true
		transition_cam.queue_free()
		camera_transition_tween = null
	)

func _update_orbit_camera() -> void:
	"""Update third-person camera position based on orbit angles"""
	if not third_view_camera or not frame:
		return
	
	# Calculate camera position orbiting around the frame (plane center)
	var orbit_center = frame.global_position
	
	# Start with offset behind the plane
	var offset = Vector3(0, 0, -orbit_distance)
	
	# Rotate by pitch (around X axis)
	offset = offset.rotated(Vector3.RIGHT, orbit_pitch)
	
	# Rotate by yaw (around Y axis)
	offset = offset.rotated(Vector3.UP, orbit_yaw)
	
	# Set camera position
	third_view_camera.global_position = orbit_center + offset
	
	# Look at the orbit center (frame position)
	third_view_camera.look_at(orbit_center)

func _update_default_third_person_camera() -> void:
	"""Keep third-person camera in default fixed position relative to plane"""
	if not third_view_camera:
		return
	
	# Apply the stored local transform relative to the Fighter node
	third_view_camera.transform = third_view_default_local_transform
