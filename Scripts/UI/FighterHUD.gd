extends CanvasLayer
class_name FighterHUD

@onready var root: Control = $Root
@onready var throttle_bar: ProgressBar = $Root/ThrottlePanel/VBoxContainer/Progress
@onready var throttle_label: Label = $Root/ThrottlePanel/VBoxContainer/Percent
@onready var gyro: GyroWidget = $Root/GyroPanel/Margin/Gyro

var bound_controller: Object = null

func _ready() -> void:
	visible = false
	if not throttle_bar or not throttle_label or not gyro:
		push_warning("FighterHUD: Missing HUD nodes; verify scene paths")
		return
	_update_throttle(0.0)
	_ensure_safe_scale()

func bind_to_controller(controller: Node) -> void:
	if bound_controller and bound_controller.is_connected("hud_state", Callable(self, "_on_hud_state")):
		bound_controller.disconnect("hud_state", Callable(self, "_on_hud_state"))
	bound_controller = null
	visible = false

	if controller and controller.has_signal("hud_state"):
		controller.connect("hud_state", Callable(self, "_on_hud_state"), CONNECT_DEFERRED)
		bound_controller = controller
		visible = true
	elif controller:
		push_warning("FighterHUD: Controller missing hud_state signal")

func _on_hud_state(throttle: float, pitch_deg: float, roll_deg: float, yaw_deg: float) -> void:
	_update_throttle(throttle)
	gyro.set_attitude(pitch_deg, roll_deg, yaw_deg)

func _update_throttle(value: float) -> void:
	var pct: float = clamp(value, 0.0, 1.0) * 100.0
	throttle_bar.value = pct
	throttle_label.text = "%d%%" % int(round(pct))

func _ensure_safe_scale() -> void:
	# Keep UI small on tiny windows
	var viewport := get_viewport()
	if viewport:
		var size: Vector2 = viewport.get_visible_rect().size
		var scale: float = clamp(size.y / 720.0, 0.75, 1.25)
		root.scale = Vector2(scale, scale)
