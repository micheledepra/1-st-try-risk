extends GPUParticles3D

## Simple impact effect for projectile hits
## Optimized for low-spec performance

var lifetime_timer: float = 0.0
var is_playing: bool = false  # Track active state (emitting becomes false after one_shot burst)
const EFFECT_DURATION: float = 2.0  # Total effect lifetime (matches BlastEffect particles)
const LIGHT_ENERGY: float = 3.0  # Blast light energy
const LIGHT_FADE_DURATION: float = 0.1  # Quick 0.1s red flash (blast style)
const MAX_LIGHT_LIFETIME: float = 0.2  # Absolute max light lifetime (safety margin)

var blast_light: OmniLight3D  # Light from child BlastEffect
var blast_effect: GPUParticles3D  # Child BlastEffect particles
var light_cleanup_timer: SceneTreeTimer = null

func _ready() -> void:
	one_shot = true
	emitting = false
	# Get child BlastEffect and its light
	blast_effect = get_node_or_null("BlastEffect")
	if blast_effect:
		blast_light = blast_effect.get_node_or_null("BlastLight")

func reset_light() -> void:
	"""Reset light state for pooled reuse"""
	if blast_light:
		blast_light.light_energy = 0.0
		blast_light.visible = false
		# Cancel any pending cleanup timer
		if light_cleanup_timer != null:
			if light_cleanup_timer.timeout.is_connected(_force_light_cleanup):
				light_cleanup_timer.timeout.disconnect(_force_light_cleanup)
			light_cleanup_timer = null

func play_effect(effect_pos: Vector3, color := Color.WHITE, enable_light := true) -> void:
	"""Play the impact effect at the given position with color
	@param enable_light: If true, spawns light effect (for terrain). If false, only particles (for units with glow)"""
	global_position = effect_pos
	
	# Set particle color for main impact particles
	var material = process_material as ParticleProcessMaterial
	if material:
		material.color = color
	
	# CRITICAL FIX: Reset particle system state to allow re-emission
	emitting = false
	restart()  # Reset GPUParticles3D internal state
	emitting = true
	is_playing = true  # Track that effect is active
	
	# Trigger child BlastEffect particles (synced)
	if blast_effect:
		blast_effect.emitting = false
		blast_effect.restart()
		blast_effect.emitting = true
	
	# Reset and enable blast light only if requested (terrain hits)
	if blast_light and enable_light:
		blast_light.light_energy = LIGHT_ENERGY
		blast_light.visible = true
		
		# Safety timer: force light cleanup after max lifetime
		if light_cleanup_timer != null:
			if light_cleanup_timer.timeout.is_connected(_force_light_cleanup):
				light_cleanup_timer.timeout.disconnect(_force_light_cleanup)
		light_cleanup_timer = get_tree().create_timer(MAX_LIGHT_LIFETIME)
		light_cleanup_timer.timeout.connect(_force_light_cleanup)
	elif blast_light:
		# Ensure light stays off for unit hits
		blast_light.visible = false
	
	lifetime_timer = 0.0

func _process(delta: float) -> void:
	if is_playing:
		lifetime_timer += delta
		
		# Fade out blast light with quick exponential curve (0.1s)
		if blast_light and blast_light.visible:
			var fade_progress = lifetime_timer / LIGHT_FADE_DURATION
			# Exponential fade: energy decreases exponentially (e^(-6*t))
			blast_light.light_energy = LIGHT_ENERGY * exp(-6.0 * fade_progress)
			if fade_progress >= 1.0:
				blast_light.visible = false
		
		if lifetime_timer >= EFFECT_DURATION:
			is_playing = false
			ImpactEffectPool.return_effect(self)

func _force_light_cleanup() -> void:
	"""Force cleanup of light after max lifetime (safety mechanism)"""
	if blast_light and blast_light.visible:
		blast_light.visible = false
		blast_light.light_energy = 0.0
	light_cleanup_timer = null
