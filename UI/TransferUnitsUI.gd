extends Control

## TransferUnitsUI - Modal for transferring units between territories
## Used for: 1) Conquest (attack phase), 2) Fortify (fortify phase)

signal transfer_confirmed(units: int)

@onready var territory_label = %TerritoryLabel
@onready var starting_territory_label = %StartingTerritoryLabel
@onready var info_label = %InfoLabel
@onready var units_slider = %UnitsSlider
@onready var units_input = %UnitsInput
@onready var confirm_button = %ConfirmButton
@onready var transfer_min_button = %TransferMinButton
@onready var transfer_max_button = %TransferMaxButton

var min_units: int
var max_units: int

func _ready():
	confirm_button.pressed.connect(_on_confirm_pressed)
	transfer_min_button.pressed.connect(_on_transfer_min)
	transfer_max_button.pressed.connect(_on_transfer_max)
	units_slider.value_changed.connect(_on_slider_changed)
	units_input.value_changed.connect(_on_input_changed)
	
	# Center the modal
	position = Vector2(
		(get_viewport().get_visible_rect().size.x - size.x) / 2,
		(get_viewport().get_visible_rect().size.y - size.y) / 2
	)

func setup(from_territory: String, to_territory: String, remaining_units: int):
	min_units = 1
	max_units = remaining_units - 1  # Must leave 1 on source territory
	starting_territory_label.text = "From: %s" % from_territory
	territory_label.text = "To: %s" % to_territory
	info_label.text = "Min: %d 🪖 | Max: %d 🪖\n" % [min_units, max_units]
	
	# Setup slider
	units_slider.min_value = min_units
	units_slider.max_value = max_units
	units_slider.value = min_units
	units_slider.step = 1
	units_slider.tick_count = max_units - min_units + 1
	units_slider.ticks_on_borders = true
	
	# Setup input
	units_input.min_value = min_units
	units_input.max_value = max_units
	units_input.value = max_units
	units_input.step = 1
	units_input.allow_greater = false
	units_input.allow_lesser = false
	
	# Update button texts
	transfer_min_button.text = "Min (1)"
	transfer_max_button.text = "Max (%d)" % max_units
	
	show()

func _on_slider_changed(value):
	units_input.value = value

func _on_input_changed(value):
	units_slider.value = value

func _on_transfer_min():
	units_slider.value = min_units
	units_input.value = min_units

func _on_transfer_max():
	units_slider.value = max_units
	units_input.value = max_units

func _on_confirm_pressed():
	var units = int(units_slider.value)
	transfer_confirmed.emit(units)
	queue_free()
