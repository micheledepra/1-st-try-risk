extends Node3D

## T-34 tank controller. Same three-channel model as the Panther (hull / turret /
## barrel) feeding the unified cannon round (PType.CANNON), with T-34-specific
## node paths, elevation axis and stats. Channels are gated by UnitCombatState.

const Combat = preload("res://Scripts/UnitCombatState.gd")

# Scale: ~4.3 game units per metre. Speeds below are real m/s * 4.3.
@export var max_speed_forward: float = 32.0
@export var max_speed_reverse: float = 12.0
@export var acceleration: float = 10.0
@export var braking: float = 18.0
@export var rotation_speed: float = 0.8
@export var mouse_sensitivity: float = 0.002
@export var turret_traverse_speed: float = 0.52
@export var barrel_max_elevation: float = 110.0
@export var barrel_max_depression: float = 70.0

# Shooting
@export var fire_rate: float = 0.2  # seconds between shots

var effect_scale_multiplier: float = 1.0

@onready var body_pivot: Node3D = $BodyPivot
@onready var turret_pivot: Node3D = $TurretPivot
@onready var barrell_pivot: Node3D = $TurretPivot/turret/BarrellPivot
@onready var barrel_tip: Marker3D = $TurretPivot/turret/BarrellPivot/BarrelTip
@onready var fpv_camera: Camera3D = get_node_or_null("TurretPivot/turret/BarrellPivot/Camera3D")

const UnitViewControllerScript = preload("res://Scripts/UnitViewController.gd")
var _view: UnitViewControllerScript = null
const UnitSightScript = preload("res://Scripts/UnitSight.gd")
var _sight: UnitSightScript = null

var cylinder1_initial_pos: Vector3
var cylinder2_initial_pos: Vector3

var fire_cooldown: float = 0.0
var mode_manager: Node = null
var fire_requested: bool = false
var platform_velocity: Vector3 = Vector3.ZERO
var current_speed: float = 0.0
var turret_yaw_target: float = 0.0
const MAX_TURRET_LEAD: float = 0.4

func _ready() -> void:
	var map = get_tree().get_first_node_in_group("map")
	if map:
		mode_manager = map.get_node_or_null("ModeManager")

	_setup_view_controller()
	_setup_sight()

	if _is_standalone_mode():
		_hide_territory_labels()
		effect_scale_multiplier = 1.0
	else:
		await get_tree().process_frame
		effect_scale_multiplier = global_transform.basis.get_scale().x

	if has_node("TurretPivot/BarrellPivot/Cylinder001"):
		var cyl1 = $TurretPivot/turret/BarrellPivot/Cylinder001
		cylinder1_initial_pos = cyl1.position
		cyl1.rotation = Vector3.ZERO
		cyl1.top_level = false
	if has_node("TurretPivot/BarrellPivot/Cylinder002"):
		var cyl2 = $TurretPivot/turret/BarrellPivot/Cylinder002
		cylinder2_initial_pos = cyl2.position
		cyl2.rotation = Vector3.ZERO
		cyl2.top_level = false

	_register_combat_metadata()

func _register_combat_metadata() -> void:
	set_meta("unit_type", Combat.UNIT_TANK)
	if not has_meta("player_color"):
		set_meta("player_color", Color(0.85, 0.7, 0.25))
	set_meta("effect_scale", effect_scale_multiplier)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _view != null and _view.consumes_mouse_motion():
			return
		if UnitCombatState.is_locked(self, Combat.Channel.TURRET):
			return
		turret_yaw_target += -event.relative.x * mouse_sensitivity
		# T-34 barrel elevates on rotation.y (model authored rotated).
		var new_rotation = barrell_pivot.rotation.y + (-event.relative.y * mouse_sensitivity)
		new_rotation = clamp(new_rotation, deg_to_rad(barrel_max_depression), deg_to_rad(barrel_max_elevation))
		barrell_pivot.rotation.y = new_rotation

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			fire_requested = true

func _process(delta: float) -> void:
	var prev_position: Vector3 = global_position

	if fire_cooldown > 0.0:
		fire_cooldown -= delta

	var move_direction: float = 0.0
	var rotate_direction: float = 0.0
	# Note: T-34 W/S are inverted vs Panther (kept as authored).
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_S):
		move_direction = 1.0
	elif Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_W):
		move_direction = -1.0
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		rotate_direction = 1.0
	elif Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		rotate_direction = -1.0

	if UnitCombatState.is_locked(self, Combat.Channel.MOVE):
		move_direction = 0.0
		rotate_direction = 0.0

	if not UnitCombatState.is_locked(self, Combat.Channel.TURRET):
		turret_yaw_target = clamp(turret_yaw_target, turret_pivot.rotation.y - MAX_TURRET_LEAD, turret_pivot.rotation.y + MAX_TURRET_LEAD)
		var max_yaw_step = turret_traverse_speed * delta
		turret_pivot.rotation.y += clamp(turret_yaw_target - turret_pivot.rotation.y, -max_yaw_step, max_yaw_step)
	else:
		turret_yaw_target = turret_pivot.rotation.y

	if rotate_direction != 0.0:
		body_pivot.rotate_y(rotate_direction * rotation_speed * delta)

	var target_speed: float = 0.0
	if move_direction > 0.0:
		target_speed = max_speed_forward
	elif move_direction < 0.0:
		target_speed = -max_speed_reverse
	var accelerating: bool = target_speed != 0.0 and abs(target_speed) > abs(current_speed) and current_speed * target_speed >= 0.0
	var rate: float = acceleration if accelerating else braking
	current_speed = move_toward(current_speed, target_speed, rate * delta)
	if absf(current_speed) > 0.0001:
		var forward = -body_pivot.global_transform.basis.z.normalized()
		global_position += forward * current_speed * delta

	if delta > 0.0:
		platform_velocity = (global_position - prev_position) / delta
	else:
		platform_velocity = Vector3.ZERO

	if fire_requested:
		fire_requested = false
		fire_projectile()

func fire_projectile() -> void:
	if not _can_fire():
		return
	if fire_cooldown > 0.0:
		return
	if UnitCombatState.is_locked(self, Combat.Channel.FIRE):
		return
	if barrel_tip == null:
		push_warning("TankControllerT34: BarrelTip marker not found!")
		return

	var spawn_pos = barrel_tip.global_position
	var direction = -barrel_tip.global_transform.basis.z

	BlastEffectPool.spawn_effect(spawn_pos, direction, Combat.PType.CANNON, effect_scale_multiplier)
	ProjectilePool.spawn(Combat.PType.CANNON, spawn_pos, direction, platform_velocity, self, effect_scale_multiplier)
	fire_cooldown = fire_rate

func get_aim_ray() -> Dictionary:
	"""Single source of truth for where the cannon round goes, read by UnitSight."""
	return {
		"origin": barrel_tip.global_position,
		"dir": -barrel_tip.global_transform.basis.z,
		"platform_velocity": platform_velocity,
		"ptype": Combat.PType.CANNON,
	}

func _can_fire() -> bool:
	if _is_standalone_mode():
		return true
	if mode_manager == null:
		return true  # no tactical manager present (e.g. the unit-test scene)
	return mode_manager.current_mode == mode_manager.GameMode.TACTICAL

func _setup_view_controller() -> void:
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

func _setup_sight() -> void:
	if _view == null:
		return
	_sight = UnitSightScript.new()
	_sight.name = "UnitSight"
	add_child(_sight)
	_sight.bind(self, _view, self, UnitSightScript.Style.TANK)

func _is_standalone_mode() -> bool:
	return get_node_or_null("/root/GameManager") == null

func _hide_territory_labels():
	var map = get_node_or_null("/root/Map")
	if map:
		var color_manager = map.get_node_or_null("TerritoryColorManager")
		if color_manager and color_manager.has_method("set_labels_visible"):
			color_manager.set_labels_visible(false)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_unit_control"):
		if mode_manager != null and mode_manager.current_mode == mode_manager.GameMode.TACTICAL:
			var map = get_tree().get_first_node_in_group("map")
			if map and map.has_method("exit_tactical_mode"):
				map.exit_tactical_mode()
				get_viewport().set_input_as_handled()
				return

	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _exit_tree() -> void:
	UnitCombatState.reset_unit(self)
