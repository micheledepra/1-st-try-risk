extends Node

## BlastEffectPool - pools the unified muzzle BlastEffect.
## spawn_effect(position, direction, ptype, unit_scale): ptype is a
## UnitCombatState.PType; the effect sizes itself by type + unit scale.

const BLAST_SCENE: String = "res://Scenes/Effects/BlastEffect.tscn"
const MAX_EFFECTS: int = 24
const PRE_INSTANTIATE: int = 8

var blast_scene: PackedScene
var pool: Array[GPUParticles3D] = []
var active: Array[GPUParticles3D] = []

func _ready() -> void:
	blast_scene = load(BLAST_SCENE)
	for i in range(PRE_INSTANTIATE):
		var e := blast_scene.instantiate() as GPUParticles3D
		e.visible = false
		add_child(e)
		pool.append(e)

func spawn_effect(position: Vector3, direction: Vector3, ptype: int = 0, unit_scale: float = 1.0) -> void:
	if active.size() >= MAX_EFFECTS:
		return_effect(active[0])

	var e: GPUParticles3D
	if pool.size() > 0:
		e = pool.pop_back()
	else:
		e = blast_scene.instantiate() as GPUParticles3D
		add_child(e)

	if not is_instance_valid(e):
		return

	e.visible = true
	e.reset_state()
	e.play_effect(position, direction, ptype, unit_scale)
	active.append(e)

func return_effect(effect: GPUParticles3D) -> void:
	if effect == null or not is_instance_valid(effect):
		return
	effect.is_playing = false
	effect.emitting = false
	effect.visible = false
	effect.reset_state()
	var idx := active.find(effect)
	if idx >= 0:
		active.remove_at(idx)
	if not pool.has(effect):
		pool.append(effect)
