extends Node

## TerritoryInputManager
## Responsibility: Handle ALL input interactions with territories
## - Mouse clicks
## - Mouse hover enter/exit detection
## - Connecting Area3D signals
## - Emitting territory interaction signals

# Signals - Territory interactions
signal territory_clicked(territory_name: String)
signal territory_hovered(territory_name: String)
signal territory_unhovered(territory_name: String)

# State tracking
var territories_cache: Dictionary = {}  # territory_name -> Node3D reference
var hover_states: Dictionary = {}  # territory_name -> bool (prevents duplicate hover events)

func _ready():
	call_deferred("setup_input_system")

func setup_input_system():
	var map = get_parent()
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
			
			# Connect all Area3D nodes in this territory
			var areas_connected = _connect_territory_inputs(territory, territory.name)
			total_areas += areas_connected
			total_territories += 1
	
	print("TerritoryInputManager: Connected %d Area3D nodes across %d territories" % [total_areas, total_territories])

func _connect_territory_inputs(territory: Node3D, territory_name: String) -> int:
	# Find ALL Area3D nodes recursively (handles multi-mesh territories)
	var areas = _find_all_area3d_nodes(territory)
	
	for area in areas:
		# Connect all input signals
		area.mouse_entered.connect(_on_area_mouse_entered.bind(territory_name))
		area.mouse_exited.connect(_on_area_mouse_exited.bind(territory_name))
		area.input_event.connect(_on_area_input_event.bind(territory_name))
	
	if areas.size() > 0:
		print("TerritoryInputManager: Connected %d Area3D nodes for '%s'" % [areas.size(), territory_name])
	else:
		push_warning("TerritoryInputManager: No Area3D found in territory '%s'" % territory_name)
	
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

# Input event handlers
func _on_area_mouse_entered(territory_name: String):
	# Only emit signal if this territory wasn't already hovered
	# Prevents duplicate events when territory has multiple Area3D nodes
	if not hover_states.get(territory_name, false):
		hover_states[territory_name] = true
		territory_hovered.emit(territory_name)

func _on_area_mouse_exited(territory_name: String):
	# Only emit signal if this territory was hovered
	if hover_states.get(territory_name, false):
		hover_states[territory_name] = false
		territory_unhovered.emit(territory_name)

func _on_area_input_event(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int, territory_name: String):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			territory_clicked.emit(territory_name)
			print("TerritoryInputManager: Territory clicked - %s" % territory_name)

# Public API - Query methods
func get_territory_node(territory_name: String) -> Node3D:
	return territories_cache.get(territory_name)

func is_territory_hovered(territory_name: String) -> bool:
	return hover_states.get(territory_name, false)
