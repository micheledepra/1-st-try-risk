extends Node3D

# Configuration
@export var raise_height: float = 3  # How much to raise the child
@export var animation_duration: float = 0.15  # Duration of the raise/lower animation in seconds
@export var use_smooth_animation: bool = true  # Enable smooth animation

# Track which child is currently hovered
var hovered_child: Node3D = null
# Store original positions of children
var original_positions: Dictionary = {}
# Track active tweens per child
var active_tweens: Dictionary = {}

func _ready() -> void:
	# Store original positions of all Node3D children
	for child in get_children():
		if child is Node3D:
			original_positions[child] = child.position
			setup_child_signals(child)

func setup_child_signals(child: Node3D) -> void:
	# Find Area3D in the child (could be nested)
	var area = find_area3d(child)
	if area:
		# Connect mouse enter/exit signals
		if not area.mouse_entered.is_connected(_on_child_mouse_entered):
			area.mouse_entered.connect(_on_child_mouse_entered.bind(child))
		if not area.mouse_exited.is_connected(_on_child_mouse_exited):
			area.mouse_exited.connect(_on_child_mouse_exited.bind(child))
		
		# Enable mouse detection
		area.input_ray_pickable = true
	else:
		push_warning("No Area3D found in child: " + child.name)

func find_area3d(node: Node) -> Area3D:
	# Recursively search for Area3D in child and its descendants
	# Skip StaticBody3D nodes (used for physics, not input)
	if node is StaticBody3D:
		return null
	
	if node is Area3D:
		return node
	
	for child in node.get_children():
		var result = find_area3d(child)
		if result:
			return result
	
	return null

func _on_child_mouse_entered(child: Node3D) -> void:
	hovered_child = child
	
	if not original_positions.has(child):
		return
	
	# Kill existing tween if any
	if active_tweens.has(child) and active_tweens[child]:
		active_tweens[child].kill()
	
	if not use_smooth_animation:
		# Instant raise
		child.position = original_positions[child] + Vector3(0, raise_height, 0)
	else:
		# Create tween for smooth animation
		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(child, "position", original_positions[child] + Vector3(0, raise_height, 0), animation_duration)
		active_tweens[child] = tween

func _on_child_mouse_exited(child: Node3D) -> void:
	if hovered_child == child:
		hovered_child = null
	
	if not original_positions.has(child):
		return
	
	# Kill existing tween if any
	if active_tweens.has(child) and active_tweens[child]:
		active_tweens[child].kill()
	
	if not use_smooth_animation:
		# Instant lower
		child.position = original_positions[child]
	else:
		# Create tween for smooth animation
		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(child, "position", original_positions[child], animation_duration)
		active_tweens[child] = tween

# Optional: Handle dynamically added children
func _on_child_entered_tree(node: Node) -> void:
	if node is Node3D and node.get_parent() == self:
		original_positions[node] = node.position
		setup_child_signals(node)

# Call this if you need to refresh children (e.g., after adding/removing)
func refresh_children() -> void:
	# Clear old tweens
	for tween in active_tweens.values():
		if tween:
			tween.kill()
	active_tweens.clear()
	
	original_positions.clear()
	for child in get_children():
		if child is Node3D:
			original_positions[child] = child.position
			setup_child_signals(child)
