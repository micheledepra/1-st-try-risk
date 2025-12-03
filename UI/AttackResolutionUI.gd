extends Control

## AttackResolutionUI - Modal for resolving battle results

signal resolution_confirmed(attacker_remaining: int, defender_remaining: int)

@onready var attacker_panel = %AttackerPanel
@onready var defender_panel = %DefenderPanel
@onready var attacker_territory_label = %AttackerTerritoryLabel
@onready var defender_territory_label = %DefenderTerritoryLabel
@onready var attacker_initial_label = %AttackerInitialLabel
@onready var defender_initial_label = %DefenderInitialLabel
@onready var attacker_remaining_input = %AttackerRemainingInput
@onready var defender_remaining_input = %DefenderRemainingInput
@onready var confirm_button = %ConfirmButton

var attacker_initial_units: int
var defender_initial_units: int
var attacker_color: Color
var defender_color: Color

func _ready():
	confirm_button.pressed.connect(_on_confirm_pressed)
	attacker_remaining_input.value_changed.connect(_validate_inputs)
	defender_remaining_input.value_changed.connect(_validate_inputs)
	
	# Center the modal
	position = Vector2(
		(get_viewport().get_visible_rect().size.x - size.x) / 2,
		(get_viewport().get_visible_rect().size.y - size.y) / 2
	)

func setup(attacker_territory: String, attacker_units: int, attacker_col: Color,
		   defender_territory: String, defender_units: int, defender_col: Color):
	
	attacker_initial_units = attacker_units
	defender_initial_units = defender_units
	attacker_color = attacker_col
	defender_color = defender_col
	
	# Set territory names
	attacker_territory_label.text = attacker_territory
	defender_territory_label.text = defender_territory
	
	# Set initial units
	attacker_initial_label.text = "Initial: %d 🪖" % attacker_units
	defender_initial_label.text = "Initial: %d 🪖" % defender_units
	
	# Apply player colors to panels
	var attacker_style = StyleBoxFlat.new()
	attacker_style.bg_color = Color(attacker_col, 0.8)  # Semi-transparent
	attacker_style.border_color = attacker_col.darkened(0.3)
	attacker_style.border_width_left = 3
	attacker_style.border_width_right = 3
	attacker_style.border_width_top = 3
	attacker_style.border_width_bottom = 3
	attacker_style.corner_radius_top_left = 8
	attacker_style.corner_radius_top_right = 8
	attacker_style.corner_radius_bottom_left = 8
	attacker_style.corner_radius_bottom_right = 8
	attacker_panel.add_theme_stylebox_override("panel", attacker_style)
	
	var defender_style = StyleBoxFlat.new()
	defender_style.bg_color = Color(defender_col, 0.8)  # Semi-transparent
	defender_style.border_color = defender_col.darkened(0.3)
	defender_style.border_width_left = 3
	defender_style.border_width_right = 3
	defender_style.border_width_top = 3
	defender_style.border_width_bottom = 3
	defender_style.corner_radius_top_left = 8
	defender_style.corner_radius_top_right = 8
	defender_style.corner_radius_bottom_left = 8
	defender_style.corner_radius_bottom_right = 8
	defender_panel.add_theme_stylebox_override("panel", defender_style)
	
	# Setup SpinBoxes
	attacker_remaining_input.min_value = 0
	attacker_remaining_input.max_value = attacker_units
	attacker_remaining_input.value = attacker_units
	attacker_remaining_input.step = 1
	attacker_remaining_input.allow_greater = false
	attacker_remaining_input.allow_lesser = false
	
	defender_remaining_input.min_value = 0
	defender_remaining_input.max_value = defender_units
	defender_remaining_input.value = defender_units
	defender_remaining_input.step = 1
	defender_remaining_input.allow_greater = false
	defender_remaining_input.allow_lesser = false
	
	_validate_inputs(0)
	show()

func _validate_inputs(_value):
	# Ensure at least one side loses units
	var attacker_remaining = int(attacker_remaining_input.value)
	var defender_remaining = int(defender_remaining_input.value)
	
	var attacker_losses = attacker_initial_units - attacker_remaining
	var defender_losses = defender_initial_units - defender_remaining
	
	# Disable confirm if no losses or invalid values
	confirm_button.disabled = (attacker_losses == 0 and defender_losses == 0) or \
							   attacker_remaining > attacker_initial_units or \
							   defender_remaining > defender_initial_units or \
							   attacker_remaining < 0 or \
							   defender_remaining < 0

func _on_confirm_pressed():
	var attacker_remaining = int(attacker_remaining_input.value)
	var defender_remaining = int(defender_remaining_input.value)
	
	resolution_confirmed.emit(attacker_remaining, defender_remaining)
	queue_free()
