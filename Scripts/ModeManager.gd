extends Node

## ModeManager
## Manages game mode switching between Strategic and Tactical modes
## - Strategic: Territory management, camera above map, mouse free
## - Tactical: Direct unit control, unit camera, mouse captured

enum GameMode {
	STRATEGIC,  # Territory management mode (default)
	TACTICAL,   # Direct unit control mode
	FIGHTER     # Fighter plane control mode
}

signal mode_changed(new_mode: GameMode)

var current_mode: GameMode = GameMode.STRATEGIC
var active_unit: Node3D = null
var active_unit_camera: Camera3D = null
var stored_territory: String = ""  # Territory where controllable unit was spawned
var active_fighter: Node3D = null  # Active fighter plane
var active_fighter_camera: Camera3D = null  # Fighter's camera

func enter_tactical_mode(unit: Node3D, camera: Camera3D, territory_name: String):
	"""Enter tactical mode with the specified unit and camera"""
	if current_mode == GameMode.TACTICAL:
		push_warning("ModeManager: Already in tactical mode")
		return
	
	active_unit = unit
	active_unit_camera = camera
	stored_territory = territory_name
	current_mode = GameMode.TACTICAL
	
	# Hide territory labels when entering tactical mode
	_set_territory_labels_visible(false)
	
	mode_changed.emit(GameMode.TACTICAL)
	print("ModeManager: Entered TACTICAL mode on territory %s" % territory_name)

func exit_tactical_mode():
	"""Exit tactical mode and return to strategic mode"""
	if current_mode == GameMode.STRATEGIC:
		push_warning("ModeManager: Already in strategic mode")
		return
	
	# Clear references
	active_unit = null
	active_unit_camera = null
	var previous_territory = stored_territory
	stored_territory = ""
	
	current_mode = GameMode.STRATEGIC
	
	# Show territory labels when exiting tactical mode
	_set_territory_labels_visible(true)
	
	mode_changed.emit(GameMode.STRATEGIC)
	print("ModeManager: Exited TACTICAL mode, returned to STRATEGIC (territory: %s)" % previous_territory)

func is_tactical_mode() -> bool:
	return current_mode == GameMode.TACTICAL

func is_strategic_mode() -> bool:
	return current_mode == GameMode.STRATEGIC

func get_active_unit() -> Node3D:
	return active_unit

func get_stored_territory() -> String:
	return stored_territory

func enter_fighter_mode(fighter: Node3D, camera: Camera3D):
	"""Enter fighter mode with the specified fighter and camera"""
	if current_mode == GameMode.FIGHTER:
		push_warning("ModeManager: Already in fighter mode")
		return
	
	active_fighter = fighter
	active_fighter_camera = camera
	current_mode = GameMode.FIGHTER
	
	# Hide territory labels when entering fighter mode
	_set_territory_labels_visible(false)
	
	mode_changed.emit(GameMode.FIGHTER)
	print("ModeManager: Entered FIGHTER mode")

func exit_fighter_mode():
	"""Exit fighter mode and return to strategic mode"""
	if current_mode != GameMode.FIGHTER:
		push_warning("ModeManager: Not in fighter mode")
		return
	
	# Clear references
	active_fighter = null
	active_fighter_camera = null
	
	current_mode = GameMode.STRATEGIC
	
	# Show territory labels when exiting fighter mode
	_set_territory_labels_visible(true)
	
	mode_changed.emit(GameMode.STRATEGIC)
	print("ModeManager: Exited FIGHTER mode, returned to STRATEGIC")

func is_fighter_mode() -> bool:
	return current_mode == GameMode.FIGHTER

func get_active_fighter() -> Node3D:
	return active_fighter

func _set_territory_labels_visible(visible: bool):
	"""Helper to show/hide territory labels via TerritoryColorManager"""
	var map = get_tree().get_first_node_in_group("map")
	if map:
		var color_manager = map.get_node_or_null("TerritoryColorManager")
		if color_manager and color_manager.has_method("set_labels_visible"):
			color_manager.set_labels_visible(visible)
