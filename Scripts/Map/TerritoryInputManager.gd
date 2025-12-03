extends Node

## TerritoryInputManager
## Responsibility: Handle ALL input interactions with territories
## - Mouse clicks
## - Mouse hover enter/exit detection
## - Connecting Area3D signals
## - Emitting territory interaction signals

# Signals - Territory interactions
signal territory_clicked(territory_name: String, ctrl_pressed: bool)
signal territory_right_clicked(territory_name: String, ctrl_pressed: bool)
signal territory_hovered(territory_name: String)
signal territory_unhovered(territory_name: String)
signal input_system_ready  # Emitted when setup is complete

# State tracking
var territories_cache: Dictionary = {}  # territory_name -> Node3D reference
var hover_states: Dictionary = {}  # territory_name -> bool (prevents duplicate hover events)
var animating_territories: Dictionary = {}  # territory_name -> bool (prevents animation overlap)
var original_positions: Dictionary = {}  # territory_name -> Vector3 (stores original Y positions)

# Animation configuration
@export var drop_distance: float = 0.4  # How far the territory drops
@export var animation_duration: float = 0.2  # Total animation time (drop + rise)

func _ready():
	setup_input_system()

func setup_input_system():
	var map = get_parent()
	if not map:
		push_error("TerritoryInputManager: No parent node found!")
		return
	
	var continents_node = map.get_node_or_null("Continents")
	
	if continents_node == null:
		push_error("TerritoryInputManager: No 'Continents' node found in Map!")
		return
	
	var total_territories = 0
	var total_areas = 0
	
	# Process only Continent nodes (direct children of Continents)
	for continent in continents_node.get_children():
		# Skip any non-Node3D children or nodes that don't represent continents
		if not continent is Node3D:
			continue
		
		# Process only territory nodes (direct children of continent)
		for territory in continent.get_children():
			# Only process Node3D children that represent actual territories
			if not territory is Node3D:
				continue
			
			territories_cache[territory.name] = territory
			hover_states[territory.name] = false
			animating_territories[territory.name] = false
			original_positions[territory.name] = territory.position
			
			# Connect all Area3D nodes in this territory
			var areas_connected = _connect_territory_inputs(territory, territory.name)
			total_areas += areas_connected
			total_territories += 1
	
	print("TerritoryInputManager: Connected %d Area3D nodes across %d territories" % [total_areas, total_territories])
	input_system_ready.emit()

func _connect_territory_inputs(territory: Node3D, territory_name: String) -> int:
	# Find ALL Area3D nodes recursively (handles multi-mesh territories)
	var areas = _find_all_area3d_nodes(territory)
	
	for area in areas:
		# Ensure Area3D can receive input events
		area.input_ray_pickable = true
		area.monitoring = true
		area.monitorable = true
		
		# Connect all input signals
		area.mouse_entered.connect(_on_area_mouse_entered.bind(territory_name))
		area.mouse_exited.connect(_on_area_mouse_exited.bind(territory_name))
		area.input_event.connect(_on_area_input_event.bind(territory_name))
	
	# Find ALL StaticBody3D nodes recursively and apply metadata for projectile collision detection
	var static_bodies = _find_all_static_body3d_nodes(territory)
	for static_body in static_bodies:
		static_body.set_meta("territory_name", territory_name)
	
	if areas.size() > 0:
		print("TerritoryInputManager: Connected %d Area3D nodes for '%s'" % [areas.size(), territory_name])
	else:
		push_warning("TerritoryInputManager: No Area3D found in territory '%s'" % territory_name)
	
	if static_bodies.size() > 0:
		print("TerritoryInputManager: Applied metadata to %d StaticBody3D nodes for '%s'" % [static_bodies.size(), territory_name])
	else:
		push_warning("TerritoryInputManager: No StaticBody3D found in territory '%s'" % territory_name)
	
	return areas.size()

func _find_all_area3d_nodes(node: Node) -> Array[Area3D]:
	var areas: Array[Area3D] = []
	for child in node.get_children():
		if child is Area3D:
			areas.append(child)
		else:
			# Recursively check children (Area3D might be nested inside Mesh nodes)
			areas.append_array(_find_all_area3d_nodes(child))
	return areas

func _find_all_static_body3d_nodes(node: Node) -> Array[StaticBody3D]:
	var static_bodies: Array[StaticBody3D] = []
	for child in node.get_children():
		if child is StaticBody3D:
			static_bodies.append(child)
		else:
			# Recursively check children (StaticBody3D might be nested inside Mesh nodes)
			static_bodies.append_array(_find_all_static_body3d_nodes(child))
	return static_bodies

# Cleanup on scene exit
func _exit_tree():
	territories_cache.clear()
	hover_states.clear()
	animating_territories.clear()
	original_positions.clear()

# Input event handlers
func _on_area_mouse_entered(territory_name: String):
	if territory_name.is_empty():
		push_warning("TerritoryInputManager: Received hover for empty territory name")
		return
	
	# Only emit signal if this territory wasn't already hovered
	# Prevents duplicate events when territory has multiple Area3D nodes
	if not hover_states.get(territory_name, false):
		hover_states[territory_name] = true
		print("TerritoryInputManager: HOVER ENTER - %s" % territory_name)
		territory_hovered.emit(territory_name)

func _on_area_mouse_exited(territory_name: String):
	if territory_name.is_empty():
		return
	
	# Only emit signal if this territory was hovered
	if hover_states.get(territory_name, false):
		hover_states[territory_name] = false
		print("TerritoryInputManager: HOVER EXIT - %s" % territory_name)
		territory_unhovered.emit(territory_name)

func _on_area_input_event(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int, territory_name: String):
	if territory_name.is_empty():
		return
	
	if event is InputEventMouseButton and event.pressed:
		var ctrl_pressed = event.ctrl_pressed
		
		if event.button_index == MOUSE_BUTTON_LEFT:
			_animate_territory_click(territory_name)
			territory_clicked.emit(territory_name, ctrl_pressed)
			print("TerritoryInputManager: Territory clicked - %s (Ctrl: %s)" % [territory_name, ctrl_pressed])
		
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_animate_territory_click(territory_name)
			territory_right_clicked.emit(territory_name, ctrl_pressed)
			print("TerritoryInputManager: Territory right-clicked - %s (Ctrl: %s)" % [territory_name, ctrl_pressed])

# Animation method - Drop and rise effect on click
func _animate_territory_click(territory_name: String):
	# Skip if already animating
	if animating_territories.get(territory_name, false):
		return
	
	var territory = territories_cache.get(territory_name)
	if not territory:
		return
	
	# Mark as animating
	animating_territories[territory_name] = true
	
	# Get original position
	var original_pos = original_positions.get(territory_name, territory.position)
	var drop_pos = original_pos + Vector3(0, -drop_distance, 0)
	
	# Create tween for drop animation
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	
	# Drop down (first half of animation)
	tween.tween_property(territory, "position", drop_pos, animation_duration * 0.5)
	
	# Rise back up (second half of animation)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(territory, "position", original_pos, animation_duration * 0.5)
	
	# Clear animation flag when done
	tween.finished.connect(func(): animating_territories[territory_name] = false)

# Public API - Query methods
func get_territory_node(territory_name: String) -> Node3D:
	return territories_cache.get(territory_name)

func is_territory_hovered(territory_name: String) -> bool:
	return hover_states.get(territory_name, false)
