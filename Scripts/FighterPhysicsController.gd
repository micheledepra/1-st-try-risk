extends Node3D

## Fighter controller — handles gun firing with muzzle blast effects.
## Supports WW1 (basic thrust/lift on RigidBody3D) and WW2 (aerodynamics addon
## already present in the scene; this controller only adds shooting).
##
## Scene setup expected:
##   Root (Node3D, this script)
##   └─ cessna172  (RigidBody3D or AeroBody3D)
##        ├─ Muzzle1  (Node3D)  — forward/nose guns
##        ├─ Muzzle2  (Node3D)
##        ├─ Muzzle3  (Node3D)  — wing guns (WW2 only)
##        └─ Muzzle4  (Node3D)

# ── Firing ────────────────────────────────────────────────────────────────
@export var fire_rate: float = 0.12          # seconds between bursts
@export var projectile_speed: float = 40.0  # units/s

## Multiplier applied to each muzzle's world-space scale to size the blast.
## Blast radius ≈ muzzle_world_scale × BLAST_SCALE_FACTOR × particle_radius.
const BLAST_SCALE_FACTOR: float = 5.0

# ── WW1 flight (ignored when AeroControlComponent is present) ─────────────
@export var thrust: float = 6000.0  # N — forward engine force
@export var lift_base: float = 6860.0  # N — baseline lift (≈ mass × 9.8)
@export var pitch_torque: float = 800.0
@export var roll_torque: float = 600.0
@export var yaw_torque: float = 400.0

# ── Internal ──────────────────────────────────────────────────────────────
var fire_cooldown: float = 0.0
var muzzle_nodes: Array[Node3D] = []
var plane_body: RigidBody3D = null
var is_ww2_mode: bool = false
var mode_manager: Node = null


func _ready() -> void:
	# Find the RigidBody3D (cessna172) child — works for both WW1 and WW2
	for child in get_children():
		if child is RigidBody3D:
			plane_body = child as RigidBody3D
			break

	if plane_body == null:
		push_warning("FighterPhysicsController: No RigidBody3D child found!")
		return

	# Collect all Muzzle nodes (children of plane_body named "Muzzle*")
	for child in plane_body.get_children():
		if child.name.begins_with("Muzzle"):
			muzzle_nodes.append(child as Node3D)

	if muzzle_nodes.is_empty():
		push_warning("FighterPhysicsController: No Muzzle nodes found under %s!" % plane_body.name)

	# WW2 mode: AeroControlComponent already handles flight
	is_ww2_mode = plane_body.has_node("AeroControlComponent")

	# ModeManager reference (for tactical mode check)
	var map = get_tree().get_first_node_in_group("map")
	if map:
		mode_manager = map.get_node_or_null("ModeManager")


func _process(delta: float) -> void:
	if fire_cooldown > 0.0:
		fire_cooldown -= delta


func _physics_process(_delta: float) -> void:
	if plane_body == null or is_ww2_mode:
		return  # WW2 aerodynamic addon handles its own flight

	# ── WW1 basic flight ──────────────────────────────────────────────────
	var fwd  := -plane_body.global_transform.basis.z
	var up   :=  plane_body.global_transform.basis.y
	var right :=  plane_body.global_transform.basis.x

	# Engine thrust + constant lift to counteract gravity
	plane_body.apply_central_force(fwd * thrust)
	plane_body.apply_central_force(up * lift_base)

	# Pitch (W/S)
	if Input.is_key_pressed(KEY_W):
		plane_body.apply_torque(-right * pitch_torque)
	elif Input.is_key_pressed(KEY_S):
		plane_body.apply_torque(right * pitch_torque)

	# Roll (A/D)
	if Input.is_key_pressed(KEY_A):
		plane_body.apply_torque(fwd * roll_torque)
	elif Input.is_key_pressed(KEY_D):
		plane_body.apply_torque(-fwd * roll_torque)

	# Yaw (Q/E)
	if Input.is_key_pressed(KEY_Q):
		plane_body.apply_torque(up * yaw_torque)
	elif Input.is_key_pressed(KEY_E):
		plane_body.apply_torque(-up * yaw_torque)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			fire_guns()


func fire_guns() -> void:
	"""Fire all gun muzzles: blast effect + projectile from each Muzzle node."""
	if fire_cooldown > 0.0:
		return

	if muzzle_nodes.is_empty():
		return

	for muzzle in muzzle_nodes:
		var spawn_pos := muzzle.global_position
		var direction  := -muzzle.global_transform.basis.z

		# Blast scale derived from this muzzle's world-space scale so the
		# flash is proportionate regardless of how the scene is scaled
		var blast_scale := muzzle.global_transform.basis.get_scale().x * BLAST_SCALE_FACTOR
		BlastEffectPool.spawn_effect(spawn_pos, direction, blast_scale)

		# Spawn projectile (pool available at runtime; silent skip otherwise)
		if has_node("/root/ProjectilePool"):
			ProjectilePool.spawn_projectile(spawn_pos, direction, projectile_speed)

	fire_cooldown = fire_rate


func _unhandled_input(event: InputEvent) -> void:
	# Ctrl+U — exit tactical mode and return to map
	if event.is_action_pressed("toggle_unit_control"):
		if mode_manager != null and mode_manager.current_mode == mode_manager.GameMode.TACTICAL:
			var map = get_tree().get_first_node_in_group("map")
			if map and map.has_method("exit_tactical_mode"):
				map.exit_tactical_mode()
				get_viewport().set_input_as_handled()
				return

	# ESC — toggle mouse capture
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
