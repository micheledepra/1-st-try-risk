extends Resource
class_name Player

## Player data for Risk game
## Stores player information, army reserves, and game state

@export var id: int = 0
@export var player_name: String = ""
@export var color: Color = Color.WHITE
@export var is_eliminated: bool = false

# Game state
var army_reserves: int = 0
var territories_owned: Array[String] = []

func _init(p_id: int = 0, p_name: String = "", p_color: Color = Color.WHITE):
	id = p_id
	player_name = p_name
	color = p_color
	is_eliminated = false
	army_reserves = 0
	territories_owned = []

func add_territory(territory_name: String) -> void:
	if not territories_owned.has(territory_name):
		territories_owned.append(territory_name)

func remove_territory(territory_name: String) -> void:
	var idx = territories_owned.find(territory_name)
	if idx != -1:
		territories_owned.remove_at(idx)
	
	# Check if player is eliminated
	if territories_owned.is_empty():
		is_eliminated = true

func get_territory_count() -> int:
	return territories_owned.size()

func add_armies(count: int) -> void:
	army_reserves += count

func remove_armies(count: int) -> bool:
	if army_reserves >= count:
		army_reserves -= count
		return true
	return false

func has_armies() -> bool:
	return army_reserves > 0

func reset() -> void:
	territories_owned.clear()
	army_reserves = 0
	is_eliminated = false
