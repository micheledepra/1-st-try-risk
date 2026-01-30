extends Node3D
class_name FighterNpcAI

# Lightweight NPC/autopilot for fighterww1_1_ph0. Keeps altitude, speed and gently circles.
@export var cruise_speed: float = 105.0
@export var min_altitude: float = 35.0
@export var cruise_altitude: float = 100.0
@export var altitude_jitter: float = 5.0
@export var turn_interval_range: Vector2 = Vector2(7.0, 13.0)
@export var direction_jitter_deg: float = 95.0
@export var use_velocity_targeting: bool = true

@onready var aero: AeroControlComponent = find_child("AeroControlComponent", true, false)
@onready var assist: FlightAssist = aero.flight_assist if aero else null
@onready var aero_body: AeroBody3D = aero.aero_body if aero else null

enum State { TAKEOFF, CLIMB, CRUISE }
var state: State = State.TAKEOFF

var desired_altitude: float = 0.0
var desired_direction: Vector3 = Vector3.FORWARD
var turn_timer: float = 0.0
var orbit_center: Vector3
var orbit_sign: float = 1.0

func _ready() -> void:
	# Seed for small heading variations
	randomize()
	orbit_center = global_transform.origin
	# Godot 4 does not support C-style ternary; pick sign with if/else
	if randf() < 0.5:
		orbit_sign = -1.0
	else:
		orbit_sign = 1.0
	desired_altitude = max(min_altitude, cruise_altitude)
	_configure_assist()
	_pick_new_direction()

func _physics_process(delta: float) -> void:
	if not aero or not aero_body:
		return
	
	turn_timer -= delta
	if turn_timer <= 0.0:
		_pick_new_direction()
	
	_update_state()
	
	if assist:
		_drive_with_assist()
	else:
		_drive_direct()

func _configure_assist() -> void:
	if not assist:
		return
	assist.enable_target_direction = true
	assist.use_velocity_vector_for_targetting = use_velocity_targeting
	assist.enable_speed_hold = true
	assist.enable_altitude_hold = true
	assist.enable_heading_hold = false
	assist.enable_inclination_hold = false
	assist.enable_bank_angle_assist = true
	assist.bank_angle_target = 0.0
	assist.speed_target = cruise_speed
	assist.altitude_target = desired_altitude

func _pick_new_direction() -> void:
	# Drift around the initial spawn point to avoid long straights
	var to_center = orbit_center - aero_body.global_transform.origin
	if to_center.length() < 1.0:
		to_center = Vector3.FORWARD
	var tangent = to_center.cross(Vector3.UP) * orbit_sign
	if tangent.length() < 0.1:
		tangent = Vector3(0, 0, -1)
	var yaw_offset = deg_to_rad(randf_range(-direction_jitter_deg, direction_jitter_deg))
	desired_direction = tangent.normalized().rotated(Vector3.UP, yaw_offset).normalized()
	desired_altitude = clamp(cruise_altitude + randf_range(-altitude_jitter, altitude_jitter), min_altitude, cruise_altitude + altitude_jitter)
	turn_timer = randf_range(turn_interval_range.x, turn_interval_range.y)

func _update_state() -> void:
	var altitude_now = aero_body.global_transform.origin.y
	var airspeed = aero_body.air_speed if aero_body else 0.0
	match state:
		State.TAKEOFF:
			if altitude_now > min_altitude * 0.6 or airspeed > cruise_speed * 0.65:
				state = State.CLIMB
		State.CLIMB:
			if altitude_now > min_altitude + 5.0:
				state = State.CRUISE
		State.CRUISE:
			if altitude_now < min_altitude * 0.8:
				state = State.CLIMB

func _drive_with_assist() -> void:
	assist.speed_target = max(cruise_speed, cruise_speed * 0.9)
	assist.altitude_target = max(desired_altitude, min_altitude + 3.0)
	assist.direction_target = desired_direction
	assist.enable_target_direction = true
	assist.use_velocity_vector_for_targetting = use_velocity_targeting
	assist.enable_speed_hold = true
	assist.enable_altitude_hold = true
	assist.enable_bank_angle_assist = true
	assist.bank_angle_target = 0.0
	
	# Keep throttle high until we are safely off the ground
	var throttle_cmd = 1.0 if state == State.TAKEOFF else 0.75
	aero.set_control_input("throttle", throttle_cmd)
	
	# Nudge nose up a bit on takeoff to help rotation
	if state == State.TAKEOFF:
		aero.set_control_input("pitch", 0.15)

func _drive_direct() -> void:
	var basis = aero_body.global_transform.basis
	var forward = basis.z.normalized()
	var right = basis.x.normalized()
	var up = basis.y.normalized()
	
	var axis = forward.cross(desired_direction).clamped(1.0)
	var altitude_error = clamp(desired_altitude - aero_body.global_transform.origin.y, -30.0, 30.0)
	var pitch_term = -axis.x * 2.0 + altitude_error * 0.05
	
	var throttle_cmd = 1.0 if state == State.TAKEOFF else 0.75
	aero.set_control_input("throttle", throttle_cmd)
	aero.set_control_input("yaw", clamp(axis.y * 2.0, -1.0, 1.0))
	aero.set_control_input("roll", clamp(-axis.z * 2.0, -1.0, 1.0))
	aero.set_control_input("pitch", clamp(pitch_term, -0.6, 0.6))

	# Bias nose up if we get too low
	if aero_body.global_transform.origin.y < min_altitude * 0.6:
		aero.set_control_input("pitch", 0.35)
