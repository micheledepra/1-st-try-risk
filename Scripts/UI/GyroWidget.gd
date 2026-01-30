extends Control
class_name GyroWidget

var pitch_deg: float = 0.0
var roll_deg: float = 0.0
var yaw_deg: float = 0.0

@export var outline_color: Color = Color(1, 1, 1, 0.85)
@export var horizon_color: Color = Color(0.2, 0.7, 1.0, 0.9)
@export var compass_color: Color = Color(0.85, 0.85, 0.85, 0.85)
@export var background_color: Color = Color(0, 0, 0, 0.35)

func set_attitude(pitch: float, roll: float, yaw: float) -> void:
	pitch_deg = clamp(pitch, -90.0, 90.0)
	roll_deg = wrapf(roll, -180.0, 180.0)
	yaw_deg = fposmod(yaw, 360.0)
	queue_redraw()

func _draw() -> void:
	var size: Vector2 = get_size()
	var center: Vector2 = size * 0.5
	var radius: float = min(size.x, size.y) * 0.42

	_draw_ring(center, radius)
	_draw_horizon(center, radius)
	_draw_reference_marks(center, radius)
	_draw_compass_band(size)

func _draw_ring(center: Vector2, radius: float) -> void:
	draw_arc(center, radius, 0.0, TAU, 96, outline_color, 2.0)
	draw_arc(center, radius * 0.9, 0.0, TAU, 96, Color(outline_color.r, outline_color.g, outline_color.b, outline_color.a * 0.35), 1.0)

func _draw_horizon(center: Vector2, radius: float) -> void:
	var roll_rad: float = deg_to_rad(roll_deg)
	var up: Vector2 = Vector2(0, -1).rotated(roll_rad)
	var right: Vector2 = Vector2(1, 0).rotated(roll_rad)
	var pitch_offset: float = clamp(pitch_deg / 45.0, -1.0, 1.0) * radius * 0.55

	var horizon_a: Vector2 = center + (right * -radius * 0.75) + (up * pitch_offset)
	var horizon_b: Vector2 = center + (right * radius * 0.75) + (up * pitch_offset)
	draw_line(horizon_a, horizon_b, horizon_color, 3.0)

	# Nose indicator
	draw_line(center + up * radius * 0.18, center - up * radius * 0.18, outline_color, 2.0)
	draw_line(center + right * radius * 0.08, center - right * radius * 0.08, outline_color, 2.0)
	draw_circle(center, 3.0, outline_color)

func _draw_reference_marks(center: Vector2, radius: float) -> void:
	var notch_len: float = radius * 0.06
	for deg_mark in [-90, -45, 0, 45, 90]:
		var r: float = deg_to_rad(deg_mark) + deg_to_rad(roll_deg)
		var dir: Vector2 = Vector2(0, -1).rotated(r)
		draw_line(center + dir * (radius - notch_len), center + dir * radius, outline_color, 1.5)

func _draw_compass_band(size: Vector2) -> void:
	var band_height: float = size.y * 0.26
	var y_start: float = size.y - band_height
	var rect := Rect2(Vector2(0, y_start), Vector2(size.x, band_height))
	draw_rect(rect, background_color)

	var mid_x: float = size.x * 0.5
	var spacing: float = size.x * 0.14  # distance between 15° ticks
	var font: Font = get_theme_default_font()
	var font_size: int = get_theme_default_font_size()
	var base_heading: float = yaw_deg

	for i in range(-3, 4):
		var angle: float = fposmod(base_heading + i * 15.0, 360.0)
		var x: float = mid_x + spacing * i
		var is_major: bool = int(angle) % 45 == 0
		var tick_h: float = band_height * (0.45 if is_major else 0.32)
		draw_line(Vector2(x, y_start + band_height), Vector2(x, y_start + band_height - tick_h), compass_color, 2.0 if is_major else 1.0)

		if font and is_major:
			var heading_text: String = _format_heading(angle)
			var text_size: Vector2 = font.get_string_size(heading_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var text_pos: Vector2 = Vector2(x - text_size.x * 0.5, y_start + band_height - tick_h - 4.0)
			draw_string(font, text_pos, heading_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, compass_color)

	# Center caret for current heading
	draw_line(Vector2(mid_x, y_start), Vector2(mid_x, y_start + band_height * 0.6), outline_color, 2.0)
	draw_triangle(Vector2(mid_x, y_start), Vector2(mid_x - 6.0, y_start + 8.0), Vector2(mid_x + 6.0, y_start + 8.0), outline_color)

func _format_heading(angle: float) -> String:
	var rounded: int = int(round(angle)) % 360
	match rounded:
		0, 360:
			return "N"
		90:
			return "E"
		180:
			return "S"
		270:
			return "W"
		_:
			return str(rounded)

func draw_triangle(a: Vector2, b: Vector2, c: Vector2, color: Color) -> void:
	draw_polygon(PackedVector2Array([a, b, c]), PackedColorArray([color, color, color]))
