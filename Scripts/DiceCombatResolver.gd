class_name DiceCombatResolver
extends RefCounted
## Handles Risk-style dice combat resolution

## Roll a specified number of dice (1-6 each)
static func roll_dice(count: int) -> Array[int]:
	var rolls: Array[int] = []
	for i in range(count):
		rolls.append(randi() % 6 + 1)
	return rolls

## Roll a single die
static func roll_single() -> int:
	return randi() % 6 + 1

## Calculate max dice attacker can use (units - 1, max 3)
static func get_attacker_max_dice(units: int) -> int:
	return mini(units - 1, 3)

## Calculate max dice defender can use (units, max 3)
static func get_defender_max_dice(units: int) -> int:
	return mini(units, 3)

## Compare dice and return losses: {attacker_losses: int, defender_losses: int}
## Attacker dice vs defender dice - ties go to defender
static func compare_dice(attacker_rolls: Array[int], defender_rolls: Array[int]) -> Dictionary:
	var attacker_sorted = attacker_rolls.duplicate()
	var defender_sorted = defender_rolls.duplicate()
	attacker_sorted.sort()
	attacker_sorted.reverse()
	defender_sorted.sort()
	defender_sorted.reverse()
	
	var attacker_losses = 0
	var defender_losses = 0
	var comparisons = mini(attacker_sorted.size(), defender_sorted.size())
	
	for i in range(comparisons):
		if attacker_sorted[i] > defender_sorted[i]:
			defender_losses += 1
		else:
			# Tie goes to defender
			attacker_losses += 1
	
	return {
		"attacker_losses": attacker_losses,
		"defender_losses": defender_losses
	}

## Check if attacker can attack (has at least 2 units)
static func can_attack(attacker_units: int) -> bool:
	return attacker_units >= 2

## Check if battle should end (defender eliminated or attacker can't continue)
static func is_battle_over(attacker_units: int, defender_units: int) -> bool:
	return defender_units <= 0 or attacker_units < 2
