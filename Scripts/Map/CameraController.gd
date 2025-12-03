extends Camera3D

## Camera movement controller for strategic map view
## Controls: 
## - WASD for horizontal movement, QE for vertical movement, Shift for sprint
## - Middle mouse button + drag to rotate camera
## - R key to reset camera to initial position and rotation

@export var move_speed: float = 15.0
@export var sprint_multiplier: float = 2.5
@export var smoothing: float = 12.0
@export var min_bounds: Vector3 = Vector3(-50, 5, -50)
@export var max_bounds: Vector3 = Vector3(50, 50, 50)

## Mouse control settings
@export var mouse_rotate_speed: float = 0.005
@export var min_rotation_x: float = -89.0  # Prevent flipping
@export var max_rotation_x: float = 0.0    # Top-down view limit

var velocity: Vector3 = Vector3.ZERO
var is_middle_click_held: bool = false
var last_mouse_position: Vector2 = Vector2.ZERO
var camera_rotation: Vector3 = Vector3.ZERO  # Track rotation separately
var initial_position: Vector3 = Vector3.ZERO  # Store startup position
var initial_rotation: Vector3 = Vector3.ZERO  # Store startup rotation

func _ready() -> void:
	# Store initial camera transform
	initial_position = global_position
	initial_rotation = rotation_degrees
	# Initialize rotation from current transform
	camera_rotation = rotation_degrees

func _input(event: InputEvent) -> void:
	# Middle click - Rotate camera
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			is_middle_click_held = event.pressed
			if event.pressed:
				last_mouse_position = event.position
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# Handle mouse motion
	if event is InputEventMouseMotion:
		if is_middle_click_held:
			handle_mouse_rotate(event.relative)
	
	# R key - Reset camera to initial position and rotation
	if event is InputEventKey:
		if event.keycode == KEY_R and event.pressed and not event.echo:
			reset_camera()

func _process(delta: float) -> void:
	handle_movement(delta)

func handle_movement(delta: float) -> void:
	var input_dir = Vector3.ZERO
	var speed = move_speed
	
	# Sprint with Shift
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= sprint_multiplier
	
	# Horizontal movement (WASD)
	if Input.is_key_pressed(KEY_W):
		input_dir.z -= 1
	if Input.is_key_pressed(KEY_S):
		input_dir.z += 1
	if Input.is_key_pressed(KEY_A):
		input_dir.x -= 1
	if Input.is_key_pressed(KEY_D):
		input_dir.x += 1
	
	# Vertical movement (QE)
	if Input.is_key_pressed(KEY_Q):
		input_dir.y -= 1
	if Input.is_key_pressed(KEY_E):
		input_dir.y += 1
	
	# Normalize to prevent faster diagonal movement
	input_dir = input_dir.normalized()
	
	# Smooth movement
	velocity = velocity.lerp(input_dir * speed, smoothing * delta)
	
	# Apply movement with bounds
	global_position += velocity * delta
	global_position = global_position.clamp(min_bounds, max_bounds)

func handle_mouse_rotate(relative: Vector2) -> void:
	# Rotate camera based on mouse movement
	camera_rotation.y -= relative.x * mouse_rotate_speed * 10.0
	camera_rotation.x -= relative.y * mouse_rotate_speed * 10.0
	
	# Clamp vertical rotation to prevent flipping
	camera_rotation.x = clamp(camera_rotation.x, min_rotation_x, max_rotation_x)
	
	# Apply rotation
	rotation_degrees = camera_rotation

func reset_camera() -> void:
	# Reset camera to initial position and rotation
	global_position = initial_position
	camera_rotation = initial_rotation
	rotation_degrees = initial_rotation
	velocity = Vector3.ZERO
