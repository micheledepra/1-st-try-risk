extends Control

## RiskCombatUI - Modal for Risk-style dice combat

signal combat_resolved(attacker_remaining: int, defender_remaining: int)

# UI References
@onready var attacker_panel = %AttackerPanel
@onready var defender_panel = %DefenderPanel
@onready var attacker_territory_label = %AttackerTerritoryLabel
@onready var defender_territory_label = %DefenderTerritoryLabel
@onready var attacker_units_label = %AttackerUnitsLabel
@onready var defender_units_label = %DefenderUnitsLabel
@onready var dice_count_selector = %DiceCountSelector
@onready var sequential_check = %SequentialCheck
@onready var attacker_roll_btn = %AttackerRollBtn
@onready var defender_roll_btn = %DefenderRollBtn
@onready var attacker_dice_container = %AttackerDiceContainer
@onready var defender_dice_container = %DefenderDiceContainer
@onready var result_label = %ResultLabel
@onready var continue_btn = %ContinueBtn
@onready var retreat_btn = %RetreatBtn
@onready var status_label = %StatusLabel

# Battle state
var attacker_territory: String
var defender_territory: String
var attacker_units: int
var defender_units: int
var attacker_color: Color
var defender_color: Color

# Round state
var attacker_dice_count: int = 1
var defender_dice_count: int = 1
var attacker_rolls: Array[int] = []
var defender_rolls: Array[int] = []
var sequential_mode: bool = false
var current_roll_index: int = 0

enum BattlePhase { SETUP, ATTACKER_ROLLING, DEFENDER_ROLLING, RESULTS }
var current_phase: BattlePhase = BattlePhase.SETUP

# Dice face representations
const DICE_FACES = ["⚀", "⚁", "⚂", "⚃", "⚄", "⚅"]

func _ready():
	attacker_roll_btn.pressed.connect(_on_attacker_roll)
	defender_roll_btn.pressed.connect(_on_defender_roll)
	continue_btn.pressed.connect(_on_continue)
	retreat_btn.pressed.connect(_on_retreat)
	dice_count_selector.value_changed.connect(_on_dice_count_changed)
	sequential_check.toggled.connect(_on_sequential_toggled)
	
	# Center the modal
	_center_modal()

func _center_modal():
	await get_tree().process_frame
	position = Vector2(
		(get_viewport().get_visible_rect().size.x - size.x) / 2,
		(get_viewport().get_visible_rect().size.y - size.y) / 2
	)

func setup(atk_territory: String, atk_units: int, atk_color: Color,
		   def_territory: String, def_units: int, def_color: Color):
	attacker_territory = atk_territory
	defender_territory = def_territory
	attacker_units = atk_units
	defender_units = def_units
	attacker_color = atk_color
	defender_color = def_color
	
	_apply_panel_colors()
	_update_ui()
	_set_phase(BattlePhase.SETUP)
	show()

func _apply_panel_colors():
	var atk_style = StyleBoxFlat.new()
	atk_style.bg_color = Color(attacker_color, 0.8)
	atk_style.border_color = attacker_color.darkened(0.3)
	atk_style.set_border_width_all(3)
	atk_style.set_corner_radius_all(8)
	attacker_panel.add_theme_stylebox_override("panel", atk_style)
	
	var def_style = StyleBoxFlat.new()
	def_style.bg_color = Color(defender_color, 0.8)
	def_style.border_color = defender_color.darkened(0.3)
	def_style.set_border_width_all(3)
	def_style.set_corner_radius_all(8)
	defender_panel.add_theme_stylebox_override("panel", def_style)

func _update_ui():
	attacker_territory_label.text = attacker_territory
	defender_territory_label.text = defender_territory
	attacker_units_label.text = "Units: %d 🪖" % attacker_units
	defender_units_label.text = "Units: %d 🪖" % defender_units
	
	# Update dice selector based on available units
	var max_attacker_dice = DiceCombatResolver.get_attacker_max_dice(attacker_units)
	dice_count_selector.max_value = max_attacker_dice
	dice_count_selector.min_value = 1
	dice_count_selector.value = mini(attacker_dice_count, max_attacker_dice)
	attacker_dice_count = int(dice_count_selector.value)
	
	defender_dice_count = DiceCombatResolver.get_defender_max_dice(defender_units)

func _set_phase(phase: BattlePhase):
	current_phase = phase
	
	match phase:
		BattlePhase.SETUP:
			status_label.text = "Choose dice count and roll method"
			dice_count_selector.editable = true
			sequential_check.disabled = false
			attacker_roll_btn.visible = true
			attacker_roll_btn.disabled = false
			attacker_roll_btn.text = "Roll %d Dice" % attacker_dice_count
			defender_roll_btn.visible = false
			continue_btn.visible = false
			retreat_btn.visible = false
			result_label.text = ""
			_clear_dice_display()
			attacker_rolls.clear()
			defender_rolls.clear()
			current_roll_index = 0
			
		BattlePhase.ATTACKER_ROLLING:
			dice_count_selector.editable = false
			sequential_check.disabled = true
			attacker_roll_btn.visible = true
			defender_roll_btn.visible = false
			if sequential_mode:
				status_label.text = "Rolling dice %d of %d..." % [current_roll_index + 1, attacker_dice_count]
				attacker_roll_btn.text = "Roll Die %d" % (current_roll_index + 1)
			else:
				status_label.text = "Attacker rolling..."
				attacker_roll_btn.disabled = true
			
		BattlePhase.DEFENDER_ROLLING:
			status_label.text = "Defender rolling %d dice..." % defender_dice_count
			attacker_roll_btn.visible = false
			defender_roll_btn.visible = true
			defender_roll_btn.text = "Roll %d Dice" % defender_dice_count
			# Auto-roll for defender
			_auto_defender_roll()
			
		BattlePhase.RESULTS:
			status_label.text = ""
			attacker_roll_btn.visible = false
			defender_roll_btn.visible = false
			_show_results()

func _on_dice_count_changed(value: float):
	attacker_dice_count = int(value)
	if current_phase == BattlePhase.SETUP:
		attacker_roll_btn.text = "Roll %d Dice" % attacker_dice_count

func _on_sequential_toggled(pressed: bool):
	sequential_mode = pressed

func _on_attacker_roll():
	if current_phase == BattlePhase.SETUP:
		_set_phase(BattlePhase.ATTACKER_ROLLING)
		if not sequential_mode:
			# Roll all dice at once
			attacker_rolls = DiceCombatResolver.roll_dice(attacker_dice_count)
			_display_dice(attacker_dice_container, attacker_rolls)
			_set_phase(BattlePhase.DEFENDER_ROLLING)
		else:
			# Sequential: roll first die
			_roll_next_attacker_die()
	elif current_phase == BattlePhase.ATTACKER_ROLLING and sequential_mode:
		_roll_next_attacker_die()

func _roll_next_attacker_die():
	var roll = DiceCombatResolver.roll_single()
	attacker_rolls.append(roll)
	_display_dice(attacker_dice_container, attacker_rolls)
	current_roll_index += 1
	
	if current_roll_index >= attacker_dice_count:
		# Attacker finished rolling
		_set_phase(BattlePhase.DEFENDER_ROLLING)
	else:
		status_label.text = "Rolling dice %d of %d..." % [current_roll_index + 1, attacker_dice_count]
		attacker_roll_btn.text = "Roll Die %d" % (current_roll_index + 1)

func _on_defender_roll():
	# Manual defender roll (not used in auto mode)
	defender_rolls = DiceCombatResolver.roll_dice(defender_dice_count)
	_display_dice(defender_dice_container, defender_rolls)
	_set_phase(BattlePhase.RESULTS)

func _auto_defender_roll():
	# Automatic defender roll after short delay
	await get_tree().create_timer(0.5).timeout
	defender_rolls = DiceCombatResolver.roll_dice(defender_dice_count)
	_display_dice(defender_dice_container, defender_rolls)
	_set_phase(BattlePhase.RESULTS)

func _display_dice(container: HBoxContainer, rolls: Array[int]):
	# Clear existing dice
	for child in container.get_children():
		child.queue_free()
	
	# Add dice labels
	for roll in rolls:
		var dice_label = Label.new()
		dice_label.text = DICE_FACES[roll - 1]
		dice_label.add_theme_font_size_override("font_size", 48)
		dice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		container.add_child(dice_label)

func _clear_dice_display():
	for child in attacker_dice_container.get_children():
		child.queue_free()
	for child in defender_dice_container.get_children():
		child.queue_free()

func _show_results():
	var result = DiceCombatResolver.compare_dice(attacker_rolls, defender_rolls)
	var atk_losses = result["attacker_losses"]
	var def_losses = result["defender_losses"]
	
	# Apply losses
	attacker_units -= atk_losses
	defender_units -= def_losses
	
	# Update unit labels
	_update_ui()
	
	# Build result text
	var result_text = "⚔️ Battle Result ⚔️\n"
	result_text += "Attacker lost: %d unit(s)\n" % atk_losses
	result_text += "Defender lost: %d unit(s)\n" % def_losses
	
	# Highlight dice comparison
	result_text += _format_comparison()
	
	result_label.text = result_text
	
	# Check battle end conditions
	if defender_units <= 0:
		status_label.text = "🏆 TERRITORY CONQUERED! 🏆"
		continue_btn.visible = false
		retreat_btn.visible = true
		retreat_btn.text = "Proceed"
	elif attacker_units < 2:
		status_label.text = "⚠️ Cannot continue attacking"
		continue_btn.visible = false
		retreat_btn.visible = true
		retreat_btn.text = "End Battle"
	else:
		status_label.text = "Continue attacking or retreat?"
		continue_btn.visible = true
		continue_btn.text = "Continue Attack"
		retreat_btn.visible = true
		retreat_btn.text = "Retreat"

func _format_comparison() -> String:
	var atk_sorted = attacker_rolls.duplicate()
	var def_sorted = defender_rolls.duplicate()
	atk_sorted.sort()
	atk_sorted.reverse()
	def_sorted.sort()
	def_sorted.reverse()
	
	var text = "\n"
	var comparisons = mini(atk_sorted.size(), def_sorted.size())
	
	for i in range(comparisons):
		var atk_val = atk_sorted[i]
		var def_val = def_sorted[i]
		var winner = "🔴" if atk_val > def_val else "🔵"
		text += "%s vs %s → %s\n" % [DICE_FACES[atk_val - 1], DICE_FACES[def_val - 1], winner]
	
	return text

func _on_continue():
	# Reset for another round
	_set_phase(BattlePhase.SETUP)

func _on_retreat():
	# End battle and emit final results
	combat_resolved.emit(attacker_units, defender_units)
	queue_free()
