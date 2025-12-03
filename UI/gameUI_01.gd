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

var game_manager: Node
var instruction_timer: Timer

# Constants
const MARGIN = 20
const INSTRUCTION_DISPLAY_TIME = 5.0  # Seconds before instruction panel fades out

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
	
	# Initial update
	_update_ui()

func _position_panels():
	# Get viewport size for responsive positioning
	var viewport_size = get_viewport_rect().size
	
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
	
	# Phase Panel - Top Right
	phase_panel.anchor_left = 1.0
	phase_panel.anchor_top = 0.0
	phase_panel.anchor_right = 1.0
	phase_panel.anchor_bottom = 0.0
	phase_panel.offset_left = -phase_panel.size.x - MARGIN
	phase_panel.offset_top = MARGIN
	phase_panel.offset_right = -MARGIN
	phase_panel.offset_bottom = phase_panel.size.y + MARGIN
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
	var phase_text = ""
	var phase_color = Color.WHITE
	
	match game_manager.current_phase:
		game_manager.GamePhase.SETUP:
			phase_text = "🛠️SETUP"
			phase_color = Color.YELLOW
		game_manager.GamePhase.REINFORCEMENT:
			phase_text = "🪖REINFORCEMENT"
			phase_color = Color.GREEN
		game_manager.GamePhase.ATTACK:
			phase_text = "⚔️ATTACK"
			phase_color = Color.RED
		game_manager.GamePhase.FORTIFY:
			phase_text = "🏯FORTIFY"
			phase_color = Color.CYAN
		game_manager.GamePhase.GAME_OVER:
			phase_text = "🏅GAME OVER"
			phase_color = Color.GOLD
	
	phase_label.text = phase_text
	phase_label.add_theme_color_override("font_color", phase_color)

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

func _on_game_over(winner: Player):
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
