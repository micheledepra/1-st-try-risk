extends Node

## TerritoryTooltipManager
## Displays a tooltip with territory information when hovering over territories
## Features:
## - Cursor-following positioning (bottom-right of cursor)
## - Automatic edge detection and offset adjustment
## - Player color border matching territory owner
## - Semi-transparent black background

# UI Components
var tooltip_panel: PanelContainer
var continent_label: Label
var territory_label: Label
var owner_label: Label
var army_label: Label

# References
var input_manager: Node
var game_manager: Node
var map: Node3D

# State
var currently_hovered: String = ""
var is_tooltip_visible: bool = false
var fade_tween: Tween

# Constants
const TOOLTIP_OFFSET = Vector2(20, 20)  # Bottom-right of cursor
const TOOLTIP_PADDING = 15
const EDGE_MARGIN = 10  # Minimum distance from screen edges
const BORDER_WIDTH = 3
const FADE_IN_DURATION = 0.15  # Seconds
const FADE_OUT_DURATION = 0.1  # Seconds

func _ready():
	# Get references
	map = get_parent()
	input_manager = map.get_node_or_null("TerritoryInputManager")
	game_manager = get_node("/root/GameManager")
	
	if not input_manager:
		push_error("TerritoryTooltipManager: TerritoryInputManager not found!")
		return
	
	if not game_manager:
		push_error("TerritoryTooltipManager: GameManager not found!")
		return
	
	print("TerritoryTooltipManager: Found input_manager and game_manager")
	
	# Create tooltip UI first
	call_deferred("_create_tooltip_ui")
	
	# Wait for input system to be ready
	if input_manager.has_signal("input_system_ready"):
		input_manager.input_system_ready.connect(_on_input_system_ready)
		print("TerritoryTooltipManager: Waiting for input_system_ready signal")
	else:
		call_deferred("_connect_signals")

func _on_input_system_ready():
	print("TerritoryTooltipManager: Input system ready, connecting signals")
	_connect_signals()

func _connect_signals():
	# Connect to hover signals
	if input_manager.territory_hovered.is_connected(_on_territory_hovered):
		print("TerritoryTooltipManager: Already connected to signals")
		return  # Already connected
	
	input_manager.territory_hovered.connect(_on_territory_hovered)
	input_manager.territory_unhovered.connect(_on_territory_unhovered)
	
	print("TerritoryTooltipManager: Successfully connected to territory_hovered and territory_unhovered signals")

func _create_tooltip_ui():
	print("TerritoryTooltipManager: Creating tooltip UI")
	
	# Create main panel container
	tooltip_panel = PanelContainer.new()
	tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_panel.visible = false
	tooltip_panel.modulate = Color(1, 1, 1, 0)  # Start fully transparent
	tooltip_panel.z_index = 100  # Ensure it's on top
	
	# Create and configure the StyleBox for the panel
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.0, 0.0, 0.0, 0.85)  # Semi-transparent black
	style_box.border_width_left = BORDER_WIDTH
	style_box.border_width_right = BORDER_WIDTH
	style_box.border_width_top = BORDER_WIDTH
	style_box.border_width_bottom = BORDER_WIDTH
	style_box.border_color = Color.WHITE  # Default, will be updated per territory
	style_box.corner_radius_top_left = 8
	style_box.corner_radius_top_right = 8
	style_box.corner_radius_bottom_left = 8
	style_box.corner_radius_bottom_right = 8
	
	tooltip_panel.add_theme_stylebox_override("panel", style_box)
	
	# Create margin container for internal padding
	var margin_container = MarginContainer.new()
	margin_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin_container.add_theme_constant_override("margin_left", TOOLTIP_PADDING)
	margin_container.add_theme_constant_override("margin_right", TOOLTIP_PADDING)
	margin_container.add_theme_constant_override("margin_top", TOOLTIP_PADDING)
	margin_container.add_theme_constant_override("margin_bottom", TOOLTIP_PADDING)
	tooltip_panel.add_child(margin_container)
	
	# Create vertical box container for layout
	var vbox = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 8)
	margin_container.add_child(vbox)
	
	# Continent label (medium size, centered)
	continent_label = Label.new()
	continent_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	continent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	continent_label.add_theme_font_size_override("font_size", 20)
	continent_label.add_theme_color_override("font_color", Color.WHITE)
	continent_label.add_theme_color_override("font_outline_color", Color.BLACK)
	continent_label.add_theme_constant_override("outline_size", 2)
	vbox.add_child(continent_label)
	
	# Territory label (centered)
	territory_label = Label.new()
	territory_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	territory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	territory_label.add_theme_font_size_override("font_size", 16)
	territory_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	territory_label.add_theme_color_override("font_outline_color", Color.BLACK)
	territory_label.add_theme_constant_override("outline_size", 1)
	vbox.add_child(territory_label)
	
	# Horizontal separator
	var separator = HSeparator.new()
	separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var separator_style = StyleBoxFlat.new()
	separator_style.bg_color = Color(0.5, 0.5, 0.5, 0.8)
	separator_style.content_margin_top = 0
	separator_style.content_margin_bottom = 0
	separator.add_theme_stylebox_override("separator", separator_style)
	separator.add_theme_constant_override("separation", 5)
	vbox.add_child(separator)
	
	# Owner label (left-aligned)
	owner_label = Label.new()
	owner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	owner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	owner_label.add_theme_font_size_override("font_size", 14)
	owner_label.add_theme_color_override("font_color", Color.WHITE)
	owner_label.add_theme_color_override("font_outline_color", Color.BLACK)
	owner_label.add_theme_constant_override("outline_size", 1)
	vbox.add_child(owner_label)
	
	# Army label (left-aligned)
	army_label = Label.new()
	army_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	army_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	army_label.add_theme_font_size_override("font_size", 14)
	army_label.add_theme_color_override("font_color", Color.WHITE)
	army_label.add_theme_color_override("font_outline_color", Color.BLACK)
	army_label.add_theme_constant_override("outline_size", 1)
	vbox.add_child(army_label)
	
	# Add tooltip to the scene tree (under CanvasLayer for proper layering)
	var canvas_layer = map.get_node_or_null("CanvasLayer")
	if canvas_layer:
		canvas_layer.add_child(tooltip_panel)
		print("TerritoryTooltipManager: Tooltip added to CanvasLayer")
	else:
		# Fallback: add directly to map
		map.add_child(tooltip_panel)
		push_warning("TerritoryTooltipManager: CanvasLayer not found, adding tooltip directly to map")
	
	# Connect signals after UI is created
	call_deferred("_connect_signals")

func _process(_delta: float):
	if is_tooltip_visible and tooltip_panel.visible:
		_update_tooltip_position()

func _update_tooltip_position():
	# Get mouse position
	var mouse_pos = get_viewport().get_mouse_position()
	
	# Calculate desired position (bottom-right of cursor)
	var desired_pos = mouse_pos + TOOLTIP_OFFSET
	
	# Get viewport size and tooltip size
	var viewport_size = get_viewport().get_visible_rect().size
	var tooltip_size = tooltip_panel.size
	
	# Adjust position to keep tooltip within screen bounds
	var final_pos = desired_pos
	
	# Check right edge
	if desired_pos.x + tooltip_size.x > viewport_size.x - EDGE_MARGIN:
		# Move to left of cursor
		final_pos.x = mouse_pos.x - tooltip_size.x - TOOLTIP_OFFSET.x
	
	# Check bottom edge
	if desired_pos.y + tooltip_size.y > viewport_size.y - EDGE_MARGIN:
		# Move above cursor
		final_pos.y = mouse_pos.y - tooltip_size.y - TOOLTIP_OFFSET.y
	
	# Check left edge (in case tooltip is now off-screen to the left)
	if final_pos.x < EDGE_MARGIN:
		final_pos.x = EDGE_MARGIN
	
	# Check top edge (in case tooltip is now off-screen at the top)
	if final_pos.y < EDGE_MARGIN:
		final_pos.y = EDGE_MARGIN
	
	tooltip_panel.position = final_pos

func _on_territory_hovered(territory_name: String):
	print("TerritoryTooltipManager: Territory hovered - ", territory_name)
	currently_hovered = territory_name
	_update_tooltip_data(territory_name)
	_fade_in_tooltip()

func _on_territory_unhovered(territory_name: String):
	print("TerritoryTooltipManager: Territory unhovered - ", territory_name)
	# Only hide if this is the currently displayed territory
	if currently_hovered == territory_name:
		_fade_out_tooltip()
		currently_hovered = ""

func _fade_in_tooltip():
	# Cancel any existing fade animation
	if fade_tween and fade_tween.is_valid():
		fade_tween.kill()
	
	# Make tooltip visible
	tooltip_panel.visible = true
	is_tooltip_visible = true
	
	# Animate fade in
	fade_tween = create_tween()
	fade_tween.set_ease(Tween.EASE_OUT)
	fade_tween.set_trans(Tween.TRANS_CUBIC)
	fade_tween.tween_property(tooltip_panel, "modulate:a", 1.0, FADE_IN_DURATION)

func _fade_out_tooltip():
	# Cancel any existing fade animation
	if fade_tween and fade_tween.is_valid():
		fade_tween.kill()
	
	# Animate fade out
	fade_tween = create_tween()
	fade_tween.set_ease(Tween.EASE_IN)
	fade_tween.set_trans(Tween.TRANS_CUBIC)
	fade_tween.tween_property(tooltip_panel, "modulate:a", 0.0, FADE_OUT_DURATION)
	
	# Hide after fade completes
	fade_tween.finished.connect(func():
		tooltip_panel.visible = false
		is_tooltip_visible = false
	)

func _update_tooltip_data(territory_name: String):
	# Get territory data
	var continent = game_manager.map_data.get(territory_name, {}).get("continent", "Unknown")
	var territory_owner = game_manager.get_territory_owner(territory_name)
	var armies = game_manager.get_territory_armies(territory_name)

	# Format continent name (replace underscores with spaces, capitalize)
	var continent_formatted = _format_name(continent)

	# Format territory name (replace underscores with spaces, capitalize)
	var territory_formatted = _format_name(territory_name)

	# Update labels
	continent_label.text = continent_formatted
	territory_label.text = territory_formatted

	if territory_owner:
		owner_label.text = "Owner: " + territory_owner.player_name
		army_label.text = "Armies: " + str(armies)

		# Update border color to match player color
		var style_box = tooltip_panel.get_theme_stylebox("panel") as StyleBoxFlat
		if style_box:
			style_box.border_color = territory_owner.color
	else:
		owner_label.text = "Owner: None"
		army_label.text = "Armies: " + str(armies)

		# Default white border if no owner
		var style_box = tooltip_panel.get_theme_stylebox("panel") as StyleBoxFlat
		if style_box:
			style_box.border_color = Color.WHITE

func _format_name(input_name: String) -> String:
	# Replace underscores with spaces
	var formatted = input_name.replace("_", " ")
	
	# Capitalize each word
	var words = formatted.split(" ")
	var capitalized_words = []
	for word in words:
		if word.length() > 0:
			capitalized_words.append(word.capitalize())
	
	return " ".join(capitalized_words)
