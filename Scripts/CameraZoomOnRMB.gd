extends Camera3D

@export var zoom_fov := 35.0
@export var zoom_speed := 8.0
@export var return_speed := 6.0

var _orig_fov: float
var _zooming := false

func _ready() -> void:
    _orig_fov = fov

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
        _zooming = event.pressed

func _process(delta: float) -> void:
    var target := zoom_fov if _zooming else _orig_fov
    var t := 1.0 - pow(0.01, delta * (zoom_speed if _zooming else return_speed))
    fov = lerp(fov, target, clamp(t, 0.0, 1.0))
