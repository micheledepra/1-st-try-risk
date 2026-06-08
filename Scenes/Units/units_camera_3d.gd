extends Camera3D

## Recreated stub (was referenced by fighter scenes but missing from the repo).
## Free-look camera: pans toward mouse movement up to a capped angle, then eases
## back to its resting orientation after the mouse goes idle. Used for the
## cockpit / chase cameras on the cessna172 fighter.

## Maximum look offset from the resting orientation, in degrees (per axis).
@export var rotate_speed_deg: float = 25.0
## Idle time (seconds) with no mouse movement before the view recenters.
@export var return_delay_sec: float = 0.5

const MOUSE_SENSITIVITY: float = 0.002
const RETURN_LERP_SPEED: float = 3.0

var _rest_basis: Basis
var _yaw: float = 0.0
var _pitch: float = 0.0
var _idle_time: float = 0.0


func _ready() -> void:
	_rest_basis = transform.basis


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var limit := deg_to_rad(rotate_speed_deg)
		_yaw = clampf(_yaw - event.relative.x * MOUSE_SENSITIVITY, -limit, limit)
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENSITIVITY, -limit, limit)
		_idle_time = 0.0


func _process(delta: float) -> void:
	_idle_time += delta
	if _idle_time >= return_delay_sec:
		_yaw = lerpf(_yaw, 0.0, clampf(RETURN_LERP_SPEED * delta, 0.0, 1.0))
		_pitch = lerpf(_pitch, 0.0, clampf(RETURN_LERP_SPEED * delta, 0.0, 1.0))
	transform.basis = _rest_basis * Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
