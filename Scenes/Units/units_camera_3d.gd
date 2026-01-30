extends Camera3D

@export var rotate_speed_deg := 45.0      # degrees per second per pixel delta
@export var return_delay_sec := 1.0       # wait after release
@export var return_duration_sec := 2   # time to blend back

var _is_rotating := false
var _rest_basis: Basis
var _return_tween: Tween

func _ready() -> void:
	_rest_basis = transform.basis

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed:
			_begin_rotate()
		else:
			_end_rotate()
	elif _is_rotating and event is InputEventMouseMotion:
		_apply_motion(event.relative)

func _begin_rotate() -> void:
	_is_rotating = true
	if _return_tween:
		_return_tween.kill()

func _end_rotate() -> void:
	_is_rotating = false
	if _return_tween:
		_return_tween.kill()
	_return_tween = create_tween()
	_return_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_return_tween.set_trans(Tween.TRANS_SINE)
	_return_tween.set_ease(Tween.EASE_IN_OUT)
	_return_tween.tween_interval(return_delay_sec)
	# Smoothly interpolate local basis back to the editor-set rest orientation
	var start_basis := transform.basis
	_return_tween.tween_method(
		func(v):
			transform.basis = start_basis.slerp(_rest_basis, v),
		0.0, 1.0, return_duration_sec
	)

func _apply_motion(rel: Vector2) -> void:
	var yaw := -rel.x * deg_to_rad(rotate_speed_deg) * get_process_delta_time()
	var pitch := -rel.y * deg_to_rad(rotate_speed_deg) * get_process_delta_time()
	# Rotate around camera’s own axes
	rotate_y(yaw)
	rotate_object_local(Vector3(1, 0, 0), pitch)
