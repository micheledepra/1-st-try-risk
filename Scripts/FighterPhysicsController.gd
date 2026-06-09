extends Node3D

## Fighter controller (live, addon AeroBody-based plane). Manages MG firing and
## the kill/perturb behaviour; flight itself is the godot_aerodynamic_physics
## addon reading the Input Map. Fires the unified MG round (PType.MG). A fatal
## hit jams the aileron + rudder and cuts the flight assist so the plane spins.

signal hud_state(throttle: float, pitch_deg: float, roll_deg: float, yaw_deg: float)

const Combat = preload("res://Scripts/UnitCombatState.gd")

# === Combat Parameters ===
@export_group("Combat")
@export var fire_rate: float = 0.1  # Seconds between shots (600 RPM)
@export var mg_muzzle_scale: float = 0.6  # muzzle-blast size factor (cockpit cam magnifies, keep small)
@export var mg_impact_scale: float = 1.0  # impact-effect size for MG hits

@export_group("Mode")
@export var standalone_mode: bool = false

# === Node References ===
@onready var fighter: Node3D = $cessna172
@onready var muzzle1: Node3D = $cessna172/Muzzle1
@onready var muzzle2: Node3D = $cessna172/Muzzle2
@onready var muzzle3: Node3D = $cessna172.get_node_or_null("Muzzle3")
@onready var muzzle4: Node3D = $cessna172.get_node_or_null("Muzzle4")
@onready var fpv_camera: Camera3D = $cessna172/Camera3D5

var aero_control: Node = null
const UnitViewControllerScript = preload("res://Scripts/UnitViewController.gd")
var _view: UnitViewControllerScript = null
const UnitSightScript = preload("res://Scripts/UnitSight.gd")
var _sight: UnitSightScript = null

@onready var smoke_trail_1: GPUParticles3D = null
@onready var smoke_trail_2: GPUParticles3D = null
@onready var smoke_trail_3: GPUParticles3D = null
@onready var smoke_trail_4: GPUParticles3D = null

var current_muzzle_primary: int = 0
var current_muzzle_secondary: int = 0
var has_secondary_muzzles: bool = false
var fire_cooldown: float = 0.0
var is_standalone: bool = false

# Kill / control-jam state (a fatal hit jams the surfaces into a natural spin).
var _dead: bool = false
var _kill_roll: float = 0.0
var _kill_yaw: float = 0.0
var _kill_pitch: float = 0.0
# Brief control perturbation ("random control switch" on a non-fatal hit).
var _perturb_timer: float = 0.0
var _perturb_roll: float = 0.0
var _perturb_yaw: float = 0.0

func _ready() -> void:
	is_standalone = standalone_mode or get_node_or_null("/root/GameManager") == null
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

	_create_muzzle_smoke_trails()
	_setup_view_controller()
	_setup_sight()
	_register_combat_metadata()

	if fighter is VehicleBody3D:
		(fighter as VehicleBody3D).sleeping = false
		aero_control = fighter.get_node_or_null("AeroControlComponent")
	_emit_hud_state()

func _register_combat_metadata() -> void:
	"""Make the plane a valid combat target. Its VehicleBody (layer 1) is the
	hittable; classification walks up to this root via unit_type/player_color."""
	set_meta("unit_type", Combat.UNIT_PLANE)
	if not has_meta("player_color"):
		set_meta("player_color", Color(0.9, 0.3, 0.2))
	set_meta("effect_scale", 1.0)

func _create_muzzle_smoke_trails() -> void:
	smoke_trail_1 = _create_smoke_trail(muzzle1, "SmokeTrail1")
	smoke_trail_2 = _create_smoke_trail(muzzle2, "SmokeTrail2")
	smoke_trail_3 = _create_smoke_trail(muzzle3, "SmokeTrail3")
	smoke_trail_4 = _create_smoke_trail(muzzle4, "SmokeTrail4")

func _create_smoke_trail(target_muzzle: Node3D, trail_name: String) -> GPUParticles3D:
	if not target_muzzle:
		return null
	var smoke_trail = GPUParticles3D.new()
	smoke_trail.name = trail_name
	smoke_trail.emitting = false
	smoke_trail.amount = 30
	smoke_trail.lifetime = 0.7
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

func _setup_sight() -> void:
	if _view == null:
		return
	_sight = UnitSightScript.new()
	_sight.name = "UnitSight"
	add_child(_sight)
	_sight.bind(self, _view, self, UnitSightScript.Style.FIGHTER)

func get_aim_ray() -> Dictionary:
	"""Single source of truth for the fighter's ONE reticle, read by UnitSight. The guns
	are toed-in to converge down-range, so aim along the harmonized centerline instead of
	any single canted barrel: the centroid of the muzzles and their averaged forward (+Z),
	where the symmetric left/right cant cancels. Inherits the plane's velocity."""
	var origin: Vector3 = Vector3.ZERO
	var fwd: Vector3 = Vector3.ZERO
	var n: int = 0
	for m in [muzzle1, muzzle2, muzzle3, muzzle4]:
		if m != null:
			origin += (m as Node3D).global_position
			fwd += (m as Node3D).global_transform.basis.z
			n += 1
	if n > 0:
		origin /= float(n)
		fwd = fwd.normalized()
	else:
		origin = global_position
		fwd = global_transform.basis.z
	var plat_vel: Vector3 = Vector3.ZERO
	if fighter is RigidBody3D:
		plat_vel = (fighter as RigidBody3D).linear_velocity
	return {
		"origin": origin,
		"dir": fwd,
		"platform_velocity": plat_vel,
		"ptype": Combat.PType.MG,
	}

func _process(delta: float) -> void:
	# A fatal hit jams the surfaces every frame so the plane spins out naturally.
	if _dead:
		_apply_jam_inputs()
		return

	# A non-fatal hit briefly perturbs the controls ("random control switch").
	if _perturb_timer > 0.0:
		_perturb_timer -= delta
		if aero_control:
			aero_control.set_control_input("roll", _perturb_roll)
			aero_control.set_control_input("yaw", _perturb_yaw)

	fire_cooldown = max(0.0, fire_cooldown - delta)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and fire_cooldown <= 0.0:
		if not UnitCombatState.is_locked(self, Combat.Channel.FIRE):
			_fire_projectile()
			fire_cooldown = fire_rate

func apply_kill() -> void:
	"""Fatal hit: jam aileron + rudder into a random stuck combination, cut the
	flight assist, and lock out the player's bindings so the plane spins down."""
	_dead = true
	_kill_roll = (1.0 if randf() < 0.5 else -1.0) * randf_range(0.6, 1.0)
	_kill_yaw = (1.0 if randf() < 0.5 else -1.0) * randf_range(0.5, 1.0)
	_kill_pitch = randf_range(-0.35, 0.1)
	if aero_control:
		aero_control.flight_assist = null  # stop the PID auto-recovery
		var cfg = aero_control.get("control_config")
		if cfg:
			var axes = cfg.get("axis_configs")
			if axes:
				for ax in axes:
					if ax.get("axis_name") in ["roll", "yaw", "pitch", "throttle"]:
						ax.set("use_bindings", false)

func perturb_controls(seconds: float) -> void:
	"""Brief loss of control on a non-fatal hit."""
	if _dead:
		return
	_perturb_timer = max(_perturb_timer, seconds)
	_perturb_roll = (1.0 if randf() < 0.5 else -1.0) * randf_range(0.5, 0.9)
	_perturb_yaw = (1.0 if randf() < 0.5 else -1.0) * randf_range(0.4, 0.8)

func _apply_jam_inputs() -> void:
	if aero_control:
		aero_control.set_control_input("roll", _kill_roll)
		aero_control.set_control_input("yaw", _kill_yaw)
		aero_control.set_control_input("pitch", _kill_pitch)
		aero_control.set_control_input("throttle", 0.0)

func _fire_from_pair(muzzle_a: Node3D, muzzle_b: Node3D, smoke_a: GPUParticles3D, smoke_b: GPUParticles3D, current_index: int) -> int:
	var muzzle: Node3D = muzzle_a if current_index == 0 else muzzle_b
	var smoke_trail: GPUParticles3D = smoke_a if current_index == 0 else smoke_b
	if not muzzle:
		return current_index

	var spawn_pos = muzzle.global_position
	var firing_direction = muzzle.global_transform.basis.z.normalized()

	# Inherit the plane's velocity so rounds fired in flight carry its momentum
	# (the previous path dropped this, making bullets hang big at the muzzle).
	var plat_vel: Vector3 = Vector3.ZERO
	if fighter is RigidBody3D:
		plat_vel = (fighter as RigidBody3D).linear_velocity

	BlastEffectPool.spawn_effect(spawn_pos, firing_direction, Combat.PType.MG, mg_muzzle_scale)
	ProjectilePool.spawn(Combat.PType.MG, spawn_pos, firing_direction, plat_vel, self, mg_impact_scale)

	if smoke_trail:
		smoke_trail.emitting = true
		get_tree().create_timer(0.15).timeout.connect(func():
			if smoke_trail:
				smoke_trail.emitting = false
		)

	return 1 - current_index

func _fire_projectile() -> void:
	current_muzzle_primary = _fire_from_pair(muzzle1, muzzle2, smoke_trail_1, smoke_trail_2, current_muzzle_primary)
	if has_secondary_muzzles:
		current_muzzle_secondary = _fire_from_pair(muzzle3, muzzle4, smoke_trail_3, smoke_trail_4, current_muzzle_secondary)

func _physics_process(_delta: float) -> void:
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

func _exit_tree() -> void:
	UnitCombatState.reset_unit(self)
