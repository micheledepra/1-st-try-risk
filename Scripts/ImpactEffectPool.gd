extends Node

## ImpactEffectPool - pools the unified ImpactEffect (terrain / unit / airburst).
## spawn_effect(position, color, with_light, unit_scale, big).

const EFFECT_SCENE: String = "res://Scenes/Effects/ImpactEffect.tscn"
const MAX_EFFECTS: int = 64
const PRE_INSTANTIATE: int = 12

var effect_scene: PackedScene
var pool: Array[GPUParticles3D] = []
var active: Array[GPUParticles3D] = []

func _ready() -> void:
	effect_scene = load(EFFECT_SCENE)
	for i in range(PRE_INSTANTIATE):
		var e := effect_scene.instantiate() as GPUParticles3D
		e.visible = false
		add_child(e)
		pool.append(e)

func spawn_effect(position: Vector3, color := Color.WHITE, with_light := true, unit_scale: float = 1.0, big := false) -> void:
	if active.size() >= MAX_EFFECTS:
		return_effect(active[0])

	var e: GPUParticles3D
	if pool.size() > 0:
		e = pool.pop_back()
	else:
		e = effect_scene.instantiate() as GPUParticles3D
		add_child(e)

	if not is_instance_valid(e):
		return

	e.visible = true
	e.reset_light()
	e.play_effect(position, color, with_light, unit_scale, big)
	active.append(e)

func return_effect(effect: GPUParticles3D) -> void:
	if effect == null or not is_instance_valid(effect):
		return
	effect.is_playing = false
	effect.emitting = false
	effect.visible = false
	effect.global_position = Vector3.ZERO
	effect.reset_light()
	var idx := active.find(effect)
	if idx >= 0:
		active.remove_at(idx)
	if not pool.has(effect):
		pool.append(effect)
