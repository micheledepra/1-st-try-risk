extends Node
class_name UnitViewController

## Centralized unit-view system shared by every controllable unit (tanks, planes, AA).
##
## ONE place owns all camera/view behaviour, replacing the old per-unit duplicates
## (CameraZoomOnRMB.gd, units_camera_3d.gd on units, and the copy-pasted
## _switch_to_camera/_transition_camera blocks that used to live in each controller).
##
## Three uniform views, identical on every unit:
##   * Key 1  -> FIRST_PERSON (default): the unit's cockpit / over-gun camera.
##   * Key 2  -> FOLLOW: a top-behind chase camera that tracks the unit.
##              Middle-mouse free-looks/orbits (auto-returns after release).
##   * RMB    -> AIM/ZOOM: hold to zoom the CURRENT view in. The press snaps to a
##              ~25% tighter FOV ("aim"); keeping it held deepens the zoom. Release
##              returns to the view's base FOV. Works in both first-person and follow.
##
## A unit only needs ONE authored camera (its first-person camera). The follow camera
## is created at runtime, so scenes no longer ship redundant chase/aim camera nodes.

enum View { FIRST_PERSON, FOLLOW }

# === Tunables (overridable via configure()) =================================
var first_person_fov: float = 75.0
var follow_fov: float = 70.0
var aim_zoom_fraction: float = 0.25      # initial RMB "aim" snap: 25% tighter FOV
var aim_zoom_max_fraction: float = 0.60  # deepest zoom while RMB held: 60% tighter FOV
var aim_deepen_time: float = 1.0         # seconds of holding RMB to reach the deepest zoom
var zoom_lerp_speed: float = 9.0         # how fast the FOV chases its target
var transition_duration: float = 0.4     # view-switch blend time (seconds)

# Follow-camera placement, in unit-local metres (auto-scaled by the unit's world scale).
var follow_distance: float = 12.0
var follow_height: float = 6.0
var freelook_sensitivity: float = 0.005
var freelook_return_delay: float = 0.6
var freelook_return_speed: float = 3.0
var freelook_pitch_min_deg: float = -80.0
var freelook_pitch_max_deg: float = 25.0

# === Wiring (set in configure()) ===========================================
var _owner_unit: Node3D = null     # the controllable unit root (cameras parent to it)
var _follow_target: Node3D = null  # node whose global_position the follow camera orbits
var _forward_node: Node3D = null   # node whose -Z is "forward" (for default behind placement)
var _fp_camera: Camera3D = null    # the existing first-person scene camera
var _follow_camera: Camera3D = null # created at runtime

# === Runtime state =========================================================
var _view: int = View.FIRST_PERSON
var _active_camera: Camera3D = null
var _rmb_held: bool = false
var _rmb_hold_time: float = 0.0
var _free_looking: bool = false
var _orbit_yaw: float = 0.0
var _orbit_pitch: float = 0.0
var _return_timer: float = 0.0
var _transition_tween: Tween = null
var _configured: bool = false


func configure(owner_unit: Node3D, fp_camera: Camera3D, opts: Dictionary = {}) -> void:
	"""Bind this view controller to a unit. Call once from the unit controller's _ready().
	opts keys: follow_target, forward_node, fp_fov, follow_fov, follow_distance, follow_height."""
	_owner_unit = owner_unit
	_fp_camera = fp_camera
	if _owner_unit == null or _fp_camera == null:
		push_warning("UnitViewController: configure() needs an owner unit and a first-person camera")
		return

	_follow_target = opts.get("follow_target", owner_unit)
	_forward_node = opts.get("forward_node", owner_unit)
	first_person_fov = opts.get("fp_fov", first_person_fov)
	follow_fov = opts.get("follow_fov", follow_fov)
	follow_distance = opts.get("follow_distance", follow_distance)
	follow_height = opts.get("follow_height", follow_height)

	# Canonical first-person FOV lives here now, not scattered across scenes/comments.
	_fp_camera.fov = first_person_fov

	_build_follow_camera()

	_view = View.FIRST_PERSON
	_active_camera = _fp_camera

	# If nothing else has claimed the viewport yet (e.g. running this unit scene directly),
	# show the first-person view. In the real game / test harness, Map or the test manager
	# already makes a camera current, so we don't steal it.
	if get_viewport() and get_viewport().get_camera_3d() == null:
		_fp_camera.current = true

	_configured = true


func _build_follow_camera() -> void:
	_follow_camera = Camera3D.new()
	_follow_camera.name = "FollowCamera"
	_follow_camera.fov = follow_fov
	_follow_camera.current = false
	_owner_unit.add_child(_follow_camera)
	_update_follow_transform()


# === Input =================================================================

func _input(event: InputEvent) -> void:
	if not _configured or not _should_handle():
		return

	if event.is_action_pressed("view_first_person"):
		set_view(View.FIRST_PERSON)
	elif event.is_action_pressed("view_follow"):
		set_view(View.FOLLOW)
	elif event.is_action_pressed("view_aim"):
		_rmb_held = true
		_rmb_hold_time = 0.0
	elif event.is_action_released("view_aim"):
		_rmb_held = false
		_rmb_hold_time = 0.0
	elif event.is_action_pressed("view_freelook"):
		if _view == View.FOLLOW:
			_free_looking = true
	elif event.is_action_released("view_freelook"):
		_free_looking = false
		_return_timer = 0.0
	elif event is InputEventMouseMotion and _free_looking and _view == View.FOLLOW:
		_orbit_yaw -= event.relative.x * freelook_sensitivity
		_orbit_pitch = clamp(
			_orbit_pitch - event.relative.y * freelook_sensitivity,
			deg_to_rad(freelook_pitch_min_deg),
			deg_to_rad(freelook_pitch_max_deg)
		)


func consumes_mouse_motion() -> bool:
	"""True while the player is free-looking in follow view, so a unit controller can
	skip its own mouse-to-turret aiming and let the camera orbit instead."""
	return _configured and _view == View.FOLLOW and _free_looking


# === View switching ========================================================

func set_view(new_view: int) -> void:
	if not _configured:
		return
	if new_view == _view and _active_camera != null:
		return

	var from_cam: Camera3D = _active_camera
	if from_cam != null:
		from_cam.fov = _base_fov_for(_view)  # reset outgoing camera so re-entry is clean

	_view = new_view
	_rmb_hold_time = 0.0

	var to_cam: Camera3D = _camera_for(new_view)
	if new_view == View.FOLLOW:
		_update_follow_transform()  # position it before we snapshot it for the blend
	to_cam.fov = _base_fov_for(new_view)
	_active_camera = to_cam

	_transition_tween = blend_cameras(_owner_unit, from_cam, to_cam, transition_duration, _transition_tween)
	_publish_active_camera()


func get_first_person_camera() -> Camera3D:
	return _fp_camera


func get_active_camera() -> Camera3D:
	return _active_camera


# === Per-frame update ======================================================

func _process(delta: float) -> void:
	if not _configured:
		return

	_update_follow_transform()

	if _rmb_held:
		_rmb_hold_time += delta

	# Free-look auto-return: after the player releases MMB, ease the orbit back to rest.
	if _free_looking:
		_return_timer = 0.0
	elif _orbit_yaw != 0.0 or _orbit_pitch != 0.0:
		_return_timer += delta
		if _return_timer >= freelook_return_delay:
			var t: float = clamp(delta * freelook_return_speed, 0.0, 1.0)
			_orbit_yaw = lerp(_orbit_yaw, 0.0, t)
			_orbit_pitch = lerp(_orbit_pitch, 0.0, t)
			if absf(_orbit_yaw) < 0.0005 and absf(_orbit_pitch) < 0.0005:
				_orbit_yaw = 0.0
				_orbit_pitch = 0.0

	# RMB zoom on the active camera (uniform for first-person aim AND follow zoom).
	if _active_camera != null:
		var target_fov: float = _target_fov()
		_active_camera.fov = lerp(_active_camera.fov, target_fov, clamp(delta * zoom_lerp_speed, 0.0, 1.0))


func _update_follow_transform() -> void:
	if _follow_camera == null or _follow_target == null or not _follow_target.is_inside_tree():
		return

	var center: Vector3 = _follow_target.global_position
	var scale_f: float = _owner_unit.global_transform.basis.get_scale().x
	if scale_f <= 0.0001:
		scale_f = 1.0
	var dist: float = follow_distance * scale_f
	var height: float = follow_height * scale_f

	# Flattened forward gives a stable top-behind chase that ignores roll/pitch.
	var fwd: Vector3 = -_forward_node.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.001:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()

	# Behind the unit, rotated by the free-look yaw.
	var behind: Vector3 = Basis(Vector3.UP, _orbit_yaw) * (-fwd)
	var offset: Vector3 = behind * dist + Vector3.UP * height

	# Free-look vertical: pitch the offset around the camera's right axis.
	var right: Vector3 = behind.cross(Vector3.UP)
	if right.length() > 0.001:
		offset = offset.rotated(right.normalized(), _orbit_pitch)

	_follow_camera.global_position = center + offset
	if (center - _follow_camera.global_position).length() > 0.001:
		_follow_camera.look_at(center, Vector3.UP)


# === Helpers ===============================================================

func _camera_for(view: int) -> Camera3D:
	return _follow_camera if view == View.FOLLOW else _fp_camera


func _base_fov_for(view: int) -> float:
	return follow_fov if view == View.FOLLOW else first_person_fov


func _target_fov() -> float:
	var base: float = _base_fov_for(_view)
	if not _rmb_held:
		return base
	var aim: float = base * (1.0 - aim_zoom_fraction)
	var deepest: float = base * (1.0 - aim_zoom_max_fraction)
	var t: float = clamp(_rmb_hold_time / aim_deepen_time, 0.0, 1.0)
	return lerp(aim, deepest, t)


func _should_handle() -> bool:
	"""Only the active unit (or a standalone unit with no mode system) reacts to view input."""
	var mm: Node = _get_mode_manager()
	if mm == null:
		return true
	return mm.active_unit == _owner_unit or mm.active_fighter == _owner_unit


func _get_mode_manager() -> Node:
	var map: Node = get_tree().get_first_node_in_group("map") if get_tree() else null
	return map.get_node_or_null("ModeManager") if map else null


func _publish_active_camera() -> void:
	"""Keep ModeManager pointed at whatever camera is live, so Map's exit transition
	blends back from the correct camera even after the player changed views."""
	var mm: Node = _get_mode_manager()
	if mm == null:
		return
	if mm.active_unit == _owner_unit:
		mm.active_unit_camera = _active_camera
	elif mm.active_fighter == _owner_unit:
		mm.active_fighter_camera = _active_camera


# === Shared camera blend (used by this controller AND Map.gd) ===============

static func blend_cameras(host: Node, source_camera: Camera3D, target_camera: Camera3D, duration: float = 0.4, prev_tween: Tween = null) -> Tween:
	"""Smoothly blend from source_camera to target_camera by tweening a throwaway camera,
	then hand control to target_camera. The single source of truth for camera transitions."""
	if prev_tween != null and prev_tween.is_valid():
		prev_tween.kill()

	if target_camera == null:
		return null
	if source_camera == null or source_camera == target_camera or host == null:
		if target_camera != null:
			target_camera.current = true
		return null

	var temp := Camera3D.new()
	host.add_child(temp)
	temp.global_transform = source_camera.global_transform
	temp.fov = source_camera.fov
	temp.current = true

	var end_transform: Transform3D = target_camera.global_transform
	var end_fov: float = target_camera.fov

	var tw := host.create_tween()
	tw.set_parallel(true)
	tw.tween_property(temp, "global_transform", end_transform, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(temp, "fov", end_fov, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.chain().tween_callback(func() -> void:
		if is_instance_valid(target_camera):
			target_camera.current = true
		if is_instance_valid(temp):
			temp.queue_free()
	)
	return tw
