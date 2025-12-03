extends Node

## BlastEffectPool
## Manages muzzle blast effect instances to reduce instantiation overhead
## Optimized for low-spec performance with object pooling

const MAX_EFFECTS: int = 10
const EFFECT_SCENE: String = "res://Scenes/Effects/BlastEffect.tscn"

var effect_scene: PackedScene
var effect_pool: Array[GPUParticles3D] = []
var active_effects: Array[GPUParticles3D] = []

func _ready() -> void:
	# Preload effect scene
	effect_scene = load(EFFECT_SCENE)
	
	# Pre-instantiate pool of effects
	for i in range(3):
		var effect = effect_scene.instantiate() as GPUParticles3D
		effect.visible = false
		effect.emitting = false
		add_child(effect)
		effect_pool.append(effect)
	
	print("BlastEffectPool: Initialized with %d pooled effects" % effect_pool.size())

func spawn_effect(position: Vector3, direction: Vector3) -> void:
	"""Spawn a muzzle blast effect at the given position facing the direction"""
	
	# Check active effect limit - force cleanup oldest effect
	if active_effects.size() >= MAX_EFFECTS:
		var oldest_effect = active_effects[0]
		return_effect(oldest_effect)
	
	# Get effect from pool
	var effect: GPUParticles3D
	if effect_pool.size() > 0:
		effect = effect_pool.pop_back()
	else:
		# Pool exhausted, create new one
		effect = effect_scene.instantiate() as GPUParticles3D
		add_child(effect)
		print("BlastEffectPool: Pool exhausted, created new effect")
	
	# Validate effect
	if not is_instance_valid(effect):
		push_error("BlastEffectPool: Invalid effect instance!")
		return
	
	# Reset and play effect
	effect.visible = true
	if effect.has_method("reset_light"):
		effect.reset_light()
	effect.play_effect(position, direction)
	active_effects.append(effect)

func return_effect(effect: GPUParticles3D) -> void:
	"""Return an effect to the pool for reuse"""
	if effect == null or not is_instance_valid(effect):
		return
	
	# Deactivate effect and reset light state
	effect.visible = false
	effect.emitting = false
	effect.global_position = Vector3.ZERO
	
	# Ensure particles are fully stopped for clean reuse
	if effect is GPUParticles3D:
		effect.restart()
	
	if effect.has_method("reset_light"):
		effect.reset_light()
	
	# Remove from active list
	var idx = active_effects.find(effect)
	if idx >= 0:
		active_effects.remove_at(idx)
	
	# Return to pool if not already there
	if not effect_pool.has(effect):
		effect_pool.append(effect)
