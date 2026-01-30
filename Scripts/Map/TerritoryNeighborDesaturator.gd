extends Node

## TerritoryNeighborDesaturator
## Responsibility: Visual feedback on territory hover
## - Highlights the hovered territory (brightness/saturation boost)
## - Desaturates neighboring territories
## - Preserves saturation grading from TerritoryTransparencyManager
## - Uses animated fade transitions
## - Properly synchronized with color system initialization

# Export variables for neighbor desaturation
@export_range(0.0, 1.0) var desaturation_amount: float = 0.5
@export var fade_in_duration: float = 0.2
@export var fade_out_duration: float = 0.15

# Hover highlight for the hovered territory itself
@export_group("Hovered Territory Highlight")
@export_range(0.0, 0.5) var hover_brightness_boost: float = 0.15
@export_range(0.0, 0.5) var hover_saturation_boost: float = 0.1

# References
var input_manager: Node = null
var color_manager: Node = null
var transparency_manager: Node = null

# Initialization state - only process hover events when ready
var is_ready: bool = false

# State tracking
var currently_hovered_territory: String = ""
var desaturated_neighbors: Array[String] = []

# Store material data for hovered territory and neighbors
var territory_material_data: Dictionary = {}
var hovered_territory_data: Array = []

# Active tweens
var active_tweens: Dictionary = {}
var hover_tweens: Array[Tween] = []

func _ready():
	call_deferred("setup_desaturator")

func setup_desaturator():
	var map = get_parent()
	if not map:
		push_error("TerritoryNeighborDesaturator: No parent node found!")
		return
	
	input_manager = map.get_node_or_null("TerritoryInputManager")
	if not input_manager:
		push_error("TerritoryNeighborDesaturator: TerritoryInputManager not found!")
		return
	
	color_manager = map.get_node_or_null("TerritoryColorManager")
	if not color_manager:
		push_error("TerritoryNeighborDesaturator: TerritoryColorManager not found!")
		return
	
	transparency_manager = map.get_node_or_null("TerritoryTransparencyManager")
	if not transparency_manager:
		push_warning("TerritoryNeighborDesaturator: TerritoryTransparencyManager not found, hover effects may not preserve saturation grading")
	
	# Wait for color system to be ready before processing any hover events
	if not color_manager.is_ready:
		print("TerritoryNeighborDesaturator: Waiting for TerritoryColorManager to be ready...")
		await color_manager.color_system_ready
	
	# Also wait for transparency manager if available
	if transparency_manager and not transparency_manager.is_ready:
		print("TerritoryNeighborDesaturator: Waiting for TerritoryTransparencyManager to be ready...")
		await transparency_manager.saturation_system_ready
	
	# Now connect to hover signals - only after systems are ready
	input_manager.territory_hovered.connect(_on_territory_hovered)
	input_manager.territory_unhovered.connect(_on_territory_unhovered)
	
	is_ready = true
	print("TerritoryNeighborDesaturator: Initialized with saturation-aware hover effects")

func _on_territory_hovered(territory_name: String):
	# Guard: only process if system is ready
	if not is_ready:
		return
	
	# Skip if same territory
	if currently_hovered_territory == territory_name:
		return
	
	# Force immediate cleanup of previous state before applying new
	if currently_hovered_territory != "":
		_force_restore_all_immediately()
	
	currently_hovered_territory = territory_name
	
	# Apply highlight to the hovered territory itself
	_apply_hover_highlight(territory_name)
	
	# Get neighbors from map_data
	var neighbors = _get_territory_neighbors(territory_name)
	if neighbors.is_empty():
		return
	
	# Desaturate each neighbor with animation
	for neighbor_name in neighbors:
		if not neighbor_name in desaturated_neighbors:
			_apply_desaturation_animated(neighbor_name)
			desaturated_neighbors.append(neighbor_name)

func _on_territory_unhovered(territory_name: String):
	# Guard: only process if system is ready
	if not is_ready:
		return
	
	if territory_name == currently_hovered_territory:
		_restore_hover_highlight()
		_restore_all_materials_animated()
		currently_hovered_territory = ""

func _get_territory_neighbors(territory_name: String) -> Array:
	if not GameManager or GameManager.map_data.is_empty():
		return []
	var territory_data = GameManager.map_data.get(territory_name, {})
	return territory_data.get("neighbors", [])

## Get the current saturation-graded color for a territory
func _get_saturation_adjusted_color(territory_name: String) -> Color:
	# Use transparency manager's saturation-adjusted color if available
	if transparency_manager and transparency_manager.has_method("get_saturation_adjusted_color"):
		return transparency_manager.get_saturation_adjusted_color(territory_name)
	
	# Fallback: get from material directly
	var territory = color_manager.territories_cache.get(territory_name)
	if territory:
		var meshes = color_manager.find_all_mesh_instances(territory)
		if not meshes.is_empty():
			var mat = meshes[0].get_surface_override_material(0)
			if mat and mat is StandardMaterial3D:
				return mat.albedo_color
	
	# Final fallback
	return Color.GRAY

func _apply_hover_highlight(territory_name: String):
	"""Apply brightness/saturation boost to the hovered territory"""
	if not color_manager:
		return
	
	var territory = color_manager.territories_cache.get(territory_name)
	if not territory:
		return
	
	var meshes = color_manager.find_all_mesh_instances(territory)
	if meshes.is_empty():
		return
	
	# Cancel any existing hover tweens
	for tween in hover_tweens:
		if is_instance_valid(tween):
			tween.kill()
	hover_tweens.clear()
	hovered_territory_data.clear()
	
	for mesh in meshes:
		var original_mat = mesh.get_surface_override_material(0)
		if not original_mat:
			original_mat = mesh.mesh.surface_get_material(0) if mesh.mesh else null
		if not original_mat or not original_mat is StandardMaterial3D:
			continue
		
		# Get current saturation-graded color (preserves army-based saturation)
		var original_color = _get_saturation_adjusted_color(territory_name)
		
		# Calculate highlighted color (boost brightness and saturation)
		var h = original_color.h
		var s = original_color.s
		var v = original_color.v
		var a = original_color.a
		var new_s = clamp(s + hover_saturation_boost, 0.0, 1.0)
		var new_v = clamp(v + hover_brightness_boost, 0.0, 1.0)
		var target_color = Color.from_hsv(h, new_s, new_v, a)
		
		# Clone material for highlight effect
		var highlight_mat: StandardMaterial3D = original_mat.duplicate()
		
		hovered_territory_data.append({
			"mesh": mesh,
			"original_override": mesh.get_surface_override_material(0),
			"highlight_mat": highlight_mat,
			"original_color": original_color,
			"target_color": target_color
		})
		
		mesh.set_surface_override_material(0, highlight_mat)
		
		# Animate to highlighted color
		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_QUAD)
		tween.tween_property(highlight_mat, "albedo_color", target_color, fade_in_duration)
		hover_tweens.append(tween)

func _restore_hover_highlight():
	"""Restore the hovered territory to its saturation-graded color"""
	for tween in hover_tweens:
		if is_instance_valid(tween):
			tween.kill()
	hover_tweens.clear()
	
	for data in hovered_territory_data:
		var mesh: MeshInstance3D = data["mesh"]
		var original_override = data["original_override"]
		var highlight_mat: StandardMaterial3D = data["highlight_mat"]
		var original_color: Color = data["original_color"]
		
		if not is_instance_valid(mesh):
			continue
		
		if not is_instance_valid(highlight_mat):
			mesh.set_surface_override_material(0, original_override)
			continue
		
		# Animate back to original saturation-graded color
		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_QUAD)
		tween.tween_property(highlight_mat, "albedo_color", original_color, fade_out_duration)
		tween.finished.connect(func():
			if is_instance_valid(mesh):
				mesh.set_surface_override_material(0, original_override)
		)
		hover_tweens.append(tween)
	
	hovered_territory_data.clear()

func _apply_desaturation_animated(territory_name: String):
	"""Apply desaturation to a neighbor territory, preserving saturation grading"""
	if not color_manager:
		return
	
	# Cancel any existing tweens and restore immediately first
	_cancel_tweens_and_restore(territory_name)
	
	# Get territory node
	var territory = color_manager.territories_cache.get(territory_name)
	if not territory:
		return
	
	# Get all mesh instances in territory
	var meshes = color_manager.find_all_mesh_instances(territory)
	if meshes.is_empty():
		return
	
	# Store material data and apply animated desaturation
	var mesh_data: Array = []
	var tweens: Array[Tween] = []
	
	for mesh in meshes:
		# Get current material (could be override or surface material)
		var original_mat = mesh.get_surface_override_material(0)
		if not original_mat:
			original_mat = mesh.mesh.surface_get_material(0) if mesh.mesh else null
		if not original_mat or not original_mat is StandardMaterial3D:
			continue
		
		# Get saturation-graded color (preserves army-based saturation)
		var original_color = _get_saturation_adjusted_color(territory_name)
		
		# Calculate desaturated target color based on the saturation-graded color
		var h = original_color.h
		var s = original_color.s
		var v = original_color.v
		var a = original_color.a
		var new_saturation = s * (1.0 - desaturation_amount)
		var target_color = Color.from_hsv(h, new_saturation, v, a)
		
		# Clone material for this mesh (starts at current color)
		var desaturated_mat: StandardMaterial3D = original_mat.duplicate()
		
		# Store data for restoration
		mesh_data.append({
			"mesh": mesh,
			"original_override": mesh.get_surface_override_material(0),
			"desaturated_mat": desaturated_mat,
			"original_color": original_color,
			"target_color": target_color
		})
		
		# Apply the cloned material as override
		mesh.set_surface_override_material(0, desaturated_mat)
		
		# Animate the color change
		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_QUAD)
		tween.tween_property(desaturated_mat, "albedo_color", target_color, fade_in_duration)
		tweens.append(tween)
	
	territory_material_data[territory_name] = mesh_data
	active_tweens[territory_name] = tweens

func _restore_all_materials_animated():
	"""Restore all territories with fade-out animation"""
	var neighbors_to_restore = desaturated_neighbors.duplicate()
	desaturated_neighbors.clear()
	
	for territory_name in neighbors_to_restore:
		_restore_material_animated(territory_name)

func _restore_material_animated(territory_name: String):
	"""Restore a territory's materials with fade-out animation"""
	if not territory_material_data.has(territory_name):
		return
	
	# Cancel any existing tweens first
	_cancel_tweens(territory_name)
	
	var mesh_data = territory_material_data[territory_name]
	var tweens: Array[Tween] = []
	
	for data in mesh_data:
		var mesh: MeshInstance3D = data["mesh"]
		var desaturated_mat: StandardMaterial3D = data["desaturated_mat"]
		var original_override = data["original_override"]
		var original_color: Color = data["original_color"]
		
		if not is_instance_valid(mesh):
			continue
		
		if not is_instance_valid(desaturated_mat):
			# Material invalid, restore immediately
			mesh.set_surface_override_material(0, original_override)
			continue
		
		# Animate back to original color
		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_QUAD)
		tween.tween_property(desaturated_mat, "albedo_color", original_color, fade_out_duration)
		
		# When animation completes, restore original material override
		tween.finished.connect(_on_restore_complete.bind(mesh, original_override, territory_name))
		tweens.append(tween)
	
	active_tweens[territory_name] = tweens

func _on_restore_complete(mesh: MeshInstance3D, original_override: StandardMaterial3D, territory_name: String):
	"""Called when fade-out animation completes - restore original material"""
	if is_instance_valid(mesh):
		mesh.set_surface_override_material(0, original_override)
	
	# Clean up data for this territory
	_cleanup_territory_data(territory_name)

func _cleanup_territory_data(territory_name: String):
	"""Remove all tracking data for a territory"""
	if active_tweens.has(territory_name):
		var all_done = true
		for tween in active_tweens[territory_name]:
			if is_instance_valid(tween) and tween.is_running():
				all_done = false
				break
		if all_done:
			active_tweens.erase(territory_name)
			territory_material_data.erase(territory_name)

func _cancel_tweens(territory_name: String):
	"""Cancel all active tweens for a territory without restoring"""
	if active_tweens.has(territory_name):
		for tween in active_tweens[territory_name]:
			if is_instance_valid(tween):
				tween.kill()
		active_tweens.erase(territory_name)

func _cancel_tweens_and_restore(territory_name: String):
	"""Cancel tweens AND immediately restore original materials"""
	_cancel_tweens(territory_name)
	_restore_material_immediately(territory_name)

func _restore_material_immediately(territory_name: String):
	"""Immediately restore a territory's materials without animation"""
	if not territory_material_data.has(territory_name):
		return
	
	var mesh_data = territory_material_data[territory_name]
	for data in mesh_data:
		var mesh: MeshInstance3D = data["mesh"]
		var original_override = data["original_override"]
		if is_instance_valid(mesh):
			mesh.set_surface_override_material(0, original_override)
	
	territory_material_data.erase(territory_name)

func _force_restore_all_immediately():
	"""Force immediate restoration of all desaturated territories and hover highlight"""
	# Cancel and restore hover highlight first
	for tween in hover_tweens:
		if is_instance_valid(tween):
			tween.kill()
	hover_tweens.clear()
	
	for data in hovered_territory_data:
		var mesh: MeshInstance3D = data["mesh"]
		var original_override = data["original_override"]
		if is_instance_valid(mesh):
			mesh.set_surface_override_material(0, original_override)
	hovered_territory_data.clear()
	
	# Cancel all neighbor tweens
	for territory_name in active_tweens.keys():
		for tween in active_tweens[territory_name]:
			if is_instance_valid(tween):
				tween.kill()
	active_tweens.clear()
	
	# Restore all neighbor materials immediately
	for territory_name in territory_material_data.keys():
		var mesh_data = territory_material_data[territory_name]
		for data in mesh_data:
			var mesh: MeshInstance3D = data["mesh"]
			var original_override = data["original_override"]
			if is_instance_valid(mesh):
				mesh.set_surface_override_material(0, original_override)
	
	territory_material_data.clear()
	desaturated_neighbors.clear()
