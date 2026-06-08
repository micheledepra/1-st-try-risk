extends Control

## Game UI - Displays game state and handles player interaction

# References to UI elements (using unique names)
@onready var player_name_label: Label = %PlayerNameLabel
@onready var army_label: Label = %ArmyLabel
@onready var territory_label: Label = %TerritoryLabel
@onready var reinforcements_label: Label = %ReinforcementsLabel
@onready var turn_number_label: Label = %TurnNumberLabel
@onready var phase_label: Label = %PhaseLabel
@onready var player_position_label: Label = %PlayerPositionLabel
@onready var instruction_label: Label = %InstructionLabel
@onready var confirm_button: Button = %ConfirmButton

# Panel references for positioning
@onready var player_panel: PanelContainer = $PlayerPanel
@onready var phase_panel: PanelContainer = $PhasePanel
@onready var instruction_panel: PanelContainer = $InstructionPanel
@onready var button_panel: PanelContainer = $ButtonPanel

# Contextual Player Info panel references
@onready var contextual_player_info: FoldableContainer = $ContextualPlayerInfo
@onready var contextual_content_vbox: VBoxContainer = %ContentVBox
@onready var star_label: Label = %StarLabel
@onready var selected_player_name: Label = %SelectedPlayerName
@onready var selected_territories: Label = %SelectedTerritories
@onready var selected_units: Label = %SelectedUnits
@onready var selected_reinforcements: Label = %SelectedReinforcements
@onready var continents_hbox: HBoxContainer = %ContinentsHBox
@onready var no_continents_label: Label = %NoContinentsLabel
@onready var territory_name_label: Label = %TerritoryNameLabel
@onready var neighbors_grid: GridContainer = %NeighborsGrid

var game_manager: Node
var instruction_timer: Timer

# Phase box references
var setup_box: PanelContainer = null
var game_over_box: PanelContainer = null
var phase_boxes_container: HBoxContainer = null
var reinforcement_box: PanelContainer = null
var attack_box: PanelContainer = null
var fortify_box: PanelContainer = null

# Contextual panel state
var selected_territory: String = ""
var selected_player: Player = null
var input_manager: Node = null

# Continent colors for the contextual panel
const CONTINENT_COLORS = {
	"north_america": Color(0.259, 0.529, 0.961, 1),  # Blue
	"south_america": Color(0.259, 0.961, 0.271, 1),  # Green
	"europe": Color(0.608, 0.259, 0.961, 1),         # Purple
	"africa": Color(0.961, 0.643, 0.259, 1),         # Orange
	"asia": Color(0.961, 0.259, 0.259, 1),           # Red
	"australia": Color(0.259, 0.961, 0.949, 1)       # Cyan
}

const CONTINENT_ABBREVIATIONS = {
	"north_america": "NA",
	"south_america": "SA",
	"europe": "EU",
	"africa": "AF",
	"asia": "AS",
	"australia": "AU"
}

# Constants
const MARGIN = 20
const INSTRUCTION_DISPLAY_TIME = 5.0  # Seconds before instruction panel fades out

# Phase box colors
const PHASE_COLOR_SETUP = Color("#FFD700")  # Yellow/Gold for setup
const PHASE_COLOR_REINFORCEMENT = Color("#4A90D9")  # Blue
const PHASE_COLOR_ATTACK = Color("#D94A4A")  # Red
const PHASE_COLOR_FORTIFY = Color("#4AD9D9")  # Cyan
const PHASE_COLOR_COMPLETED = Color("#4AD94A")  # Green
const PHASE_COLOR_UPCOMING = Color("#606060")  # Grey
const PHASE_COLOR_GAME_OVER = Color("#FFD700")  # Gold for game over
const PHASE_BOX_FONT_SIZE = 10
const PHASE_BOX_CORNER_RADIUS = 12
const PHASE_BOX_BORDER_WIDTH = 3
const PHASE_CONTAINER_HEIGHT = 85

func _ready():
	# Allow mouse to pass through the root Control node
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Position panels BEFORE getting size (size needs to be calculated first)
	call_deferred("_position_panels")
	
	# Get GameManager reference
	game_manager = get_node("/root/GameManager")
	
	# Connect GameManager signals
	if game_manager:
		game_manager.turn_changed.connect(_on_turn_changed)
		game_manager.phase_changed.connect(_on_phase_changed)
		game_manager.game_over.connect(_on_game_over)
		game_manager.armies_changed.connect(_on_armies_changed)
	
	# Create and configure instruction timer
	instruction_timer = Timer.new()
	instruction_timer.wait_time = INSTRUCTION_DISPLAY_TIME
	instruction_timer.one_shot = true
	instruction_timer.timeout.connect(_on_instruction_timer_timeout)
	add_child(instruction_timer)
	
	# Setup phase boxes in phase panel
	_setup_phase_boxes()
	
	# Connect to TerritoryInputManager (deferred to ensure Map is loaded)
	call_deferred("_connect_territory_input")
	
	# Initial update
	_update_ui()

func _position_panels():
	# Get viewport size for responsive positioning
	var _viewport_size = get_viewport_rect().size
	
	# Configure all panels to stop mouse events (so they're clickable)
	# but allow pass-through everywhere else
	_configure_panel_mouse_filter(player_panel)
	_configure_panel_mouse_filter(phase_panel)
	_configure_panel_mouse_filter(instruction_panel)
	_configure_panel_mouse_filter(button_panel)
	
	# Player Panel - Top Left
	player_panel.position = Vector2(MARGIN, MARGIN)
	player_panel.anchor_left = 0.0
	player_panel.anchor_top = 0.0
	player_panel.anchor_right = 0.0
	player_panel.anchor_bottom = 0.0
	
	# Phase Panel - Top Right (uses fixed height, width from inspector)
	var phase_panel_width = phase_panel.size.x
	var phase_panel_height = PHASE_CONTAINER_HEIGHT  # Use constant (85px) instead of runtime size
	phase_panel.anchor_left = 1.0
	phase_panel.anchor_top = 0.0
	phase_panel.anchor_right = 1.0
	phase_panel.anchor_bottom = 0.0
	phase_panel.offset_left = -phase_panel_width - MARGIN
	phase_panel.offset_top = MARGIN
	phase_panel.offset_right = -MARGIN
	phase_panel.offset_bottom = phase_panel_height + MARGIN
	phase_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	phase_panel.grow_vertical = Control.GROW_DIRECTION_END
	
	# Instruction Panel - Top Center
	instruction_panel.anchor_left = 0.5
	instruction_panel.anchor_top = 0.0
	instruction_panel.anchor_right = 0.5
	instruction_panel.anchor_bottom = 0.0
	instruction_panel.offset_left = -instruction_panel.size.x / 2
	instruction_panel.offset_top = MARGIN
	instruction_panel.offset_right = instruction_panel.size.x / 2
	instruction_panel.offset_bottom = instruction_panel.size.y + MARGIN
	instruction_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	instruction_panel.grow_vertical = Control.GROW_DIRECTION_END
	
	# Button Panel - Bottom Right
	button_panel.anchor_left = 1.0
	button_panel.anchor_top = 1.0
	button_panel.anchor_right = 1.0
	button_panel.anchor_bottom = 1.0
	button_panel.offset_left = -button_panel.size.x - MARGIN
	button_panel.offset_top = -button_panel.size.y - MARGIN
	button_panel.offset_right = -MARGIN
	button_panel.offset_bottom = -MARGIN
	button_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	button_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	
	# Contextual Player Info - Below Phase Panel, aligned horizontally with same width
	contextual_player_info.anchor_left = 1.0
	contextual_player_info.anchor_top = 0.0
	contextual_player_info.anchor_right = 1.0
	contextual_player_info.anchor_bottom = 0.0
	# Use the phase panel's width to ensure alignment
	contextual_player_info.custom_minimum_size.x = phase_panel_width
	contextual_player_info.offset_left = -phase_panel_width - MARGIN
	contextual_player_info.offset_top = phase_panel_height + MARGIN + 4  # Below phase panel with small gap
	contextual_player_info.offset_right = -MARGIN
	contextual_player_info.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	contextual_player_info.grow_vertical = Control.GROW_DIRECTION_END

func _configure_panel_mouse_filter(panel: PanelContainer):
	# Panel itself should stop mouse events (so it's visible/clickable)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# But allow pass-through for all child containers (except buttons)
	for child in panel.get_children():
		if child is Container and not child is Button:
			_set_mouse_filter_recursive(child, Control.MOUSE_FILTER_IGNORE)

func _set_mouse_filter_recursive(node: Node, filter: int):
	if node is Control and not node is Button:
		node.mouse_filter = filter
	
	for child in node.get_children():
		_set_mouse_filter_recursive(child, filter)

func _update_ui():
	if not game_manager:
		return
	
	var current_player = game_manager.get_current_player()
	if not current_player:
		return
	
	# Update player info
	player_name_label.text = current_player.player_name
	player_name_label.add_theme_color_override("font_color", current_player.color)
	
	# Update armies on map
	var total_armies = 0
	for territory_name in current_player.territories_owned:
		total_armies += game_manager.get_territory_armies(territory_name)
	army_label.text = "🪖: %d" % total_armies
	
	# Update territories count
	territory_label.text = "⛳: %d" % current_player.territories_owned.size()
	
	# Update reinforcements
	reinforcements_label.text = "⏭️: %d" % current_player.army_reserves
	
	# Update turn number
	turn_number_label.text = "Turn: %d" % game_manager.turn_number
	
	# Update player position (n/x format)
	var player_index = game_manager.current_player_index + 1
	var total_players = game_manager.players.size()
	player_position_label.text = "%d/%d" % [player_index, total_players]
	
	# Update phase with color coding
	_update_phase_display()
	
	# Update instructions and button
	_update_instructions_and_button(current_player)

func _update_phase_display():
	if not game_manager:
		return
	
	var current_phase = game_manager.current_phase
	
	# Show setup box for SETUP phase, game_over box for GAME_OVER, otherwise show 3-phase row
	if current_phase == game_manager.GamePhase.SETUP:
		if setup_box:
			setup_box.visible = true
		if game_over_box:
			game_over_box.visible = false
		if phase_boxes_container:
			phase_boxes_container.visible = false
		# Hide old phase label
		if phase_label:
			phase_label.visible = false
	elif current_phase == game_manager.GamePhase.GAME_OVER:
		if setup_box:
			setup_box.visible = false
		if game_over_box:
			game_over_box.visible = true
		if phase_boxes_container:
			phase_boxes_container.visible = false
		if phase_label:
			phase_label.visible = false
	else:
		# Show 3-phase boxes for REINFORCEMENT, ATTACK, FORTIFY
		if setup_box:
			setup_box.visible = false
		if game_over_box:
			game_over_box.visible = false
		if phase_boxes_container:
			phase_boxes_container.visible = true
		if phase_label:
			phase_label.visible = false
		
		# Update box colors based on current phase
		_update_phase_box_colors(current_phase)

func _update_phase_box_colors(current_phase):
	# Phase order: REINFORCEMENT (1), ATTACK (2), FORTIFY (3)
	var phase_order = {
		game_manager.GamePhase.REINFORCEMENT: 1,
		game_manager.GamePhase.ATTACK: 2,
		game_manager.GamePhase.FORTIFY: 3
	}
	
	var current_order = phase_order.get(current_phase, 0)
	
	# Update Reinforcement box
	if reinforcement_box:
		var rein_order = 1
		if rein_order < current_order:
			_set_phase_box_style(reinforcement_box, PHASE_COLOR_COMPLETED, Color.BLACK)
		elif rein_order == current_order:
			_set_phase_box_style(reinforcement_box, PHASE_COLOR_REINFORCEMENT, Color.WHITE)
		else:
			_set_phase_box_style(reinforcement_box, PHASE_COLOR_UPCOMING, Color.WHITE)
	
	# Update Attack box
	if attack_box:
		var atk_order = 2
		if atk_order < current_order:
			_set_phase_box_style(attack_box, PHASE_COLOR_COMPLETED, Color.BLACK)
		elif atk_order == current_order:
			_set_phase_box_style(attack_box, PHASE_COLOR_ATTACK, Color.WHITE)
		else:
			_set_phase_box_style(attack_box, PHASE_COLOR_UPCOMING, Color.WHITE)
	
	# Update Fortify box
	if fortify_box:
		var fort_order = 3
		if fort_order < current_order:
			_set_phase_box_style(fortify_box, PHASE_COLOR_COMPLETED, Color.BLACK)
		elif fort_order == current_order:
			_set_phase_box_style(fortify_box, PHASE_COLOR_FORTIFY, Color.BLACK)
		else:
			_set_phase_box_style(fortify_box, PHASE_COLOR_UPCOMING, Color.WHITE)

func _set_phase_box_style(box: PanelContainer, bg_color: Color, text_color: Color):
	var style = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.set_corner_radius_all(PHASE_BOX_CORNER_RADIUS)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	# Add border with 50% darker color
	style.border_color = bg_color.darkened(0.5)
	style.set_border_width_all(PHASE_BOX_BORDER_WIDTH)
	box.add_theme_stylebox_override("panel", style)
	
	# Update label color
	var label = box.get_node_or_null("Label")
	if label:
		label.add_theme_color_override("font_color", text_color)

func _update_instructions_and_button(player: Player):
	match game_manager.current_phase:
		game_manager.GamePhase.SETUP:
			if player.army_reserves > 0:
				instruction_label.text = "Click your territories to place %d armies\nRight-click to undo" % player.army_reserves
				confirm_button.text = "Next Player"
				confirm_button.disabled = true
			else:
				instruction_label.text = "All armies placed! Ready for next player."
				confirm_button.text = "Next Player"
				confirm_button.disabled = false
			
			# Show instruction panel and start fade timer
			_show_instruction_panel()
		
		game_manager.GamePhase.REINFORCEMENT:
			if player.army_reserves > 0:
				instruction_label.text = "Place %d reinforcements on your territories\nRight-click to undo" % player.army_reserves
				confirm_button.text = "Start Attack"
				confirm_button.disabled = true
			else:
				instruction_label.text = "All reinforcements placed!"
				confirm_button.text = "Start Attack"
				confirm_button.disabled = false
			
			# Show instruction panel and start fade timer
			_show_instruction_panel()
		
		game_manager.GamePhase.ATTACK:
			instruction_label.text = "Click your territory (2+ armies) then enemy territory to attack\nRight-click to cancel"
			
			# Show game mode indicator
			if game_manager.developer_mode:
				instruction_label.text += "\n⚙️ DEVELOPER MODE: Manual battle resolution"
			else:
				instruction_label.text += "\n⚡ AUTO MODE: -1 unit per side"
			
			confirm_button.text = "Skip to Fortify"
			confirm_button.disabled = false
			
			# Show instruction panel and start fade timer
			_show_instruction_panel()
		
		game_manager.GamePhase.FORTIFY:
			instruction_label.text = "Move armies between connected territories\nRight-click to cancel"
			confirm_button.text = "End Turn"
			confirm_button.disabled = false
			
			# Show instruction panel and start fade timer
			_show_instruction_panel()
		
		game_manager.GamePhase.GAME_OVER:
			instruction_label.text = "🏆 %s WINS THE GAME! 🏆" % player.player_name
			confirm_button.visible = false

# Signal handlers
func _on_turn_changed(_player: Player):
	_update_ui()

func _on_phase_changed(_new_phase):
	_update_ui()
	_animate_current_phase_box(_new_phase)

func _on_game_over(_winner: Player):
	_update_ui()

func _on_armies_changed(_territory_name: String, _army_count: int):
	_update_ui()

func _on_confirm_button_pressed():
	if not game_manager:
		return
	
	match game_manager.current_phase:
		game_manager.GamePhase.SETUP:
			game_manager.end_turn()
		
		game_manager.GamePhase.REINFORCEMENT:
			game_manager.advance_phase()
		
		game_manager.GamePhase.ATTACK:
			game_manager.advance_phase()
		
		game_manager.GamePhase.FORTIFY:
			game_manager.end_turn()

# Public method for map.gd to update instructions during selection
func set_instruction_text(text: String):
	instruction_label.text = text

# Instruction panel visibility management
func _show_instruction_panel():
	# Make instruction panel visible
	instruction_panel.modulate.a = 1.0
	instruction_panel.visible = true
	
	# Restart the timer
	instruction_timer.start()

func _on_instruction_timer_timeout():
	# Create a tween to fade out the instruction panel
	var tween = create_tween()
	tween.tween_property(instruction_panel, "modulate:a", 0.0, 1.0)
	tween.tween_callback(func(): instruction_panel.visible = false)

func show_territory_selection_prompt():
	"""Show prompt for territory selection in tactical mode"""
	instruction_label.text = "🎯 SELECT A TERRITORY YOU CONTROL\nPress ESC to cancel"
	_show_instruction_panel_persistent()
	print("GameUI: Showing territory selection prompt")

func hide_territory_selection_prompt():
	"""Hide territory selection prompt"""
	instruction_panel.visible = false
	print("GameUI: Hiding territory selection prompt")

func show_tactical_mode_ui():
	"""Show tactical mode UI overlay"""
	instruction_label.text = "🎮 TACTICAL MODE\nWASD to move • Mouse to aim • Ctrl+U to exit"
	_show_instruction_panel_persistent()
	
	# Hide strategic UI elements
	confirm_button.visible = false
	print("GameUI: Showing tactical mode UI")

func hide_tactical_mode_ui():
	"""Hide tactical mode UI and restore strategic UI"""
	instruction_panel.visible = false
	confirm_button.visible = true
	print("GameUI: Hiding tactical mode UI")

func _show_instruction_panel_persistent():
	"""Show instruction panel without auto-fade"""
	instruction_panel.modulate.a = 1.0
	instruction_panel.visible = true
	# Stop any running timer
	if instruction_timer.time_left > 0:
		instruction_timer.stop()

# Phase box setup and creation functions
func _setup_phase_boxes():
	"""Setup phase boxes inside the phase panel"""
	# Get the VBoxContainer inside PhasePanel
	var margin_container = phase_panel.get_node_or_null("MarginContainer")
	if not margin_container:
		return
	var vbox = margin_container.get_node_or_null("VBoxContainer")
	if not vbox:
		return
	
	# Stop margin container and vbox from expanding vertically
	margin_container.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	vbox.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	
	# Fix PlayerPositionLabel which has SIZE_EXPAND_FILL causing expansion
	var player_pos_label = vbox.get_node_or_null("PlayerPositionLabel")
	if player_pos_label:
		player_pos_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	
	# Create container for phase boxes (will be added after existing elements)
	var phase_container = VBoxContainer.new()
	phase_container.name = "PhaseBoxContainer"
	phase_container.add_theme_constant_override("separation", 4)
	phase_container.custom_minimum_size = Vector2(0, PHASE_CONTAINER_HEIGHT)
	phase_container.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	phase_container.clip_contents = true
	vbox.add_child(phase_container)
	
	# Create setup box (single yellow box for initial setup)
	setup_box = _create_phase_box("INITIAL SETUP PHASE", PHASE_COLOR_SETUP, Color.BLACK)
	setup_box.name = "SetupBox"
	setup_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	phase_container.add_child(setup_box)
	
	# Create game over box (single gold box, displayed like setup)
	game_over_box = _create_phase_box("GAME OVER", PHASE_COLOR_GAME_OVER, Color.BLACK)
	game_over_box.name = "GameOverBox"
	game_over_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	game_over_box.visible = false
	phase_container.add_child(game_over_box)
	
	# Create container for 3 phase boxes (horizontal)
	phase_boxes_container = HBoxContainer.new()
	phase_boxes_container.name = "PhaseBoxesRow"
	phase_boxes_container.add_theme_constant_override("separation", 6)
	phase_boxes_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	phase_boxes_container.visible = false
	phase_container.add_child(phase_boxes_container)
	
	# Create the 3 phase boxes
	reinforcement_box = _create_phase_box("REINFORCE", PHASE_COLOR_REINFORCEMENT, Color.WHITE)
	reinforcement_box.name = "ReinforcementBox"
	reinforcement_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	phase_boxes_container.add_child(reinforcement_box)
	
	attack_box = _create_phase_box("ATTACK", PHASE_COLOR_ATTACK, Color.WHITE)
	attack_box.name = "AttackBox"
	attack_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	phase_boxes_container.add_child(attack_box)
	
	fortify_box = _create_phase_box("FORTIFY", PHASE_COLOR_FORTIFY, Color.BLACK)
	fortify_box.name = "FortifyBox"
	fortify_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	phase_boxes_container.add_child(fortify_box)

func _create_phase_box(text: String, bg_color: Color, text_color: Color) -> PanelContainer:
	"""Create a styled phase box with label"""
	var box = PanelContainer.new()
	
	# Create style
	var style = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.set_corner_radius_all(PHASE_BOX_CORNER_RADIUS)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	# Add border with 50% darker color
	style.border_color = bg_color.darkened(0.5)
	style.set_border_width_all(PHASE_BOX_BORDER_WIDTH)
	box.add_theme_stylebox_override("panel", style)
	
	# Set size constraints - max height of 2 lines of text (roughly 20px * 2 + padding)
	box.custom_minimum_size = Vector2(0, 0)
	
	# Create label
	var label = Label.new()
	label.name = "Label"
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", PHASE_BOX_FONT_SIZE)
	label.add_theme_color_override("font_color", text_color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(label)
	
	return box

func _animate_current_phase_box(phase):
	"""Animate the current phase box with a pop effect"""
	var box_to_animate: PanelContainer = null
	
	if not game_manager:
		return
	
	match phase:
		game_manager.GamePhase.SETUP:
			box_to_animate = setup_box
		game_manager.GamePhase.REINFORCEMENT:
			box_to_animate = reinforcement_box
		game_manager.GamePhase.ATTACK:
			box_to_animate = attack_box
		game_manager.GamePhase.FORTIFY:
			box_to_animate = fortify_box
		game_manager.GamePhase.GAME_OVER:
			box_to_animate = game_over_box
	
	if box_to_animate and box_to_animate.visible:
		# Reset scale and pivot
		box_to_animate.pivot_offset = box_to_animate.size / 2.0
		box_to_animate.scale = Vector2.ONE
		
		# Create pop animation: scale up then back down
		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_ELASTIC)
		tween.tween_property(box_to_animate, "scale", Vector2(1.15, 1.15), 0.2)
		tween.tween_property(box_to_animate, "scale", Vector2.ONE, 0.2)

# =============================================================================
# CONTEXTUAL PLAYER INFO PANEL
# =============================================================================

func _connect_territory_input():
	"""Connect to TerritoryInputManager for territory click events"""
	input_manager = get_tree().get_first_node_in_group("territory_input")
	if input_manager:
		input_manager.territory_clicked.connect(_on_any_territory_clicked)
		print("GameUI: Connected to TerritoryInputManager")
	else:
		push_warning("GameUI: TerritoryInputManager not found. Retrying...")
		# Retry after a short delay if not found
		get_tree().create_timer(0.5).timeout.connect(_connect_territory_input)

func _on_any_territory_clicked(territory_name: String, _ctrl_pressed: bool):
	"""Handle any territory click to update contextual panel"""
	selected_territory = territory_name
	
	# Only update if panel is expanded (visible)
	if contextual_content_vbox and contextual_content_vbox.visible:
		_update_contextual_panel()

func _on_contextual_visibility_changed():
	"""Called when the contextual panel VBox visibility changes (panel expanded/collapsed)"""
	if contextual_content_vbox and contextual_content_vbox.visible and selected_territory != "":
		_update_contextual_panel()

func _update_contextual_panel():
	"""Update all sections of the contextual player info panel"""
	if not game_manager or selected_territory == "":
		return
	
	# Get the owner of the selected territory
	selected_player = game_manager.get_territory_owner(selected_territory)
	if not selected_player:
		return
	
	# Update player info section
	_update_player_info_section()
	
	# Update continents section
	_update_continents_section()
	
	# Update territory name
	_update_territory_section()

func _update_player_info_section():
	"""Update the player info section of the contextual panel"""
	if not selected_player:
		return
	
	var current_player = game_manager.get_current_player()
	
	# Show star if this is the current player's territory
	star_label.visible = (selected_player.id == current_player.id)
	
	# Update player name with their color
	selected_player_name.text = selected_player.player_name
	selected_player_name.add_theme_color_override("font_color", selected_player.color)
	
	# Update territories count
	var territory_count = selected_player.territories_owned.size()
	selected_territories.text = "⛳: %d" % territory_count
	
	# Calculate total units on map
	var total_units = 0
	for territory_name in selected_player.territories_owned:
		total_units += game_manager.get_territory_armies(territory_name)
	selected_units.text = "🪖: %d" % total_units
	
	# Calculate next turn reinforcements
	var next_reinforcements = _calculate_reinforcements(selected_player)
	selected_reinforcements.text = "⏭️: %d" % next_reinforcements

func _calculate_reinforcements(player: Player) -> int:
	"""Calculate expected reinforcements for next turn"""
	# Base reinforcement: floor(territories / 3), minimum 3 (classic Risk rule)
	@warning_ignore("integer_division")
	var base_armies = max(3, player.territories_owned.size() / 3)
	
	# Add continent bonuses
	var continent_bonus = 0
	for continent_name in game_manager.CONTINENT_BONUSES.keys():
		if game_manager.does_player_own_continent(player.id, continent_name):
			continent_bonus += game_manager.CONTINENT_BONUSES[continent_name]
	
	return base_armies + continent_bonus

func _update_continents_section():
	"""Update the controlled continents section"""
	if not selected_player:
		return
	
	# Clear existing continent indicators (except the NoContinentsLabel)
	for child in continents_hbox.get_children():
		if child != no_continents_label:
			child.queue_free()
	
	# Check which continents the selected player owns
	var owned_continents = []
	for continent_name in game_manager.CONTINENT_BONUSES.keys():
		if game_manager.does_player_own_continent(selected_player.id, continent_name):
			owned_continents.append(continent_name)
	
	# Show/hide "None" label
	no_continents_label.visible = owned_continents.is_empty()
	
	# Add colored indicators for owned continents
	for continent_name in owned_continents:
		var bonus = game_manager.CONTINENT_BONUSES[continent_name]
		var color = CONTINENT_COLORS.get(continent_name, Color.WHITE)
		var abbrev = CONTINENT_ABBREVIATIONS.get(continent_name, "??")
		
		var label = Label.new()
		label.text = "+%d ●%s" % [bonus, abbrev]
		label.add_theme_color_override("font_color", color)
		label.tooltip_text = _format_territory_name(continent_name) + " (+" + str(bonus) + " armies)"
		continents_hbox.add_child(label)

func _update_territory_section():
	"""Update the territory name and neighbors display"""
	if not game_manager or selected_territory == "":
		return
	
	# Update territory name
	territory_name_label.text = _format_territory_name(selected_territory)
	
	# Clear existing neighbor entries
	for child in neighbors_grid.get_children():
		child.queue_free()
	
	# Get neighbors from map data
	var territory_data = game_manager.map_data.get(selected_territory, {})
	var neighbors = territory_data.get("neighbors", [])
	
	# Determine font size based on number of neighbors (dynamic adjustment)
	var font_size = 13
	if neighbors.size() > 4:
		font_size = 12
	if neighbors.size() > 6:
		font_size = 11
	
	for neighbor_name in neighbors:
		# Get neighbor owner for coloring
		var owner = game_manager.get_territory_owner(neighbor_name)
		var armies = game_manager.get_territory_armies(neighbor_name)
		var owner_color = owner.color if owner else Color.GRAY
		
		# Territory name label (colored by owner)
		var name_label = Label.new()
		name_label.text = _format_territory_name(neighbor_name)
		name_label.add_theme_color_override("font_color", owner_color)
		name_label.add_theme_font_size_override("font_size", font_size)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.clip_text = true
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.tooltip_text = _format_territory_name(neighbor_name)
		neighbors_grid.add_child(name_label)
		
		# Army count label with clearer formatting
		var army_label = Label.new()
		army_label.text = "[%d]" % armies
		army_label.add_theme_font_size_override("font_size", font_size)
		army_label.add_theme_color_override("font_color", owner_color)
		army_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		army_label.tooltip_text = "%d armies" % armies
		neighbors_grid.add_child(army_label)

func _format_territory_name(name: String) -> String:
	"""Convert snake_case territory name to Title Case"""
	# Replace underscores with spaces and capitalize each word
	var words = name.replace("_", " ").split(" ")
	var formatted_words = []
	for word in words:
		if word.length() > 0:
			formatted_words.append(word.capitalize())
	return " ".join(formatted_words)
