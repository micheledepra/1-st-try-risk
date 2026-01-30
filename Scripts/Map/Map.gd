extends Node3D

var input_manager: Node
var color_manager: Node
var unit_manager: Node
var game_manager: Node
var reinforcement_phase: Node
var attack_phase: Node
var fortify_phase: Node
var game_ui: Control
var mode_manager: Node
var map_camera: Camera3D
var initial_camera_transform: Transform3D
var initial_camera_fov: float
var awaiting_territory_selection: bool = false
var camera_transition_tween: Tween
var fighter_hud_scene: PackedScene = preload("res://Scenes/UI/FighterHUD.tscn")
var fighter_hud: FighterHUD = null
@export_enum("WW1", "WW2") var fighter_plane_type: String = "WW1"
const FIGHTER_WW1_SCENE := preload("res://Scenes/Units/Import/Fighter/Fighterww_1_ph0.tscn")
const FIGHTER_WW2_SCENE := preload("res://Scenes/Units/Import/Fighter/FighterWW2/fww2_Mcc.tscn")
const FIGHTER_WW1_CAMERA_PATH := "cessna172/Camera3D5"
const FIGHTER_WW2_CAMERA_PATH := "cessna172/Camera3D5"

# Interaction state
var first_selected_territory: String = ""
var interaction_mode: String = ""  # "place", "attack", "fortify"

func _ready():
	# Add to map group for easy reference by tank controllers
	add_to_group("map")
	
	# Wait for children to be ready first
	await get_tree().process_frame
	
	input_manager = get_node_or_null("TerritoryInputManager")
	color_manager = get_node_or_null("TerritoryColorManager")
	unit_manager = get_node_or_null("TerritoryUnitManager")
	game_manager = get_node("/root/GameManager")
	
	# Get UI reference from CanvasLayer
	var canvas_layer = get_node_or_null("CanvasLayer")
	if canvas_layer:
		game_ui = canvas_layer.get_node_or_null("GameUI_01")
		if not game_ui:
			push_warning("Map: GameUI_01 not found under CanvasLayer")
	else:
		push_warning("Map: CanvasLayer not found in scene tree")
	
	# Create phase controllers
	reinforcement_phase = Node.new()
	reinforcement_phase.name = "ReinforcementPhase"
	reinforcement_phase.set_script(load("res://Scripts/ReinforcementPhase.gd"))
	add_child(reinforcement_phase)
	
	attack_phase = Node.new()
	attack_phase.name = "AttackPhase"
	attack_phase.set_script(load("res://Scripts/AttackPhase.gd"))
	add_child(attack_phase)
	attack_phase.map_ref = self  # Set reference for UI updates
	
	fortify_phase = Node.new()
	fortify_phase.name = "FortifyPhase"
	fortify_phase.set_script(load("res://Scripts/FortifyPhase.gd"))
	add_child(fortify_phase)
	fortify_phase.map_ref = self  # Set reference for UI updates
	
	if input_manager == null:
		push_error("Map: TerritoryInputManager not found - input will not work!")
	else:
		# Connect to territory signals from input manager (single source of truth)
		if not input_manager.territory_clicked.is_connected(_on_territory_clicked):
			input_manager.territory_clicked.connect(_on_territory_clicked)
			print("Map: Connected to TerritoryInputManager.territory_clicked")
		
		if not input_manager.territory_right_clicked.is_connected(_on_territory_right_clicked):
			input_manager.territory_right_clicked.connect(_on_territory_right_clicked)
			print("Map: Connected to TerritoryInputManager.territory_right_clicked")
	
	
	if color_manager == null:
		push_warning("Map: TerritoryColorManager not found - visual state disabled")
	
	if unit_manager == null:
		push_warning("Map: TerritoryUnitManager not found - unit visualization disabled")
	
	# Create Mode Manager
	mode_manager = Node.new()
	mode_manager.name = "ModeManager"
	mode_manager.set_script(load("res://Scripts/ModeManager.gd"))
	add_child(mode_manager)
	
	# Get map camera reference
	map_camera = get_node_or_null("Camera3D")
	if not map_camera:
		push_error("Map: Camera3D not found!")
	else:
		# Store initial camera state to restore later
		initial_camera_transform = map_camera.global_transform
		initial_camera_fov = map_camera.fov
		print("Map: Stored initial camera state (transform and FOV)")
	
	print("Map initialized with continent-based structure and game systems")
	
	# Check if game is already set up from menu system
	if game_manager and not game_manager.players.is_empty():
		print("Map: Game already initialized with %d players" % game_manager.players.size())
		# Update visual state for existing territories
		update_territory_visuals()
	else:
		# Fallback: Wait a bit then start the game with default settings
		await get_tree().create_timer(1.0).timeout
		start_game()

func update_territory_visuals():
	# Update the visual representation of all territories based on current game state
	if not game_manager or not color_manager:
		return
	
	for territory_name in game_manager.territory_armies.keys():
		var owner = game_manager.get_territory_owner(territory_name)
		if owner:
			color_manager.set_territory_owner(territory_name, owner.id)

func set_territory_owner(territory_name: String, player_id: int):
	if color_manager:
		color_manager.set_territory_owner(territory_name, player_id)

func get_territory_owner(territory_name: String) -> int:
	if color_manager:
		return color_manager.territory_owners.get(territory_name, 0)
	return 0

func set_continent_owner(continent_name: String, player_id: int):
	if color_manager:
		color_manager.set_continent_owner(continent_name, player_id)

func get_continent_owner(continent_name: String) -> int:
	if color_manager:
		return color_manager.get_continent_owner(continent_name)
	return -1

func get_territories_in_continent(continent_name: String) -> Array:
	if color_manager:
		return color_manager.get_territories_in_continent(continent_name)
	return []

func get_all_continents() -> Array:
	if color_manager:
		return color_manager.get_all_continents()
	return []

func reset_all_territories():
	if color_manager:
		color_manager.reset_all_territories()

func start_game():
	if game_manager:
		# Start a 3-player game by default (can be made configurable)
		game_manager.start_new_game(3)
		print("Game started with 3 players")

func _on_territory_clicked(territory_name: String, ctrl_pressed: bool):
	if not game_manager:
		return
	
	# Handle territory selection for tactical mode
	if awaiting_territory_selection:
		enter_tactical_mode_with_territory(territory_name)
		return
	
	var current_phase = game_manager.current_phase
	
	match current_phase:
		game_manager.GamePhase.SETUP, game_manager.GamePhase.REINFORCEMENT:
			# Left-click ADDS armies (1 or 5 with Ctrl) - primary action
			handle_reinforcement_add(territory_name, ctrl_pressed)
			
		game_manager.GamePhase.ATTACK:
			# Left-click selects territory for attack
			handle_attack_click(territory_name)
			
		game_manager.GamePhase.FORTIFY:
			# Left-click selects territory for fortify
			handle_fortify_click(territory_name)

func _on_territory_right_clicked(territory_name: String, ctrl_pressed: bool):
	if not game_manager:
		return
	
	var current_phase = game_manager.current_phase
	
	match current_phase:
		game_manager.GamePhase.SETUP, game_manager.GamePhase.REINFORCEMENT:
			# Right-click REMOVES armies (1 or 5 with Ctrl)
			handle_reinforcement_remove(territory_name, ctrl_pressed)
			
		game_manager.GamePhase.ATTACK:
			# Right-click cancels selection
			handle_right_click_cancel("attack")
			
		game_manager.GamePhase.FORTIFY:
			# Right-click cancels selection
			handle_right_click_cancel("fortify")

func handle_reinforcement_add(territory_name: String, ctrl_pressed: bool):
	var count = 5 if ctrl_pressed else 1
	if reinforcement_phase.place_army(territory_name, count):
		print("Added %d army(s) to %s" % [count, territory_name])
	else:
		print("Cannot add armies to %s" % territory_name)

func handle_reinforcement_remove(territory_name: String, ctrl_pressed: bool):
	var count = 5 if ctrl_pressed else 1
	if reinforcement_phase.remove_army(territory_name, count):
		print("Removed %d army(s) from %s" % [count, territory_name])
	else:
		print("Cannot remove armies from %s" % territory_name)

func handle_attack_click(territory_name: String):
	# Always use UI-based attack resolution
	# AttackPhase shows RiskCombatUI (standard) or AttackResolutionUI (developer mode)
	attack_phase.handle_territory_clicked(territory_name)

func handle_fortify_click(territory_name: String):
	if first_selected_territory == "":
		# Select source territory
		var current_player = game_manager.get_current_player()
		if current_player.territories_owned.has(territory_name):
			if game_manager.get_territory_armies(territory_name) >= 2:
				first_selected_territory = territory_name
				if game_ui:
					game_ui.set_instruction_text("✓ Selected %s. Click connected territory to move armies" % territory_name)
				print("Selected %s to fortify from" % territory_name)
			else:
				if game_ui:
					game_ui.set_instruction_text("❌ Territory needs at least 2 armies to fortify")
				print("Territory needs at least 2 armies to fortify")
		else:
			if game_ui:
				game_ui.set_instruction_text("❌ You don't own %s" % territory_name)
			print("You don't own %s" % territory_name)
	else:
		# Show transfer UI to select army count
		fortify_phase.handle_fortify_transfer(first_selected_territory, territory_name)
		first_selected_territory = ""

func handle_right_click_cancel(phase: String):
	"""Cancel territory selection in attack or fortify phase"""
	if phase == "attack":
		if game_manager.developer_mode:
			# Reset attack phase selection
			attack_phase.reset_selection()
		else:
			# Reset Map selection
			if first_selected_territory != "":
				first_selected_territory = ""
				if game_ui:
					game_ui.set_instruction_text("❌ Selection cancelled. Click your territory to attack")
				print("Attack selection cancelled")
	elif phase == "fortify":
		# Reset fortify selection
		if first_selected_territory != "":
			first_selected_territory = ""
			if game_ui:
				game_ui.set_instruction_text("❌ Selection cancelled. Click your territory to fortify")
			print("Fortify selection cancelled")

func _input(event):
	# Handle Ctrl+U to toggle unit control mode
	if event.is_action_pressed("toggle_unit_control"):
		toggle_unit_control_mode()
		get_viewport().set_input_as_handled()
	
	# Handle Ctrl+P to toggle fighter mode
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_P and event.ctrl_pressed:
			toggle_fighter_mode()
			get_viewport().set_input_as_handled()
	
	# Handle ESC to cancel territory selection
	if event.is_action_pressed("ui_cancel") and awaiting_territory_selection:
		cancel_territory_selection()
		get_viewport().set_input_as_handled()

func toggle_unit_control_mode():
	"""Toggle between Strategic and Tactical modes"""
	if not game_manager or not mode_manager or not unit_manager:
		return
	
	if mode_manager.is_strategic_mode():
		# Entering tactical mode - prompt for territory selection
		var current_player = game_manager.get_current_player()
		if not current_player:
			return
		
		awaiting_territory_selection = true
		if game_ui:
			game_ui.show_territory_selection_prompt()
		print("Map: Awaiting territory selection for unit control")
	else:
		# Exiting tactical mode - return to strategic
		exit_tactical_mode()

func cancel_territory_selection():
	"""Cancel the territory selection process"""
	if awaiting_territory_selection:
		awaiting_territory_selection = false
		if game_ui:
			game_ui.hide_territory_selection_prompt()
			game_ui._update_ui()  # Restore normal UI
		print("Map: Territory selection cancelled")

func enter_tactical_mode_with_territory(territory_name: String):
	"""Spawn controllable unit on selected territory and enter tactical mode"""
	if not awaiting_territory_selection:
		return
	
	var current_player = game_manager.get_current_player()
	if not current_player:
		return
	
	# Validate player owns the territory
	if not current_player.territories_owned.has(territory_name):
		if game_ui:
			game_ui.set_instruction_text("❌ You don't own %s. Select your territory." % territory_name)
		return
	
	# Spawn controllable unit
	var unit_data = unit_manager.spawn_controllable_unit(territory_name, current_player)
	if not unit_data:
		if game_ui:
			game_ui.set_instruction_text("❌ Failed to spawn unit on %s" % territory_name)
		return
	
	# Enter tactical mode
	mode_manager.enter_tactical_mode(unit_data.unit, unit_data.camera, territory_name)
	
	# Disable strategic input
	if input_manager:
		input_manager.set_process_input(false)
	
	# Switch camera with smooth transition
	transition_to_camera(unit_data.camera)
	
	# Update UI
	if game_ui:
		game_ui.show_tactical_mode_ui()
	
	awaiting_territory_selection = false
	print("Map: Entered tactical mode on %s" % territory_name)

func exit_tactical_mode():
	"""Exit tactical mode and return to strategic mode"""
	if not mode_manager.is_tactical_mode():
		return
	
	var territory_name = mode_manager.get_stored_territory()
	var unit = mode_manager.get_active_unit()
	
	# CRITICAL: Store unit camera reference BEFORE mode_manager clears it
	var unit_camera = mode_manager.active_unit_camera
	
	# Despawn controllable unit
	if unit_manager and unit:
		unit_manager.despawn_controllable_unit(unit, territory_name)
	
	# Exit tactical mode (this clears active_unit_camera reference)
	mode_manager.exit_tactical_mode()
	
	# Re-enable strategic input
	if input_manager:
		input_manager.set_process_input(true)
	
	# Restore map camera to initial state
	if map_camera:
		map_camera.global_transform = initial_camera_transform
		map_camera.fov = initial_camera_fov
	
	# Switch camera back to map with explicit source camera
	if map_camera and unit_camera:
		transition_from_to(unit_camera, map_camera)
	elif map_camera:
		# Fallback: direct switch if unit camera was lost
		map_camera.current = true
	
	# Restore mouse mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# Update UI
	if game_ui:
		game_ui.hide_tactical_mode_ui()
		game_ui._update_ui()
	
	print("Map: Exited tactical mode")

func toggle_fighter_mode():
	"""Toggle fighter plane mode (spawn/despawn fighter with Ctrl+P)"""
	if not mode_manager or not map_camera:
		return
	
	if mode_manager.is_fighter_mode():
		# Exit fighter mode - despawn fighter and return to map camera
		exit_fighter_mode()
	else:
		# Enter fighter mode - spawn fighter at map camera position
		enter_fighter_mode()

func enter_fighter_mode():
	"""Spawn fighter at AirSpawn position and enter fighter mode"""
	# Exit any other mode first (mutually exclusive)
	if mode_manager.is_tactical_mode():
		exit_tactical_mode()
	
	# Get AirSpawn node
	var air_spawn = get_node_or_null("AirSpawn")
	if not air_spawn:
		push_error("Map: AirSpawn node not found")
		return
	
	# Pick fighter scene and camera path based on inspector setting
	var fighter_scene: PackedScene
	var camera_path: String
	match fighter_plane_type:
		"WW2":
			fighter_scene = FIGHTER_WW2_SCENE
			camera_path = FIGHTER_WW2_CAMERA_PATH
		_:
			fighter_scene = FIGHTER_WW1_SCENE
			camera_path = FIGHTER_WW1_CAMERA_PATH

	# Instantiate fighter
	var fighter = fighter_scene.instantiate()
	if not fighter:
		push_error("Map: Failed to instantiate fighter")
		return
	
	# Add fighter to scene FIRST (required before setting global_position)
	add_child(fighter)
	
	# Position fighter at AirSpawn location
	fighter.global_position = air_spawn.global_position
	
	# Set fighter rotation to match AirSpawn's rotation
	fighter.global_rotation = air_spawn.global_rotation
	
	# Get fighter's camera
	var fighter_camera = fighter.get_node_or_null(camera_path)
	if not fighter_camera:
		push_error("Map: Fighter camera not found")
		fighter.queue_free()
		return
	
	# Enter fighter mode
	mode_manager.enter_fighter_mode(fighter, fighter_camera)
	_bind_hud_to_fighter(fighter)

	# Shrink ground units while flying
	if unit_manager:
		unit_manager.set_fighter_scale_active(true)
	
	# Disable strategic input
	if input_manager:
		input_manager.set_process_input(false)
	
	# Switch camera with smooth transition
	transition_to_camera(fighter_camera)
	
	# Set mouse mode for fighter controls
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED
	
	# Update UI if present
	if game_ui:
		game_ui.show_tactical_mode_ui()  # Reuse tactical UI for now
	
	print("Map: Entered fighter mode at position %s" % fighter.global_position)

func exit_fighter_mode():
	"""Exit fighter mode and return to strategic mode"""
	if not mode_manager.is_fighter_mode():
		return
	
	var fighter = mode_manager.get_active_fighter()
	
	# Store fighter camera reference BEFORE mode_manager clears it
	var fighter_camera = mode_manager.active_fighter_camera
	
	# Exit fighter mode (this clears references)
	mode_manager.exit_fighter_mode()

	# Restore ground unit scale after leaving fighter mode
	if unit_manager:
		unit_manager.set_fighter_scale_active(false)
	
	# Re-enable strategic input
	if input_manager:
		input_manager.set_process_input(true)
	
	# Restore map camera to initial state
	if map_camera:
		map_camera.global_transform = initial_camera_transform
		map_camera.fov = initial_camera_fov
	
	# Switch camera back to map with explicit source camera
	if map_camera and fighter_camera:
		transition_from_to(fighter_camera, map_camera)
	elif map_camera:
		# Fallback: direct switch if fighter camera was lost
		map_camera.current = true
	
	# Restore mouse mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# Update UI
	if game_ui:
		game_ui.hide_tactical_mode_ui()
		game_ui._update_ui()
	
	# Despawn fighter after camera transition completes
	if fighter:
		# Wait for camera transition to finish before despawning
		await get_tree().create_timer(0.5).timeout
		fighter.queue_free()

	_hide_fighter_hud()
	
	print("Map: Exited fighter mode")

func _ensure_fighter_hud() -> FighterHUD:
	if fighter_hud:
		fighter_hud.visible = true
		return fighter_hud

	if not fighter_hud_scene:
		push_warning("Map: FighterHUD scene not found")
		return null

	fighter_hud = fighter_hud_scene.instantiate() as FighterHUD
	add_child(fighter_hud)
	return fighter_hud

func _bind_hud_to_fighter(fighter: Node) -> void:
	var hud := _ensure_fighter_hud()
	if hud:
		hud.bind_to_controller(fighter)

func _hide_fighter_hud() -> void:
	if fighter_hud:
		fighter_hud.bind_to_controller(null)
		fighter_hud.visible = false

func transition_to_camera(target_camera: Camera3D, duration: float = 0.4):
	"""Smoothly transition between cameras"""
	if not target_camera:
		return
	
	# Cancel existing transition
	if camera_transition_tween:
		camera_transition_tween.kill()
	
	# Get current active camera
	var current_camera = map_camera if mode_manager.is_strategic_mode() else mode_manager.active_unit_camera
	if not current_camera or current_camera == target_camera:
		target_camera.current = true
		return
	
	# Use explicit transition
	transition_from_to(current_camera, target_camera, duration)

func transition_from_to(source_camera: Camera3D, target_camera: Camera3D, duration: float = 0.4):
	"""Transition from explicit source camera to target camera"""
	if not source_camera or not target_camera:
		if target_camera:
			target_camera.current = true
		return
	
	if source_camera == target_camera:
		target_camera.current = true
		return
	
	# Cancel existing transition
	if camera_transition_tween:
		camera_transition_tween.kill()
	
	# Store transform data
	var start_transform = source_camera.global_transform
	var end_transform = target_camera.global_transform
	var start_fov = source_camera.fov
	var end_fov = target_camera.fov
	
	# Create transition camera
	var transition_cam = Camera3D.new()
	add_child(transition_cam)
	transition_cam.global_transform = start_transform
	transition_cam.fov = start_fov
	transition_cam.current = true
	
	# Animate transition
	camera_transition_tween = create_tween()
	camera_transition_tween.set_parallel(true)
	camera_transition_tween.tween_property(transition_cam, "global_transform", end_transform, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	camera_transition_tween.tween_property(transition_cam, "fov", end_fov, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	
	# Clean up after transition
	camera_transition_tween.chain().tween_callback(func():
		target_camera.current = true
		transition_cam.queue_free()
		camera_transition_tween = null
	)
