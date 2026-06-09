extends Node3D

## Anti-Aircraft controller. Drives the rig, aims the dual barrels, and fires the
## unified AA round (UnitCombatState.PType.AA) through ProjectilePool. Turret and
## firing are gated independently by UnitCombatState locks; a kill freezes it.

const Combat = preload("res://Scripts/UnitCombatState.gd")

# Movement parameters
@export var movement_speed: float = 3.0
@export var rotation_speed: float = 1.1
@export var mouse_sensitivity: float = 0.002

# Barrel constraints
@export var barrel_max_elevation: float = 85.0
@export var barrel_max_depression: float = -10.0

# Shooting
@export var fire_rate: float = 0.14  # seconds between shots (full-auto while held)

# Standalone testing
@export var standalone_mode: bool = true

# Node references
@onready var body_pivot: Node3D = $BodyPivot
@onready var turret_pivot: Node3D = $TurretPivot
@onready var barrel1: Node3D = $TurretPivot/Turret/bone29/Barrel1
@onready var barrel2: Node3D = $TurretPivot/Turret/bone49/Barrel2
@onready var muzzle1: Node3D = $TurretPivot/Turret/bone29/Barrel1/Muzzle1
@onready var muzzle2: Node3D = $TurretPivot/Turret/bone49/Barrel2/Muzzle2
@onready var fpv_camera: Camera3D = get_node_or_null("TurretPivot/Turret/bone49/Barrel2/Camera3D")

var fire_cooldown: float = 0.0
var current_barrel: int = 0
var is_standalone: bool = false
var effect_scale_multiplier: float = 1.0

const UnitViewControllerScript = preload("res://Scripts/UnitViewController.gd")
var _view: UnitViewControllerScript = null
const UnitSightScript = preload("res://Scripts/UnitSight.gd")
var _sight: UnitSightScript = null

func _ready() -> void:
	is_standalone = standalone_mode or get_node_or_null("/root/GameManager") == null
	if not turret_pivot or not barrel1 or not barrel2 or not muzzle1 or not muzzle2:
		push_error("AAController: Missing required child nodes")
		set_process(false)
		set_process_input(false)
		return

	_setup_view_controller()
	_setup_sight()
	_register_combat_metadata()
	_ensure_hitbox()

	if standalone_mode:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _ensure_hitbox() -> void:
	"""The AA has no authored collision body; give it a layer-2 hitbox so it can
	be hit by projectiles (region is generic — the AA has no turret/body split)."""
	if has_node("Hitbox"):
		return
	var hb := Area3D.new()
	hb.name = "Hitbox"
	hb.collision_layer = 2  # UnitHitboxes
	hb.collision_mask = 4   # Projectiles
	hb.set_meta("hit_region", "generic")
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 2.6, 3.6)
	cs.shape = box
	cs.position = Vector3(0.0, 1.3, 0.0)
	hb.add_child(cs)
	add_child(hb)

func _register_combat_metadata() -> void:
	"""Make the AA a valid combat target: type + (fallback) colour + scale."""
	set_meta("unit_type", Combat.UNIT_AA)
	if not has_meta("player_color"):
		set_meta("player_color", Color(0.3, 0.55, 0.95))
	if is_standalone:
		effect_scale_multiplier = 1.0
	else:
		await get_tree().process_frame
		effect_scale_multiplier = global_transform.basis.get_scale().x
	set_meta("effect_scale", effect_scale_multiplier)

func _setup_view_controller() -> void:
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

func _setup_sight() -> void:
	if _view == null:
		return
	_sight = UnitSightScript.new()
	_sight.name = "UnitSight"
	add_child(_sight)
	_sight.bind(self, _view, self, UnitSightScript.Style.AA)

func get_aim_ray() -> Dictionary:
	"""Single source of truth for where AA rounds go, read by UnitSight. Origin is the
	mid-point of the two alternating muzzles; direction follows barrel2 (the camera barrel)."""
	return {
		"origin": (muzzle1.global_position + muzzle2.global_position) * 0.5,
		"dir": -muzzle2.global_transform.basis.z,
		"platform_velocity": Vector3.ZERO,
		"ptype": Combat.PType.AA,
	}

func _input(event: InputEvent) -> void:
	if not _can_process_input():
		return
	if is_standalone and event is InputEventKey:
		if event.pressed and event.keycode == KEY_ESCAPE:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED)
			return

	# Turret aim (yaw + barrel elevation) — blocked while the turret is locked.
	if event is InputEventMouseMotion:
		if _view != null and _view.consumes_mouse_motion():
			return
		if UnitCombatState.is_locked(self, Combat.Channel.TURRET):
			return
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED or not is_standalone:
			turret_pivot.rotate_y(-event.relative.x * mouse_sensitivity)
			_rotate_barrels(-event.relative.y * mouse_sensitivity)

func _process(delta: float) -> void:
	if not _can_process_input():
		return
	if fire_cooldown > 0:
		fire_cooldown -= delta

	# Drive (W/S/A/D) — blocked while movement is locked.
	if not UnitCombatState.is_locked(self, Combat.Channel.MOVE):
		var move_direction: float = 0.0
		var rotate_direction: float = 0.0
		if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
			move_direction = 1.0
		elif Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
			move_direction = -1.0
		if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
			rotate_direction = 1.0
		elif Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
			rotate_direction = -1.0
		if rotate_direction != 0.0:
			body_pivot.rotate_y(rotate_direction * rotation_speed * delta)
		if move_direction != 0.0:
			var forward = -body_pivot.global_transform.basis.z.normalized()
			global_position += forward * move_direction * movement_speed * delta

	# Fire (full-auto) — blocked while firing is locked.
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and fire_cooldown <= 0:
		if not UnitCombatState.is_locked(self, Combat.Channel.FIRE):
			fire_projectile()
			fire_cooldown = fire_rate

func _can_process_input() -> bool:
	if is_standalone:
		return true
	var mm = get_node_or_null("/root/ModeManager")
	return mm != null and mm.current_mode == mm.GameMode.TACTICAL

func _rotate_barrels(vertical_delta: float) -> void:
	var new_rotation = barrel1.rotation.x + vertical_delta
	new_rotation = clamp(new_rotation, deg_to_rad(-barrel_max_elevation), deg_to_rad(-barrel_max_depression))
	barrel1.rotation.x = new_rotation
	barrel2.rotation.x = new_rotation

func fire_projectile() -> void:
	var current_muzzle: Node3D = muzzle1 if current_barrel == 0 else muzzle2
	current_barrel = 1 - current_barrel
	var spawn_pos = current_muzzle.global_position
	var direction = -current_muzzle.global_transform.basis.z.normalized()
	BlastEffectPool.spawn_effect(spawn_pos, direction, Combat.PType.AA, effect_scale_multiplier)
	ProjectilePool.spawn(Combat.PType.AA, spawn_pos, direction, Vector3.ZERO, self, effect_scale_multiplier)

func _exit_tree() -> void:
	if is_standalone:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	UnitCombatState.reset_unit(self)
