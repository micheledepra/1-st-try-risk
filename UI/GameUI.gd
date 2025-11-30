extends PanelContainer

## GameUI - Main game interface for turn-based Risk gameplay
## Uses a single button for phase advancement and state refresh for proper initialization

@onready var player_name_label: Label = %PlayerNameLabel
@onready var turn_number_label: Label = %TurnNumberLabel
@onready var phase_label: Label = %PhaseLabel
@onready var army_reserves_label: Label = %ArmyReservesLabel
@onready var territory_count_label: Label = %TerritoryCountLabel

@onready var advance_button: Button = %AdvancePhaseButton

@onready var action_info_label: Label = %ActionInfoLabel

var game_manager: Node
var _is_initialized: bool = false

func _ready():
	# Defer initialization to ensure GameManager is fully ready
	call_deferred("_initialize_ui")

func _initialize_ui():
	game_manager = get_node_or_null("/root/GameManager")
	
	if not game_manager:
		push_error("GameUI: GameManager not found!")
		return
	
	# Connect signals for state refresh
	if not game_manager.turn_changed.is_connected(_on_turn_changed):
		game_manager.turn_changed.connect(_on_turn_changed)
	if not game_manager.phase_changed.is_connected(_on_phase_changed):
		game_manager.phase_changed.connect(_on_phase_changed)
	if not game_manager.game_over.is_connected(_on_game_over):
		game_manager.game_over.connect(_on_game_over)
	if not game_manager.armies_changed.is_connected(_on_armies_changed):
		game_manager.armies_changed.connect(_on_armies_changed)
	
	# Connect single button signal
	if not advance_button.pressed.is_connected(_on_advance_button_pressed):
		advance_button.pressed.connect(_on_advance_button_pressed)
	
	_is_initialized = true
	
	# Force initial state refresh
	_refresh_state()
	
	print("GameUI: Initialized and connected to GameManager")

## Force a complete state refresh from GameManager
func _refresh_state():
	if not _is_initialized or not game_manager:
		return
	
	_update_player_info()
	_update_phase_info()
	_update_button_state()
	_update_action_info()
	
	print("GameUI: State refreshed")

func _update_player_info():
	if not game_manager:
		return
	
	var current_player = game_manager.get_current_player()
	if current_player == null:
		player_name_label.text = "No Player"
		turn_number_label.text = "Turn: -"
		army_reserves_label.text = "Armies: -"
		territory_count_label.text = "Territories: -"
		return
	
	# Update player info with turn indicator
	player_name_label.text = "▶ " + current_player.player_name  # Turn indicator
	player_name_label.add_theme_color_override("font_color", current_player.color)
	
	# Update turn number - show 0 during setup, actual turn during game
	if game_manager.current_phase == game_manager.GamePhase.SETUP:
		turn_number_label.text = "Setup Phase"
	else:
		turn_number_label.text = "Turn: %d" % game_manager.turn_number
	
	# Update army and territory counts
	army_reserves_label.text = "Armies: %d" % current_player.army_reserves
	territory_count_label.text = "Territories: %d" % current_player.get_territory_count()

func _update_phase_info():
	if not game_manager:
		return
	
	var phase_name = ""
	var phase_color = Color.WHITE
	match game_manager.current_phase:
		game_manager.GamePhase.SETUP:
			phase_name = "SETUP - Place Armies"
			phase_color = Color.YELLOW
		game_manager.GamePhase.REINFORCEMENT:
			phase_name = "REINFORCEMENT"
			phase_color = Color.GREEN
		game_manager.GamePhase.ATTACK:
			phase_name = "ATTACK"
			phase_color = Color.RED
		game_manager.GamePhase.FORTIFY:
			phase_name = "FORTIFY"
			phase_color = Color.CYAN
		game_manager.GamePhase.GAME_OVER:
			phase_name = "GAME OVER"
			phase_color = Color.GOLD
	
	phase_label.text = phase_name
	phase_label.add_theme_color_override("font_color", phase_color)

func _update_button_state():
	var current_player = game_manager.get_current_player()
	if current_player == null:
		advance_button.disabled = true
		advance_button.text = "Waiting..."
		return
	
	# Single button that adapts based on current phase
	match game_manager.current_phase:
		game_manager.GamePhase.SETUP:
			advance_button.text = "Next Player"
			# Disabled until all armies are placed
			advance_button.disabled = current_player.army_reserves > 0
			
		game_manager.GamePhase.REINFORCEMENT:
			advance_button.text = "Start Attack Phase"
			# Disabled until all armies are placed
			advance_button.disabled = current_player.army_reserves > 0
			
		game_manager.GamePhase.ATTACK:
			advance_button.text = "Skip to Fortify"
			advance_button.disabled = false
			
		game_manager.GamePhase.FORTIFY:
			advance_button.text = "End Turn"
			advance_button.disabled = false
			
		game_manager.GamePhase.GAME_OVER:
			advance_button.text = "Game Over"
			advance_button.disabled = true

func _update_action_info():
	var current_player = game_manager.get_current_player()
	if current_player == null:
		action_info_label.text = "Waiting for game to start..."
		return
	
	match game_manager.current_phase:
		game_manager.GamePhase.SETUP:
			if current_player.army_reserves > 0:
				action_info_label.text = "Click your territories to place %d armies" % current_player.army_reserves
			else:
				action_info_label.text = "All armies placed! Click Next Player"
				
		game_manager.GamePhase.REINFORCEMENT:
			if current_player.army_reserves > 0:
				action_info_label.text = "Place %d reinforcement armies on your territories" % current_player.army_reserves
			else:
				action_info_label.text = "All armies placed! Advance to attack phase"
				
		game_manager.GamePhase.ATTACK:
			action_info_label.text = "Click your territory with 2+ armies, then click adjacent enemy territory to attack"
			
		game_manager.GamePhase.FORTIFY:
			action_info_label.text = "Move armies between connected territories (optional), then end turn"
			
		game_manager.GamePhase.GAME_OVER:
			action_info_label.text = "Game Over!"

## Signal handlers - trigger state refresh on changes
func _on_turn_changed(player: Player):
	_refresh_state()
	print("GameUI: Turn changed to %s" % player.player_name)

func _on_phase_changed(_new_phase):
	_refresh_state()
	var phase_name = game_manager.GamePhase.keys()[_new_phase] if game_manager else "UNKNOWN"
	print("GameUI: Phase changed to %s" % phase_name)

func _on_game_over(winner: Player):
	_refresh_state()
	action_info_label.text = "%s WINS!" % winner.player_name
	print("GameUI: Game over - %s wins!" % winner.player_name)

func _on_armies_changed(_territory_name: String, _army_count: int):
	# Refresh state when armies change to update counts
	_refresh_state()

## Single button handler for all phase advancement
func _on_advance_button_pressed():
	if not game_manager:
		return
	
	match game_manager.current_phase:
		game_manager.GamePhase.SETUP:
			# During setup, move to next player
			game_manager.end_turn()
		game_manager.GamePhase.REINFORCEMENT:
			# Advance to attack phase
			game_manager.advance_phase()
		game_manager.GamePhase.ATTACK:
			# Skip to fortify
			game_manager.advance_phase()
		game_manager.GamePhase.FORTIFY:
			# End turn (moves to next player's reinforcement)
			game_manager.end_turn()
