extends PanelContainer

## GameUI - Main game interface for turn-based Risk gameplay

@onready var player_name_label: Label = %PlayerNameLabel
@onready var turn_number_label: Label = %TurnNumberLabel
@onready var phase_label: Label = %PhaseLabel
@onready var army_reserves_label: Label = %ArmyReservesLabel
@onready var territory_count_label: Label = %TerritoryCountLabel

@onready var advance_phase_button: Button = %AdvancePhaseButton
@onready var end_turn_button: Button = %EndTurnButton

@onready var action_info_label: Label = %ActionInfoLabel

var game_manager: Node

func _ready():
	game_manager = get_node("/root/GameManager")
	
	# Connect signals
	if game_manager:
		game_manager.turn_changed.connect(_on_turn_changed)
		game_manager.phase_changed.connect(_on_phase_changed)
		game_manager.game_over.connect(_on_game_over)
		game_manager.armies_changed.connect(_on_armies_changed)
	
	# Connect button signals
	advance_phase_button.pressed.connect(_on_advance_phase_pressed)
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	
	update_ui()

func update_ui():
	if not game_manager:
		return
	
	var current_player = game_manager.get_current_player()
	if current_player == null:
		return
	
	# Update player info
	player_name_label.text = current_player.player_name
	player_name_label.add_theme_color_override("font_color", current_player.color)
	
	turn_number_label.text = "Turn: %d" % game_manager.turn_number
	army_reserves_label.text = "Armies: %d" % current_player.army_reserves
	territory_count_label.text = "Territories: %d" % current_player.get_territory_count()
	
	# Update phase info
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
	
	# Update button states
	update_button_states()
	
	# Update action info
	update_action_info()

func update_button_states():
	var current_player = game_manager.get_current_player()
	if current_player == null:
		advance_phase_button.disabled = true
		end_turn_button.disabled = true
		return
	
	match game_manager.current_phase:
		game_manager.GamePhase.SETUP:
			advance_phase_button.visible = false
			end_turn_button.visible = true
			# Check if this is the last player with armies to deploy
			var all_others_done = true
			for player in game_manager.players:
				if player != current_player and player.army_reserves > 0:
					all_others_done = false
					break
			if all_others_done and current_player.army_reserves == 0:
				end_turn_button.text = "Start Game!"
			else:
				end_turn_button.text = "Confirm Deployment"
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

func update_action_info():
	var current_player = game_manager.get_current_player()
	if current_player == null:
		action_info_label.text = ""
		return
	
	match game_manager.current_phase:
		game_manager.GamePhase.SETUP:
			if current_player.army_reserves > 0:
				action_info_label.text = "INITIAL DEPLOYMENT: Click your territories to place %d armies" % current_player.army_reserves
			else:
				# Check if all players are done to show appropriate message
				var all_done = true
				for player in game_manager.players:
					if player.army_reserves > 0:
						all_done = false
						break
				if all_done:
					action_info_label.text = "All players deployed! Click 'Start Game!' to begin"
				else:
					action_info_label.text = "All armies placed! Click 'Confirm Deployment' for next player"
				
		game_manager.GamePhase.REINFORCEMENT:
			if current_player.army_reserves > 0:
				action_info_label.text = "Place %d reinforcement armies on your territories" % current_player.army_reserves
			else:
				action_info_label.text = "All armies placed! Advance to attack or fortify"
				
		game_manager.GamePhase.ATTACK:
			action_info_label.text = "Click your territory with 2+ armies, then click adjacent enemy territory to attack"
			
		game_manager.GamePhase.FORTIFY:
			action_info_label.text = "Move armies between connected territories (optional), then end turn"
			
		game_manager.GamePhase.GAME_OVER:
			action_info_label.text = "Game Over!"

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

func _on_armies_changed(_territory_name: String, _army_count: int):
	# Update UI when armies are placed/changed to reflect current reserves
	update_ui()

func _on_advance_phase_pressed():
	game_manager.advance_phase()

func _on_end_turn_pressed():
	game_manager.end_turn()
