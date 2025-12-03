extends PanelContainer

## GameUI - Modular game interface for turn-based Risk gameplay
## All visual properties are customizable from the Godot editor

# ============================================================
# EXPORTED PROPERTIES
# ============================================================

## Layout Settings
@export_group("Layout")
@export var main_margin_left: int = 10
@export var main_margin_top: int = 10
@export var main_margin_right: int = 10
@export var main_margin_bottom: int = 10
@export var content_separation: int = 8
@export var section_padding: int = 8

## Player Info Section
@export_group("Player Info")
@export var player_name_font_size: int = 24
@export var player_stats_font_size: int = 14
@export var player_stats_spacing: int = 10

## Phase Info Section
@export_group("Phase Info")
@export var turn_number_font_size: int = 16
@export var phase_name_font_size: int = 20
@export var phase_info_spacing: int = 4

## Phase Colors
@export_subgroup("Phase Colors")
@export var setup_phase_color: Color = Color.YELLOW
@export var reinforcement_phase_color: Color = Color.GREEN
@export var attack_phase_color: Color = Color.RED
@export var fortify_phase_color: Color = Color.CYAN
@export var game_over_phase_color: Color = Color.GOLD

## Action Info Section
@export_group("Action Info")
@export var action_info_font_size: int = 13
@export var action_info_padding: int = 6

## Button Section
@export_group("Buttons")
@export var button_min_width: int = 150
@export var button_min_height: int = 36
@export var button_spacing: int = 10
@export var advance_button_text: String = "Advance Phase"
@export var end_turn_button_text: String = "End Turn"

## Instruction Messages
@export_group("Messages")
@export var setup_place_armies_msg: String = "Left-click your territories to place armies (Right-click to undo)"
@export var setup_complete_msg: String = "All armies placed! Click Next Player"
@export var reinforcement_place_msg: String = "Left-click to place reinforcement armies (Right-click to undo)"
@export var reinforcement_complete_msg: String = "All armies placed! Advance to attack or fortify"
@export var attack_instruction_msg: String = "Click your territory with 2+ armies, then click adjacent enemy territory to attack"
@export var fortify_instruction_msg: String = "Move armies between connected territories (optional), then end turn"
@export var game_over_msg: String = "Game Over!"

# ============================================================
# NODE REFERENCES
# ============================================================

@onready var main_container: MarginContainer = $MainContainer
@onready var content_vbox: VBoxContainer = $MainContainer/ContentVBox

# Player Info Section
@onready var player_info_section: PanelContainer = $MainContainer/ContentVBox/PlayerInfoSection
@onready var player_margin: MarginContainer = $MainContainer/ContentVBox/PlayerInfoSection/PlayerMargin
@onready var player_vbox: VBoxContainer = $MainContainer/ContentVBox/PlayerInfoSection/PlayerMargin/PlayerVBox
@onready var player_name_label: Label = %PlayerNameLabel
@onready var player_stats_hbox: HBoxContainer = $MainContainer/ContentVBox/PlayerInfoSection/PlayerMargin/PlayerVBox/PlayerStatsHBox
@onready var army_reserves_label: Label = %ArmyReservesLabel
@onready var territory_count_label: Label = %TerritoryCountLabel

# Phase Info Section
@onready var phase_info_section: PanelContainer = $MainContainer/ContentVBox/PhaseInfoSection
@onready var phase_margin: MarginContainer = $MainContainer/ContentVBox/PhaseInfoSection/PhaseMargin
@onready var phase_vbox: VBoxContainer = $MainContainer/ContentVBox/PhaseInfoSection/PhaseMargin/PhaseVBox
@onready var turn_number_label: Label = %TurnNumberLabel
@onready var phase_label: Label = %PhaseLabel

# Action Info Section
@onready var action_info_section: PanelContainer = $MainContainer/ContentVBox/ActionInfoSection
@onready var action_margin: MarginContainer = $MainContainer/ContentVBox/ActionInfoSection/ActionMargin
@onready var action_info_label: Label = %ActionInfoLabel

# Button Section
@onready var button_section: HBoxContainer = $MainContainer/ContentVBox/ButtonSection
@onready var advance_phase_button: Button = %AdvancePhaseButton
@onready var end_turn_button: Button = %EndTurnButton

# ============================================================
# GAME REFERENCES
# ============================================================

var game_manager: Node

# ============================================================
# LIFECYCLE METHODS
# ============================================================

func _ready():
	_apply_export_settings()
	_connect_game_manager()
	_connect_button_signals()
	update_ui()

func _apply_export_settings():
	# Apply main margins
	main_container.add_theme_constant_override("margin_left", main_margin_left)
	main_container.add_theme_constant_override("margin_top", main_margin_top)
	main_container.add_theme_constant_override("margin_right", main_margin_right)
	main_container.add_theme_constant_override("margin_bottom", main_margin_bottom)
	
	# Apply content separation
	content_vbox.add_theme_constant_override("separation", content_separation)
	
	# Player Info Section
	player_margin.add_theme_constant_override("margin_left", section_padding)
	player_margin.add_theme_constant_override("margin_top", section_padding)
	player_margin.add_theme_constant_override("margin_right", section_padding)
	player_margin.add_theme_constant_override("margin_bottom", section_padding)
	player_vbox.add_theme_constant_override("separation", 4)
	player_stats_hbox.add_theme_constant_override("separation", player_stats_spacing)
	
	player_name_label.add_theme_font_size_override("font_size", player_name_font_size)
	army_reserves_label.add_theme_font_size_override("font_size", player_stats_font_size)
	territory_count_label.add_theme_font_size_override("font_size", player_stats_font_size)
	
	# Phase Info Section
	phase_margin.add_theme_constant_override("margin_left", section_padding)
	phase_margin.add_theme_constant_override("margin_top", section_padding)
	phase_margin.add_theme_constant_override("margin_right", section_padding)
	phase_margin.add_theme_constant_override("margin_bottom", section_padding)
	phase_vbox.add_theme_constant_override("separation", phase_info_spacing)
	
	turn_number_label.add_theme_font_size_override("font_size", turn_number_font_size)
	phase_label.add_theme_font_size_override("font_size", phase_name_font_size)
	
	# Action Info Section
	action_margin.add_theme_constant_override("margin_left", section_padding)
	action_margin.add_theme_constant_override("margin_top", action_info_padding)
	action_margin.add_theme_constant_override("margin_right", section_padding)
	action_margin.add_theme_constant_override("margin_bottom", action_info_padding)
	
	action_info_label.add_theme_font_size_override("font_size", action_info_font_size)
	
	# Button Section
	button_section.add_theme_constant_override("separation", button_spacing)
	
	advance_phase_button.custom_minimum_size = Vector2(button_min_width, button_min_height)
	advance_phase_button.text = advance_button_text
	
	end_turn_button.custom_minimum_size = Vector2(button_min_width, button_min_height)
	end_turn_button.text = end_turn_button_text

func _connect_game_manager():
	game_manager = get_node("/root/GameManager")
	
	if game_manager:
		if not game_manager.turn_changed.is_connected(_on_turn_changed):
			game_manager.turn_changed.connect(_on_turn_changed)
		if not game_manager.phase_changed.is_connected(_on_phase_changed):
			game_manager.phase_changed.connect(_on_phase_changed)
		if not game_manager.game_over.is_connected(_on_game_over):
			game_manager.game_over.connect(_on_game_over)

func _connect_button_signals():
	if not advance_phase_button.pressed.is_connected(_on_advance_phase_pressed):
		advance_phase_button.pressed.connect(_on_advance_phase_pressed)
	if not end_turn_button.pressed.is_connected(_on_end_turn_pressed):
		end_turn_button.pressed.connect(_on_end_turn_pressed)

# ============================================================
# UI UPDATE METHODS
# ============================================================

func update_ui():
	if not game_manager:
		return
	
	var current_player = game_manager.get_current_player()
	if current_player == null:
		return
	
	_update_player_info(current_player)
	_update_phase_info()
	_update_button_states()
	_update_action_info()

func _update_player_info(player: Player):
	player_name_label.text = player.player_name
	player_name_label.add_theme_color_override("font_color", player.color)
	
	army_reserves_label.text = "Armies: %d" % player.army_reserves
	territory_count_label.text = "Territories: %d" % player.get_territory_count()

func _update_phase_info():
	turn_number_label.text = "Turn: %d" % game_manager.turn_number
	
	var phase_name = ""
	var phase_color = Color.WHITE
	
	match game_manager.current_phase:
		game_manager.GamePhase.SETUP:
			phase_name = "SETUP - Place Armies"
			phase_color = setup_phase_color
		game_manager.GamePhase.REINFORCEMENT:
			phase_name = "REINFORCEMENT"
			phase_color = reinforcement_phase_color
		game_manager.GamePhase.ATTACK:
			phase_name = "ATTACK"
			phase_color = attack_phase_color
		game_manager.GamePhase.FORTIFY:
			phase_name = "FORTIFY"
			phase_color = fortify_phase_color
		game_manager.GamePhase.GAME_OVER:
			phase_name = "GAME OVER"
			phase_color = game_over_phase_color
	
	phase_label.text = phase_name
	phase_label.add_theme_color_override("font_color", phase_color)

func _update_button_states():
	var current_player = game_manager.get_current_player()
	if current_player == null:
		advance_phase_button.disabled = true
		advance_phase_button.visible = false
		end_turn_button.disabled = true
		end_turn_button.visible = false
		return
	
	match game_manager.current_phase:
		game_manager.GamePhase.SETUP:
			advance_phase_button.visible = false
			end_turn_button.visible = true
			end_turn_button.text = "Next Player"
			end_turn_button.disabled = current_player.army_reserves > 0
			
		game_manager.GamePhase.REINFORCEMENT:
			advance_phase_button.visible = true
			advance_phase_button.text = "Start Attack Phase"
			advance_phase_button.disabled = current_player.army_reserves > 0
			end_turn_button.visible = false
			
		game_manager.GamePhase.ATTACK:
			advance_phase_button.visible = true
			advance_phase_button.text = "Skip to Fortify"
			advance_phase_button.disabled = false
			end_turn_button.visible = false
			
		game_manager.GamePhase.FORTIFY:
			advance_phase_button.visible = false
			end_turn_button.visible = true
			end_turn_button.text = "End Turn"
			end_turn_button.disabled = false
			
		game_manager.GamePhase.GAME_OVER:
			advance_phase_button.visible = false
			end_turn_button.visible = false

func _update_action_info():
	var current_player = game_manager.get_current_player()
	if current_player == null:
		action_info_label.text = ""
		return
	
	match game_manager.current_phase:
		game_manager.GamePhase.SETUP:
			if current_player.army_reserves > 0:
				action_info_label.text = setup_place_armies_msg.replace("armies", "%d armies" % current_player.army_reserves)
			else:
				action_info_label.text = setup_complete_msg
				
		game_manager.GamePhase.REINFORCEMENT:
			if current_player.army_reserves > 0:
				action_info_label.text = reinforcement_place_msg.replace("armies", "%d reinforcement armies" % current_player.army_reserves)
			else:
				action_info_label.text = reinforcement_complete_msg
				
		game_manager.GamePhase.ATTACK:
			action_info_label.text = attack_instruction_msg
			
		game_manager.GamePhase.FORTIFY:
			action_info_label.text = fortify_instruction_msg
			
		game_manager.GamePhase.GAME_OVER:
			action_info_label.text = game_over_msg

# ============================================================
# SIGNAL HANDLERS
# ============================================================

func _on_turn_changed(player: Player):
	update_ui()
	print("UI: Turn changed to %s" % player.player_name)

func _on_phase_changed(new_phase):
	update_ui()
	var phase_name = game_manager.GamePhase.keys()[new_phase]
	print("UI: Phase changed to %s" % phase_name)

func _on_game_over(winner: Player):
	update_ui()
	action_info_label.text = "%s WINS!" % winner.player_name
	print("UI: Game over - %s wins!" % winner.player_name)

func _on_advance_phase_pressed():
	game_manager.advance_phase()

func _on_end_turn_pressed():
	game_manager.end_turn()


func _on_advance_phase_button_pressed() -> void:
	pass # Replace with function body.


func _on_end_turn_button_pressed() -> void:
	pass # Replace with function body.
