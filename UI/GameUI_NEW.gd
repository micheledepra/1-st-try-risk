extends Control

## Simple Game UI - Displays game state and single action button

# UI Elements - Separate Panels
var player_panel: PanelContainer
var phase_panel: PanelContainer
var instruction_panel: PanelContainer
var button_panel: PanelContainer

# Player Panel Elements
var player_label: Label
var armies_label: Label
var territories_label: Label

# Phase Panel Elements
var phase_label: Label
var turn_number_label: Label
var player_position_label: Label

# Instruction Panel Elements
var instruction_label: Label

# Button Panel Elements
var confirm_button: Button

var game_manager: Node

# UI Constants
const MARGIN = 20
const PADDING = 15
const MIN_PANEL_WIDTH = 300

func _ready():
	# Build UI structure
	_build_ui()
	
	# Get GameManager reference
	game_manager = get_node("/root/GameManager")
	
	# Connect signals
	if game_manager:
		game_manager.turn_changed.connect(_on_turn_changed)
		game_manager.phase_changed.connect(_on_phase_changed)
		game_manager.game_over.connect(_on_game_over)
	
	# Initial update
	_update_ui()

func _build_ui():
	_build_player_panel()
	_build_phase_panel()
	_build_instruction_panel()
	_build_button_panel()
	
	# Connect button
	confirm_button.pressed.connect(_on_confirm_pressed)

func _build_player_panel():
	# Player panel - Top Left
	player_panel = PanelContainer.new()
	player_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	player_panel.position = Vector2(MARGIN, MARGIN)
	player_panel.custom_minimum_size = Vector2(MIN_PANEL_WIDTH, 0)
	add_child(player_panel)
	
	# Margin container for padding
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", PADDING)
	margin.add_theme_constant_override("margin_top", PADDING)
	margin.add_theme_constant_override("margin_right", PADDING)
	margin.add_theme_constant_override("margin_bottom", PADDING)
	player_panel.add_child(margin)
	
	# Vertical box for player info
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)
	
	# Player name label
	player_label = Label.new()
	player_label.text = "Player 1"
	player_label.add_theme_font_size_override("font_size", 24)
	player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(player_label)
	
	# Separator
	var separator = HSeparator.new()
	vbox.add_child(separator)
	
	# Armies label
	armies_label = Label.new()
	armies_label.text = "Armies: 0"
	armies_label.add_theme_font_size_override("font_size", 16)
	armies_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(armies_label)
	
	# Territories label
	territories_label = Label.new()
	territories_label.text = "Territories: 0"
	territories_label.add_theme_font_size_override("font_size", 16)
	territories_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(territories_label)

func _build_phase_panel():
	# Phase panel - Top Right
	phase_panel = PanelContainer.new()
	phase_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	phase_panel.position = Vector2(-MARGIN, MARGIN)
	phase_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	phase_panel.custom_minimum_size = Vector2(MIN_PANEL_WIDTH, 0)
	add_child(phase_panel)
	
	# Margin container for padding
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", PADDING)
	margin.add_theme_constant_override("margin_top", PADDING)
	margin.add_theme_constant_override("margin_right", PADDING)
	margin.add_theme_constant_override("margin_bottom", PADDING)
	phase_panel.add_child(margin)
	
	# Vertical box for phase info
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)
	
	# Phase label
	phase_label = Label.new()
	phase_label.text = "Phase: SETUP"
	phase_label.add_theme_font_size_override("font_size", 20)
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(phase_label)
	
	# Separator
	var separator = HSeparator.new()
	vbox.add_child(separator)
	
	# Turn number label
	turn_number_label = Label.new()
	turn_number_label.text = "Turn: 0"
	turn_number_label.add_theme_font_size_override("font_size", 16)
	turn_number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(turn_number_label)
	
	# Player position label
	player_position_label = Label.new()
	player_position_label.text = "Player: 1/2"
	player_position_label.add_theme_font_size_override("font_size", 16)
	player_position_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(player_position_label)

func _build_instruction_panel():
	# Instruction panel - Top Center
	instruction_panel = PanelContainer.new()
	instruction_panel.anchor_left = 0.5
	instruction_panel.anchor_right = 0.5
	instruction_panel.anchor_top = 0.0
	instruction_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	instruction_panel.position = Vector2(0, MARGIN)
	instruction_panel.custom_minimum_size = Vector2(400, 0)
	add_child(instruction_panel)
	
	# Margin container for padding
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", PADDING * 2)
	margin.add_theme_constant_override("margin_top", PADDING)
	margin.add_theme_constant_override("margin_right", PADDING * 2)
	margin.add_theme_constant_override("margin_bottom", PADDING)
	instruction_panel.add_child(margin)
	
	# Instruction label
	instruction_label = Label.new()
	instruction_label.text = "Deploy your armies"
	instruction_label.add_theme_font_size_override("font_size", 16)
	instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instruction_label.custom_minimum_size = Vector2(350, 0)
	margin.add_child(instruction_label)

func _build_button_panel():
	# Button panel - Bottom Right
	button_panel = PanelContainer.new()
	button_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	button_panel.position = Vector2(-MARGIN, -MARGIN)
	button_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	button_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(button_panel)
	
	# Margin container for padding
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", PADDING * 2)
	margin.add_theme_constant_override("margin_top", PADDING)
	margin.add_theme_constant_override("margin_right", PADDING * 2)
	margin.add_theme_constant_override("margin_bottom", PADDING)
	button_panel.add_child(margin)
	
	# VBox to hold multiple buttons
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)
	
	# Confirm button
	confirm_button = Button.new()
	confirm_button.text = "Confirm"
	confirm_button.custom_minimum_size = Vector2(200, 50)
	confirm_button.add_theme_font_size_override("font_size", 18)
	vbox.add_child(confirm_button)

func _update_ui():
	if not game_manager:
		return
	
	var current_player = game_manager.get_current_player()
	if not current_player:
		return
	
	# Update player info
	player_label.text = current_player.player_name
	player_label.add_theme_color_override("font_color", current_player.color)
	
	armies_label.text = "Armies: %d" % current_player.army_reserves
	territories_label.text = "Territories: %d" % current_player.get_territory_count()
	
	# Update turn info
	turn_number_label.text = "Turn: %d" % game_manager.turn_number
	var player_position = game_manager.current_player_index + 1
	var total_players = game_manager.players.size()
	player_position_label.text = "Player: %d/%d" % [player_position, total_players]
	
	# Update phase info
	var phase_text = ""
	var phase_color = Color.WHITE
	
	match game_manager.current_phase:
		game_manager.GamePhase.SETUP:
			phase_text = "SETUP"
			phase_color = Color.YELLOW
		game_manager.GamePhase.REINFORCEMENT:
			phase_text = "REINFORCEMENT"
			phase_color = Color.GREEN
		game_manager.GamePhase.ATTACK:
			phase_text = "ATTACK"
			phase_color = Color.RED
		game_manager.GamePhase.FORTIFY:
			phase_text = "FORTIFY"
			phase_color = Color.CYAN
		game_manager.GamePhase.GAME_OVER:
			phase_text = "GAME OVER"
			phase_color = Color.GOLD
	
	phase_label.text = "Phase: %s" % phase_text
	phase_label.add_theme_color_override("font_color", phase_color)
	
	# Update instructions and button
	_update_instructions_and_button(current_player)

func _update_instructions_and_button(player: Player):
	match game_manager.current_phase:
		game_manager.GamePhase.SETUP:
			if player.army_reserves > 0:
				instruction_label.text = "Left-click your territories to place %d armies\nRight-click to undo" % player.army_reserves
				confirm_button.text = "Next Player"
				confirm_button.disabled = true
			else:
				instruction_label.text = "All armies placed!"
				confirm_button.text = "Next Player"
				confirm_button.disabled = false
		
		game_manager.GamePhase.REINFORCEMENT:
			if player.army_reserves > 0:
				instruction_label.text = "Place %d reinforcement armies\nLeft-click to place, Right-click to undo" % player.army_reserves
				confirm_button.text = "Start Attack"
				confirm_button.disabled = true
			else:
				instruction_label.text = "All armies placed!"
				confirm_button.text = "Start Attack"
				confirm_button.disabled = false
		
		game_manager.GamePhase.ATTACK:
			instruction_label.text = "Click your territory (2+ armies) then enemy territory to attack"
			confirm_button.text = "Skip to Fortify"
			confirm_button.disabled = false
		
		game_manager.GamePhase.FORTIFY:
			instruction_label.text = "Move armies between connected territories\n(optional)"
			confirm_button.text = "End Turn"
			confirm_button.disabled = false
		
		game_manager.GamePhase.GAME_OVER:
			instruction_label.text = "Game Over!"
			confirm_button.visible = false

func _on_confirm_pressed():
	match game_manager.current_phase:
		game_manager.GamePhase.SETUP:
			game_manager.end_turn()
		game_manager.GamePhase.REINFORCEMENT:
			game_manager.advance_phase()
		game_manager.GamePhase.ATTACK:
			game_manager.advance_phase()
		game_manager.GamePhase.FORTIFY:
			game_manager.end_turn()

func _on_turn_changed(_player: Player):
	_update_ui()

func _on_phase_changed(_new_phase):
	_update_ui()

func _on_game_over(winner: Player):
	_update_ui()
	instruction_label.text = "%s WINS!" % winner.player_name

# Public method for setting instruction text
func set_instruction_text(text: String):
	if instruction_label:
		instruction_label.text = text
