extends Node

## AirImpactEffectPool
## Manages air impact effect instances to reduce instantiation overhead
## Optimized for low-spec performance with object pooling

const MAX_EFFECTS: int = 250
const EFFECT_SCENE: String = "res://Scenes/Effects/AirImpactEffect.tscn"

var effect_scene: PackedScene
var effect_pool: Array[Node3D] = []
var active_effects: Array[Node3D] = []

func _ready() -> void:
	# Preload effect scene
	effect_scene = load(EFFECT_SCENE)
	
	if not effect_scene:
		push_error("AirImpactEffectPool: Failed to load scene at " + EFFECT_SCENE)
		return
	
	# Pre-instantiate pool of effects
	for i in range(10):
		var effect = effect_scene.instantiate() as Node3D
		effect.visible = false
		add_child(effect)
		effect_pool.append(effect)
	
	print("AirImpactEffectPool: Initialized with %d pooled effects" % effect_pool.size())

func spawn_effect(position: Vector3, color: Color = Color.WHITE, enable_light: bool = true) -> void:
	"""Spawn an air impact effect at the given position with the specified color
	@param position: Impact position
	@param color: Tracer color (red or green)
	@param enable_light: If true, spawns light effect (for terrain). If false, only particles (for units)"""
	
	# Check active effect limit - force cleanup oldest effect
	if active_effects.size() >= MAX_EFFECTS:
		var oldest_effect = active_effects[0]
		return_effect(oldest_effect)
	
	# Get effect from pool
	var effect: Node3D
	if effect_pool.size() > 0:
		effect = effect_pool.pop_back()
	else:
		# Pool exhausted, create new one
		effect = effect_scene.instantiate() as Node3D
		add_child(effect)
	
	# Validate effect
	if not is_instance_valid(effect):
		push_error("AirImpactEffectPool: Invalid effect instance!")
		return
	
	# Reset and play effect
	effect.visible = true
	if effect.has_method("reset_light"):
		effect.reset_light()
	if effect.has_method("play_effect"):
		effect.play_effect(position, color, enable_light)
	active_effects.append(effect)

func return_effect(effect: Node3D) -> void:
	"""Return an effect to the pool for reuse"""
	if effect == null or not is_instance_valid(effect):
		return
	
	# Deactivate effect
	effect.visible = false
	effect.global_position = Vector3.ZERO
	
	# Reset particle systems
	var impact_particles = effect.get_node_or_null("ImpactParticles")
	var blast_particles = effect.get_node_or_null("BlastParticles")
	
	if impact_particles:
		impact_particles.emitting = false
		impact_particles.restart()
	if blast_particles:
		blast_particles.emitting = false
		blast_particles.restart()
	
	if effect.has_method("reset_light"):
		effect.reset_light()
	
	# Remove from active list
	var idx = active_effects.find(effect)
	if idx >= 0:
		active_effects.remove_at(idx)
	
	# Return to pool if not already there
	if not effect_pool.has(effect):
		effect_pool.append(effect)
