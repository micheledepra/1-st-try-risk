extends Node3D

## Fighter Physics Controller for fighterww_1_phy.tscn
## Manages continuous machine gun firing with alternating muzzles and smoke trails
## Three-camera system: Camera3D1 (first-person), Camera3D2 (aiming), Camera3D3 (third-person)

signal hud_state(throttle: float, pitch_deg: float, roll_deg: float, yaw_deg: float)

# === Combat Parameters ===
# Scale: ~4.3 game units per metre. Speeds are real m/s * 4.3.
@export_group("Combat")
@export var fire_rate: float = 0.1  # Seconds between shots (600 RPM)
@export var projectile_speed: float = 3200.0  # WW1/MC.202 MG ~745 m/s * 4.3 u/m
@export var mg_muzzle_blast_scale: float = 0.2  # MG blast: small. The cockpit camera sits right on the guns at 90deg FOV, which magnifies it, so this is kept well below the cannon's ~5.0
@export var mg_bullet_scale: float = 1.35  # MG round = smaller version of the shared cannon round
@export var mg_impact_scale: float = 1.5  # Impact-effect size for MG hits (small vs the tank)

@export_group("Mode")
@export var standalone_mode: bool = false  # Set true for test scene

# === Node References ===
@onready var fighter: Node3D = $cessna172
@onready var muzzle1: Node3D = $cessna172/Muzzle1
@onready var muzzle2: Node3D = $cessna172/Muzzle2
@onready var muzzle3: Node3D = $cessna172.get_node_or_null("Muzzle3")
@onready var muzzle4: Node3D = $cessna172.get_node_or_null("Muzzle4")
@onready var fpv_camera: Camera3D = $cessna172/Camera3D5  # first-person / cockpit camera

var aero_control: Node = null
# Centralized view system (key 1 first-person, key 2 follow, RMB aim-zoom). See UnitViewController.gd
const UnitViewControllerScript = preload("res://Scripts/UnitViewController.gd")
var _view: UnitViewControllerScript = null

# === Muzzle Smoke Trails ===
@onready var smoke_trail_1: GPUParticles3D = null
@onready var smoke_trail_2: GPUParticles3D = null
@onready var smoke_trail_3: GPUParticles3D = null
@onready var smoke_trail_4: GPUParticles3D = null

# === State Variables ===
var current_muzzle_primary: int = 0  # Alternates between 0 (Muzzle1) and 1 (Muzzle2)
var current_muzzle_secondary: int = 0  # Alternates between 0 (Muzzle3) and 1 (Muzzle4)
var has_secondary_muzzles: bool = false
var fire_cooldown: float = 0.0
var is_standalone: bool = false

func _ready() -> void:
	# Detect standalone mode
	is_standalone = standalone_mode or get_node_or_null("/root/GameManager") == null
	
	# Validate node references
	if not fighter:
		push_error("FighterPhysicsController: cessna172 node not found!")
		return
	if not muzzle1 or not muzzle2:
		push_error("FighterPhysicsController: Muzzle nodes not found!")
		return
	has_secondary_muzzles = muzzle3 != null and muzzle4 != null
	if not fpv_camera:
		push_error("FighterPhysicsController: first-person Camera3D (cessna172/Camera3D5) not found!")
		return

	# Create muzzle smoke trails
	_create_muzzle_smoke_trails()

	# Centralized view system owns the first-person / follow / aim-zoom cameras.
	_setup_view_controller()

	# CRITICAL: Ensure VehicleBody3D is awake and processing physics
	if fighter is VehicleBody3D:
		var vehicle_body = fighter as VehicleBody3D
		vehicle_body.sleeping = false
		print("FighterPhysicsController: VehicleBody3D sleeping disabled")
		print("FighterPhysicsController: VehicleBody3D mass=", vehicle_body.mass)
		
		# Check AeroControlComponent
		aero_control = fighter.get_node_or_null("AeroControlComponent")
		if aero_control:
			print("FighterPhysicsController: AeroControlComponent found")
			var control_config = aero_control.get("control_config")
			if control_config:
				var axis_configs = control_config.get("axis_configs")
				if axis_configs:
					print("FighterPhysicsController: Found ", axis_configs.size(), " control axes")
					for axis in axis_configs:
						var axis_name = axis.get("axis_name")
						var use_bindings = axis.get("use_bindings")
						var pos_event = axis.get("positive_event")
						var neg_event = axis.get("negative_event")
						var cum_pos = axis.get("cumulative_positive_event")
						var cum_neg = axis.get("cumulative_negative_event")
						if cum_pos or cum_neg:
							print("  - Axis: %s, use_bindings=%s, cum+=%s, cum-=%s" % [axis_name, use_bindings, cum_pos, cum_neg])
						else:
							print("  - Axis: %s, use_bindings=%s, +event=%s, -event=%s" % [axis_name, use_bindings, pos_event, neg_event])
		else:
			push_error("FighterPhysicsController: AeroControlComponent NOT FOUND!")
	else:
		push_warning("FighterPhysicsController: Fighter is not a VehicleBody3D!")
	
	print("FighterPhysicsController: Initialized (standalone=%s) - view system active" % is_standalone)
	print("FighterPhysicsController: Flight controls via project Input Map - WASDQE, PageUp/Down for throttle")
	_emit_hud_state()

func _create_muzzle_smoke_trails() -> void:
	"""Create continuous smoke trail particles at muzzles"""
	smoke_trail_1 = _create_smoke_trail(muzzle1, "SmokeTrail1")
	smoke_trail_2 = _create_smoke_trail(muzzle2, "SmokeTrail2")
	smoke_trail_3 = _create_smoke_trail(muzzle3, "SmokeTrail3")
	smoke_trail_4 = _create_smoke_trail(muzzle4, "SmokeTrail4")
	print("FighterPhysicsController: Muzzle smoke trails created")

func _create_smoke_trail(target_muzzle: Node3D, trail_name: String) -> GPUParticles3D:
	if not target_muzzle:
		return null
	var smoke_trail = GPUParticles3D.new()
	smoke_trail.name = trail_name
	smoke_trail.emitting = false
	smoke_trail.amount = 50
	smoke_trail.lifetime = 0.8
	smoke_trail.one_shot = false
	smoke_trail.explosiveness = 0.0
	smoke_trail.randomness = 0.3
	smoke_trail.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))

	var smoke_material = ParticleProcessMaterial.new()
	smoke_material.direction = Vector3(0, 0, 1)
	smoke_material.spread = 15.0
	smoke_material.initial_velocity_min = 2.0
	smoke_material.initial_velocity_max = 5.0
	smoke_material.gravity = Vector3(0, -0.5, 0)
	smoke_material.scale_min = 0.1
	smoke_material.scale_max = 0.3
	smoke_material.color = Color(0.6, 0.6, 0.6, 0.7)
	smoke_trail.process_material = smoke_material

	var smoke_mesh = QuadMesh.new()
	smoke_mesh.size = Vector2(0.2, 0.2)
	smoke_trail.draw_pass_1 = smoke_mesh

	target_muzzle.add_child(smoke_trail)
	return smoke_trail

func _setup_view_controller() -> void:
	"""Attach the shared unit-view system (first-person / follow / aim-zoom)."""
	_view = UnitViewControllerScript.new()
	_view.name = "UnitViewController"
	add_child(_view)
	_view.configure(self, fpv_camera, {
		"follow_target": fighter,
		"forward_node": fighter,
		"fp_fov": 90.0,
		"follow_fov": 70.0,
		"follow_distance": 18.0,
		"follow_height": 6.0,
	})

func _process(delta: float) -> void:
	"""Handle continuous firing and debug flight inputs"""
	# Debug: Log flight input reception with actual strength values
	if is_standalone and Engine.get_frames_drawn() % 60 == 0:  # Log once per second
		var inputs_active = []
		var pitch_up_str = Input.get_action_strength("pitch_up")
		var pitch_down_str = Input.get_action_strength("pitch_down")
		var yaw_left_str = Input.get_action_strength("yaw_left")
		var yaw_right_str = Input.get_action_strength("yaw_right")
		var roll_left_str = Input.get_action_strength("roll_left")
		var roll_right_str = Input.get_action_strength("roll_right")
		var throttle_up_str = Input.get_action_strength("throttle_up")
		var throttle_down_str = Input.get_action_strength("throttle_down")
		
		if pitch_up_str > 0: inputs_active.append("pitch_up=%.2f" % pitch_up_str)
		if pitch_down_str > 0: inputs_active.append("pitch_down=%.2f" % pitch_down_str)
		if yaw_left_str > 0: inputs_active.append("yaw_left=%.2f" % yaw_left_str)
		if yaw_right_str > 0: inputs_active.append("yaw_right=%.2f" % yaw_right_str)
		if roll_left_str > 0: inputs_active.append("roll_left=%.2f" % roll_left_str)
		if roll_right_str > 0: inputs_active.append("roll_right=%.2f" % roll_right_str)
		if throttle_up_str > 0: inputs_active.append("throttle_up=%.2f" % throttle_up_str)
		if throttle_down_str > 0: inputs_active.append("throttle_down=%.2f" % throttle_down_str)
		
		if inputs_active.size() > 0:
			print("INPUT STRENGTHS: ", inputs_active)
		else:
			# Show VehicleBody3D state when no inputs
			if fighter is VehicleBody3D:
				var vb = fighter as VehicleBody3D
				print("Fighter: pos.y=%.2f sleeping=%s vel=%.2f" % [vb.global_position.y, vb.sleeping, vb.linear_velocity.length()])
	
	# Decrease cooldown
	fire_cooldown = max(0.0, fire_cooldown - delta)
	
	# Continuous firing while LMB held
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and fire_cooldown <= 0.0:
		_fire_projectile()
		fire_cooldown = fire_rate

func _fire_from_pair(
	muzzle_a: Node3D,
	muzzle_b: Node3D,
	smoke_a: GPUParticles3D,
	smoke_b: GPUParticles3D,
	current_index: int,
	pool,
	blast_pool
) -> int:
	var muzzle: Node3D = muzzle_a if current_index == 0 else muzzle_b
	var smoke_trail: GPUParticles3D = smoke_a if current_index == 0 else smoke_b
	if not muzzle:
		return current_index

	var spawn_pos = muzzle.global_position
	var firing_direction = muzzle.global_transform.basis.z.normalized()

	# Inherit the plane's velocity so rounds fired in flight carry the aircraft's momentum
	# (otherwise fast-moving fighters' bullets appear to drift backwards).
	var plat_vel: Vector3 = Vector3.ZERO
	if fighter is RigidBody3D:
		plat_vel = (fighter as RigidBody3D).linear_velocity

	# Same shared round as the tank cannon - just a smaller MG version (bullet_scale),
	# so it inherits identical velocity/drag/gravity/swept-collision rules.
	pool.spawn_projectile(spawn_pos, firing_direction, projectile_speed, mg_impact_scale, plat_vel, mg_bullet_scale)

	if blast_pool:
		blast_pool.spawn_effect(spawn_pos, firing_direction, mg_muzzle_blast_scale)  # small MG blast

	if smoke_trail:
		smoke_trail.emitting = true
		get_tree().create_timer(0.15).timeout.connect(func():
			if smoke_trail:
				smoke_trail.emitting = false
		)

	return 1 - current_index

func _fire_projectile() -> void:
	"""Fire projectiles from available muzzle pairs with muzzle flash and smoke"""
	# Unified bullet: fighters now fire the same Projectile as the tank cannon (smaller MG version)
	var pool = get_node_or_null("/root/ProjectilePool")
	if not pool:
		if is_standalone:
			push_warning("FighterPhysicsController: ProjectilePool not found (standalone mode)")
		return

	var blast_pool = get_node_or_null("/root/BlastEffectPool")

	current_muzzle_primary = _fire_from_pair(
		muzzle1,
		muzzle2,
		smoke_trail_1,
		smoke_trail_2,
		current_muzzle_primary,
		pool,
		blast_pool
	)

	if has_secondary_muzzles:
		current_muzzle_secondary = _fire_from_pair(
			muzzle3,
			muzzle4,
			smoke_trail_3,
			smoke_trail_4,
			current_muzzle_secondary,
			pool,
			blast_pool
		)

func _physics_process(_delta: float) -> void:
	"""Monitor physics state for debugging"""
	if is_standalone and Engine.get_physics_frames() % 60 == 0:
		if fighter is VehicleBody3D:
			var vb = fighter as VehicleBody3D
			print("[PHYSICS] pos.y=%.2f sleeping=%s lin_vel=%s ang_vel=%s" % [
				vb.global_position.y,
				vb.sleeping,
				vb.linear_velocity,
				vb.angular_velocity
			])

	_emit_hud_state()

func _get_throttle_value() -> float:
	if aero_control and aero_control.has_method("get_control_command"):
		return clamp(aero_control.get_control_command("throttle"), 0.0, 1.0)
	return 0.0

func _emit_hud_state() -> void:
	var source: Node3D = fighter if fighter else self
	var euler: Vector3 = source.global_transform.basis.get_euler()
	var pitch_deg: float = rad_to_deg(euler.x)
	var roll_deg: float = rad_to_deg(euler.z)
	var yaw_deg: float = rad_to_deg(euler.y)

	emit_signal("hud_state", _get_throttle_value(), pitch_deg, roll_deg, yaw_deg)
