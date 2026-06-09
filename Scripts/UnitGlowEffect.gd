extends Node

## UnitGlowEffect - Autoload Singleton (combat visual feedback)
##
## Drives the two hit "tells" the combat system needs, by toggling emission on a
## unit's existing StandardMaterial3D surfaces (no material creation overhead):
##   flash(unit, color, times, period) - blink the colour N times (light hits)
##   hold(unit, color, duration)       - steady colour for duration (kills / incapacitation)
## clear(unit) restores the original emission immediately (call on despawn).

const GLOW_ENERGY := 6.0  # emission_energy_multiplier while glowing

# unit_id -> Array[Dictionary]  original emission state per affected material
var _originals: Dictionary = {}
# unit_id -> Tween  active feedback tween
var _tweens: Dictionary = {}

func flash(unit: Node3D, color: Color, times: int = 3, period: float = 0.18) -> void:
	"""Blink `color` on the unit `times` times, then restore."""
	if not _begin(unit):
		return
	var id := unit.get_instance_id()
	var tw := create_tween()
	for i in range(max(times, 1)):
		tw.tween_callback(_set_glow.bind(id, color))
		tw.tween_interval(period * 0.5)
		tw.tween_callback(_set_base.bind(id))
		tw.tween_interval(period * 0.5)
	tw.tween_callback(_finish.bind(id))
	_tweens[id] = tw

func hold(unit: Node3D, color: Color, duration: float = 7.0) -> void:
	"""Hold a steady `color` glow on the unit for `duration`, then restore."""
	if not _begin(unit):
		return
	var id := unit.get_instance_id()
	_set_glow(id, color)
	var tw := create_tween()
	tw.tween_interval(max(duration, 0.05))
	tw.tween_callback(_finish.bind(id))
	_tweens[id] = tw

func clear(unit: Node3D) -> void:
	"""Restore original emission immediately and drop tracking."""
	if unit == null or not is_instance_valid(unit):
		return
	_finish(unit.get_instance_id())

# Backwards-compatible alias used by unit pooling.
func cancel_glow(unit: Node3D) -> void:
	clear(unit)

# --- internals --------------------------------------------------------------

func _begin(unit: Node3D) -> bool:
	"""Capture original emission state (once) and cancel any running tween."""
	if unit == null or not is_instance_valid(unit):
		return false
	var id := unit.get_instance_id()
	if _tweens.has(id) and _tweens[id] != null and _tweens[id].is_valid():
		_tweens[id].kill()
		_tweens.erase(id)
		_apply_originals(id)  # snap back to baseline before the new effect
	if not _originals.has(id):
		var states: Array = []
		for mesh in _find_meshes(unit):
			var surfaces: int = mesh.mesh.get_surface_count() if mesh.mesh else 0
			for si in range(surfaces):
				var mat = mesh.get_active_material(si)
				if mat is StandardMaterial3D:
					states.append({
						"material": mat,
						"emission_enabled": mat.emission_enabled,
						"emission": mat.emission,
						"energy": mat.emission_energy_multiplier,
					})
		if states.is_empty():
			return false
		_originals[id] = states
	return true

func _set_glow(id: int, color: Color) -> void:
	if not _originals.has(id):
		return
	for st in _originals[id]:
		var mat = st["material"]
		if is_instance_valid(mat):
			mat.emission_enabled = true
			mat.emission = color
			mat.emission_energy_multiplier = GLOW_ENERGY

func _set_base(id: int) -> void:
	"""Restore baseline emission without dropping the capture (mid-blink off)."""
	_apply_originals(id)

func _apply_originals(id: int) -> void:
	if not _originals.has(id):
		return
	for st in _originals[id]:
		var mat = st["material"]
		if is_instance_valid(mat):
			mat.emission_enabled = st["emission_enabled"]
			mat.emission = st["emission"]
			mat.emission_energy_multiplier = st["energy"]

func _finish(id: int) -> void:
	_apply_originals(id)
	_originals.erase(id)
	if _tweens.has(id):
		if _tweens[id] != null and _tweens[id].is_valid():
			_tweens[id].kill()
		_tweens.erase(id)

func _find_meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_find_meshes(child))
	return out
