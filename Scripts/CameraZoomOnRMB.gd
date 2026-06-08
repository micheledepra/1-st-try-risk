extends Camera3D

## Recreated stub (was referenced by fighter scenes but missing from the repo).
## Narrows the field of view (zooms in) while the right mouse button is held and
## eases back to the camera's default FOV on release.

## FOV (degrees) while the right mouse button is held.
@export var zoomed_fov: float = 25.0
## How quickly the FOV transitions toward its target.
@export var zoom_speed: float = 8.0

var _default_fov: float = 75.0


func _ready() -> void:
	_default_fov = fov


func _process(delta: float) -> void:
	var target := zoomed_fov if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) else _default_fov
	fov = lerpf(fov, target, clampf(zoom_speed * delta, 0.0, 1.0))
