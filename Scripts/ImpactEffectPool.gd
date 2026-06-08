extends Node

## ImpactEffectPool
## Manages impact effect instances to reduce instantiation overhead
## Optimized for low-spec performance with object pooling

const MAX_EFFECTS: int = 250
const EFFECT_SCENE: String = "res://Scenes/Effects/ImpactEffect.tscn"

var effect_scene: PackedScene
var effect_pool: Array[GPUParticles3D] = []
var active_effects: Array[GPUParticles3D] = []

func _ready() -> void:
	# Preload effect scene
	effect_scene = load(EFFECT_SCENE)
	
	# Pre-instantiate pool of effects
	for i in range(15):
		var effect = effect_scene.instantiate() as GPUParticles3D
		effect.visible = false
		effect.emitting = false
		add_child(effect)
		effect_pool.append(effect)
	
	print("ImpactEffectPool: Initialized with %d pooled effects" % effect_pool.size())

func spawn_effect(position: Vector3, color := Color.WHITE, enable_light := true) -> void:
	"""Spawn an impact effect at the given position with the specified color
	@param enable_light: If true, spawns light effect (for terrain). If false, only particles (for units with glow)"""
	
	print("[ImpactEffectPool] spawn_effect() called - position: %s, color: %s, enable_light: %s" % [position, color, enable_light])
	
	# Check active effect limit - force cleanup oldest effect instead of silently failing
	if active_effects.size() >= MAX_EFFECTS:
		print("ImpactEffectPool: MAX_EFFECTS limit reached (%d active), forcing cleanup of oldest effect" % active_effects.size())
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
		print("ImpactEffectPool: Pool exhausted, created new effect (Active: %d, Pool: %d)" % [active_effects.size(), effect_pool.size()])
	
	# Validate effect
	if not is_instance_valid(effect):
		push_error("ImpactEffectPool: Invalid effect instance!")
		return
	
	# Reset and play effect
	effect.visible = true
	if effect.has_method("reset_light"):
		effect.reset_light()
	effect.play_effect(position, color, enable_light)
	active_effects.append(effect)
	
	# Debug: Log pool status periodically (every 5th spawn)
	if active_effects.size() % 5 == 0:
		print("ImpactEffectPool: Status - Active: %d/%d, Pool: %d" % [active_effects.size(), MAX_EFFECTS, effect_pool.size()])

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
		effect.restart()  # Reset particle system internal state
	
	if effect.has_method("reset_light"):
		effect.reset_light()
	
	# Remove from active list
	var idx = active_effects.find(effect)
	if idx >= 0:
		active_effects.remove_at(idx)
	
	# Return to pool if not already there
	if not effect_pool.has(effect):
		effect_pool.append(effect)
