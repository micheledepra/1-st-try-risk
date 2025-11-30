extends Node

## GameManager - Singleton for turn-based Risk game flow
## Manages players, turns, phases, and game state

enum GamePhase {
	SETUP,           # Initial territory distribution and army placement
	REINFORCEMENT,   # Player receives and places new armies
	ATTACK,          # Player can attack neighboring territories
	FORTIFY,         # Player can move armies between connected territories
	GAME_OVER        # Game has ended
}

# Signals
signal phase_changed(new_phase: GamePhase)
signal turn_changed(player: Player)
signal player_eliminated(player: Player)
signal game_over(winner: Player)
signal armies_changed(territory_name: String, army_count: int)

# Game state
var players: Array[Player] = []
var current_player_index: int = 0
var current_phase: GamePhase = GamePhase.SETUP
var turn_number: int = 0
var map_data: Dictionary = {}
var num_players: int = 0

# Continent bonuses (armies per turn)
const CONTINENT_BONUSES = {
	"north_america": 5,
	"south_america": 2,
	"europe": 5,
	"africa": 3,
	"asia": 7,
	"australia": 2
}

# Initial army counts based on player count (classic Risk rules)
const INITIAL_ARMIES = {
	2: 40,
	3: 35,
	4: 30,
	5: 25,
	6: 20
}

func _ready():
	load_map_data()

func load_map_data():
	var file = FileAccess.open("res://map_data.json", FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		file.close()
		
		var json = JSON.new()
		var error = json.parse(json_string)
		if error == OK:
			map_data = json.data
			print("GameManager: Loaded map data with %d territories" % map_data.size())
		else:
			push_error("GameManager: Failed to parse map_data.json")
	else:
		push_error("GameManager: Failed to open map_data.json")

func set_num_players(count: int):
	num_players = count
	print("GameManager: Number of players set to %d" % num_players)

func start_player_setup():
	# Reset game state for new game
	players.clear()
	current_player_index = 0
	turn_number = 0
	current_phase = GamePhase.SETUP
	print("GameManager: Starting player setup")

func start_new_game(player_count: int):
	if player_count < 2 or player_count > 6:
		push_error("GameManager: Invalid player count. Must be 2-6 players.")
		return
	
	# Reset game state
	players.clear()
	current_player_index = 0
	turn_number = 0
	current_phase = GamePhase.SETUP
	
	# Create players
	var player_colors = [
		Color(0.8, 0.2, 0.2, 1.0),  # Red
		Color(0.2, 0.2, 0.8, 1.0),  # Blue
		Color(0.2, 0.8, 0.2, 1.0),  # Green
		Color(0.8, 0.8, 0.2, 1.0),  # Yellow
		Color(0.8, 0.2, 0.8, 1.0),  # Magenta
		Color(0.2, 0.8, 0.8, 1.0),  # Cyan
	]
	
	for i in range(player_count):
		var player = Player.new(i + 1, "Player %d" % (i + 1), player_colors[i])
		players.append(player)
	
	print("GameManager: Started new game with %d players" % player_count)
	
	# Distribute territories randomly
	distribute_territories_randomly()
	
	# Give initial armies for setup phase
	assign_initial_armies()
	
	# Start with first player
	current_player_index = 0
	emit_signal("turn_changed", get_current_player())
	emit_signal("phase_changed", current_phase)

func distribute_territories_randomly():
	# Get all territory names
	var all_territories = map_data.keys()
	all_territories.shuffle()
	
	# Distribute territories round-robin to players
	var player_index = 0
	for territory_name in all_territories:
		var player = players[player_index]
		player.add_territory(territory_name)
		
		# Update map ownership
		if has_node("/root/Map"):
			get_node("/root/Map").set_territory_owner(territory_name, player.id)
		
		# Place one army on each territory
		set_territory_armies(territory_name, 1)
		
		player_index = (player_index + 1) % players.size()
	
	print("GameManager: Distributed %d territories among %d players" % [all_territories.size(), players.size()])

func assign_initial_armies():
	var armies_per_player = INITIAL_ARMIES.get(players.size(), 20)
	
	# Each player already has 1 army per territory, subtract those
	for player in players:
		var remaining_armies = armies_per_player - player.get_territory_count()
		player.add_armies(remaining_armies)
		print("Player %d has %d territories and %d armies to place" % [player.id, player.get_territory_count(), player.army_reserves])

func get_current_player() -> Player:
	if players.is_empty():
		return null
	return players[current_player_index]

func end_turn():
	# Validate phase progression
	match current_phase:
		GamePhase.SETUP:
			# During setup, players must place ALL remaining armies before passing
			if get_current_player().army_reserves > 0:
				push_warning("Player still has armies to place in setup! Must deploy all %d remaining armies." % get_current_player().army_reserves)
				return
			
			# Check if all players finished setup (including current player who just finished)
			var all_done = true
			for player in players:
				if player.army_reserves > 0:
					all_done = false
					break
			
			if all_done:
				# All players have deployed their initial armies
				# Move to ATTACK phase starting with first player
				current_phase = GamePhase.ATTACK
				turn_number = 1
				current_player_index = 0
				print("GameManager: Setup complete! All initial armies deployed. Starting Turn 1 - ATTACK phase with Player %d" % get_current_player().id)
				emit_signal("phase_changed", current_phase)
				emit_signal("turn_changed", get_current_player())
			else:
				# Move to next player for their setup turn
				current_player_index = (current_player_index + 1) % players.size()
				print("GameManager: Setup phase - Player %d's turn to deploy armies" % get_current_player().id)
				emit_signal("turn_changed", get_current_player())
			return
			
		GamePhase.FORTIFY:
			# End of turn, move to next player
			advance_to_next_player()
			
		_:
			push_warning("Cannot end turn in phase: %s" % GamePhase.keys()[current_phase])
			return
	
	emit_signal("turn_changed", get_current_player())

func advance_to_next_player():
	# Skip eliminated players
	var attempts = 0
	while attempts < players.size():
		current_player_index = (current_player_index + 1) % players.size()
		if not players[current_player_index].is_eliminated:
			break
		attempts += 1
	
	# Start new turn with reinforcement phase
	current_phase = GamePhase.REINFORCEMENT
	turn_number += 1
	
	# Calculate and give reinforcement armies
	give_reinforcement_armies()
	
	emit_signal("phase_changed", current_phase)
	emit_signal("turn_changed", get_current_player())
	
	print("GameManager: Turn %d - Player %d's turn" % [turn_number, get_current_player().id])

func give_reinforcement_armies():
	var player = get_current_player()
	
	# Base reinforcement: territories / 3 (minimum 3)
	var base_armies = max(3, player.get_territory_count() / 3)
	
	# Add continent bonuses
	var continent_bonus = 0
	for continent_name in CONTINENT_BONUSES.keys():
		if does_player_own_continent(player.id, continent_name):
			continent_bonus += CONTINENT_BONUSES[continent_name]
			print("Player %d gets +%d armies for controlling %s" % [player.id, CONTINENT_BONUSES[continent_name], continent_name])
	
	var total_armies = base_armies + continent_bonus
	player.add_armies(total_armies)
	
	print("Player %d receives %d armies (%d base + %d continent bonus)" % [player.id, total_armies, base_armies, continent_bonus])

func does_player_own_continent(player_id: int, continent_name: String) -> bool:
	for territory_name in map_data.keys():
		var territory_data = map_data[territory_name]
		if territory_data.get("continent", "") == continent_name:
			# Check if this territory is owned by the player
			var owner_id = 0
			for player in players:
				if player.territories_owned.has(territory_name):
					owner_id = player.id
					break
			
			if owner_id != player_id:
				return false
	
	return true

func advance_phase():
	match current_phase:
		GamePhase.REINFORCEMENT:
			# Check if player placed all armies
			if get_current_player().army_reserves > 0:
				push_warning("Player must place all reinforcement armies before attacking!")
				return
			current_phase = GamePhase.ATTACK
			
		GamePhase.ATTACK:
			current_phase = GamePhase.FORTIFY
			
		GamePhase.FORTIFY:
			end_turn()
			return
			
		_:
			return
	
	emit_signal("phase_changed", current_phase)
	print("GameManager: Advanced to phase %s" % GamePhase.keys()[current_phase])

# Territory army management
var territory_armies: Dictionary = {}

func set_territory_armies(territory_name: String, count: int):
	territory_armies[territory_name] = count
	emit_signal("armies_changed", territory_name, count)

func get_territory_armies(territory_name: String) -> int:
	return territory_armies.get(territory_name, 0)

func add_armies_to_territory(territory_name: String, count: int):
	var current = get_territory_armies(territory_name)
	set_territory_armies(territory_name, current + count)

func get_territory_owner(territory_name: String) -> Player:
	for player in players:
		if player.territories_owned.has(territory_name):
			return player
	return null

func are_territories_connected(from_territory: String, to_territory: String, player_id: int) -> bool:
	# BFS to check if territories are connected through player-owned territories
	var visited = {}
	var queue = [from_territory]
	visited[from_territory] = true
	
	while not queue.is_empty():
		var current = queue.pop_front()
		
		if current == to_territory:
			return true
		
		var neighbors = map_data.get(current, {}).get("neighbors", [])
		for neighbor in neighbors:
			if visited.has(neighbor):
				continue
			
			var territory_owner = get_territory_owner(neighbor)
			if territory_owner and territory_owner.id == player_id:
				visited[neighbor] = true
				queue.append(neighbor)
	
	return false

func check_win_condition():
	var remaining_players = 0
	var winner: Player = null
	
	for player in players:
		if not player.is_eliminated:
			remaining_players += 1
			winner = player
	
	if remaining_players == 1 and winner != null:
		current_phase = GamePhase.GAME_OVER
		emit_signal("game_over", winner)
		print("GameManager: Game Over! Player %d wins!" % winner.id)

func eliminate_player(player: Player):
	player.is_eliminated = true
	emit_signal("player_eliminated", player)
	print("Player %d has been eliminated" % player.id)
	check_win_condition()
