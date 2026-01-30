extends Node3D
class_name UnitTestManager

## Unit Testing Manager
## Inspector-only selection. Each unit runs standalone with its own camera/control system.
## Set NONE to use free camera mode on MainCam3D.

enum UnitType {
	NONE,
	T34,
	PANTHER,
	AA,
	FIGHTER,
	FWW2
}

@export var selected_unit_type: UnitType = UnitType.NONE

@onready var t34: Node3D = $t_34
@onready var panther: Node3D = $Sda
@onready var aa: Node3D = $Aa
@onready var fighter: Node3D = $fighterww1_1_ph0
@onready var fww2: Node3D = $fww2_Mcc
@onready var main_camera: Camera3D = $MainCam3D

@export var npc_fighter_scene: PackedScene = preload("res://Scenes/Units/Import/Fighter/Fighterww_1_ph0_NPC.tscn")
@export var npc_fighter_count: int = 0
@export var npc_spawn_radius: float = 50.0
@export var npc_spawn_height_offset: float = 5.0
@export var fighter_hud_scene: PackedScene = preload("res://Scenes/UI/FighterHUD.tscn")

var npc_fighters: Array[Node3D] = []
var selected_unit: Node3D = null
var fighter_hud: FighterHUD = null

func _ready() -> void:
	_deactivate_all_units()
	_spawn_npc_fighters()

	match selected_unit_type:
		UnitType.NONE:
			_activate_camera_mode()
		UnitType.T34:
			_activate_unit(t34, "T34 Tank")
		UnitType.PANTHER:
			_activate_unit(panther, "Panther Tank")
		UnitType.AA:
			_activate_unit(aa, "AA Unit")
		UnitType.FIGHTER:
			_activate_unit(fighter, "Fighter WW1")
		UnitType.FWW2:
			_activate_unit(fww2, "Fighter WW2")

func _activate_camera_mode() -> void:
	_deactivate_all_units()
	selected_unit = null
	_hide_fighter_hud()

	if main_camera:
		main_camera.current = true
	else:
		push_warning("UnitTestManager: MainCam3D not found for camera mode")

	print("=== Unit Test Environment ===")
	print("Mode: FREE CAMERA")
	print("Camera controls active on MainCam3D")
	if npc_fighters.size() > 0:
		print("NPC fighters spawned: %d (AI-driven)" % npc_fighters.size())
	print("=============================")

func _activate_unit(unit: Node3D, unit_name: String) -> void:
	if not unit:
		push_error("UnitTestManager: Unit '%s' not found" % unit_name)
		return

	_deactivate_all_units()
	selected_unit = unit

	if "standalone_mode" in unit:
		unit.standalone_mode = true

	_enable_unit_input(unit)

	var has_cam = _ensure_unit_camera(unit)
	if not has_cam:
		push_warning("UnitTestManager: No camera found for %s" % unit_name)

	if unit == aa:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if unit == fighter or unit == fww2:
		_bind_fighter_hud(unit)
	else:
		_hide_fighter_hud()

	if main_camera:
		main_camera.current = false

	print("=== Unit Test Environment ===")
	print("Unit: %s (STANDALONE MODE)" % unit_name)
	print("Unit camera and control systems active")
	if npc_fighters.size() > 0:
		print("NPC fighters spawned: %d (AI-driven)" % npc_fighters.size())
	print("=============================")

func _ensure_unit_camera(unit: Node) -> bool:
	if unit is Camera3D:
		(unit as Camera3D).current = true
		return true

	for child in unit.get_children():
		if child is Camera3D:
			(child as Camera3D).current = true
			return true
		if _ensure_unit_camera(child):
			return true

	return false

func _deactivate_all_units() -> void:
	_disable_unit_input(t34)
	_disable_unit_input(panther)
	_disable_unit_input(aa)
	_disable_unit_input(fighter)
	_disable_unit_input(fww2)
	selected_unit = null
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_hide_fighter_hud()

func _disable_unit_input(unit: Node) -> void:
	if not unit:
		return
	unit.set_process_input(false)
	unit.set_process_unhandled_input(false)

	if "standalone_mode" in unit:
		unit.standalone_mode = false

	for child in unit.get_children():
		_disable_unit_input(child)

func _enable_unit_input(unit: Node) -> void:
	if not unit:
		return
	unit.set_process_input(true)
	unit.set_process_unhandled_input(true)

	for child in unit.get_children():
		_enable_unit_input(child)

func _spawn_npc_fighters() -> void:
	if not npc_fighter_scene or npc_fighter_count <= 0:
		return

	var center: Vector3 = main_camera.global_transform.origin if main_camera else global_transform.origin

	for i in range(npc_fighter_count):
		var npc_instance = npc_fighter_scene.instantiate() as Node3D
		if not npc_instance:
			continue
		add_child(npc_instance)

		var angle = randf_range(0.0, TAU)
		var radius = sqrt(randf()) * npc_spawn_radius
		var offset = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)

		var spawn_pos = center + offset
		spawn_pos.y = max(0.0, center.y + npc_spawn_height_offset)

		npc_instance.global_transform = Transform3D(npc_instance.global_transform.basis, spawn_pos)
		npc_fighters.append(npc_instance)

func _bind_fighter_hud(unit: Node) -> void:
	if not fighter_hud_scene:
		return

	if not fighter_hud:
		fighter_hud = fighter_hud_scene.instantiate() as FighterHUD
		add_child(fighter_hud)

	fighter_hud.bind_to_controller(unit)

func _hide_fighter_hud() -> void:
	if fighter_hud:
		fighter_hud.bind_to_controller(null)
		fighter_hud.visible = false
