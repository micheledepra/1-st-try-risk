extends Node3D

## AA Blast effect combining radial impact burst + 3x scaled blast effect
## Triggered by AA bullets on: unit area entry, terrain collision, or timer expiration
## Optimized for low-spec performance

var lifetime_timer: float = 0.0
var is_playing: bool = false
const EFFECT_DURATION: float = 2.0  # Total effect lifetime (matches particle durations)
const LIGHT_ENERGY: float = 35.0  # Blast light energy (3x BlastEffect)
const LIGHT_FADE_DURATION: float =0.450  # Slightly longer flash for larger blast

@onready var impact_particles: GPUParticles3D = $ImpactParticles
@onready var blast_particles: GPUParticles3D = $BlastParticles
@onready var blast_light: OmniLight3D = $BlastLight

var light_cleanup_timer: SceneTreeTimer = null

func _ready() -> void:
	# Ensure particles are set to one-shot and not emitting initially
	if impact_particles:
		impact_particles.one_shot = true
		impact_particles.emitting = false
	if blast_particles:
		blast_particles.one_shot = true
		blast_particles.emitting = false

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

func play_effect(position: Vector3, enable_light := true) -> void:
	"""Play the AA blast effect at the given position
	@param position: Explosion position
	@param enable_light: If true, spawns light effect (for terrain/mid-air). If false, only particles (for units)"""
	global_position = position
	
	# Reset and trigger impact particles (radial 360° burst)
	if impact_particles:
		impact_particles.emitting = false
		impact_particles.restart()
		impact_particles.emitting = true
	
	# Reset and trigger blast particles (3x scaled smoke/debris)
	if blast_particles:
		blast_particles.emitting = false
		blast_particles.restart()
		blast_particles.emitting = true
	
	is_playing = true
	
	# Reset and enable blast light only if requested
	if blast_light and enable_light:
		blast_light.light_energy = LIGHT_ENERGY
		blast_light.visible = true
		
		# Safety timer: force light cleanup after max duration
		if light_cleanup_timer != null:
			if light_cleanup_timer.timeout.is_connected(_force_light_cleanup):
				light_cleanup_timer.timeout.disconnect(_force_light_cleanup)
		light_cleanup_timer = get_tree().create_timer(LIGHT_FADE_DURATION * 2.0)
		light_cleanup_timer.timeout.connect(_force_light_cleanup)
	elif blast_light:
		# Ensure light stays off for unit hits
		blast_light.visible = false
	
	lifetime_timer = 0.0

func _process(delta: float) -> void:
	if is_playing:
		lifetime_timer += delta
		
		# Fade out blast light with exponential curve
		if blast_light and blast_light.visible:
			var fade_progress = lifetime_timer / LIGHT_FADE_DURATION
			# Exponential fade: energy decreases exponentially
			blast_light.light_energy = LIGHT_ENERGY * exp(-6.0 * fade_progress)
			if fade_progress >= 1.0:
				blast_light.visible = false
		
		# Return to pool after effect duration
		if lifetime_timer >= EFFECT_DURATION:
			is_playing = false
			AABlastEffectPool.return_effect(self)

func _force_light_cleanup() -> void:
	"""Force cleanup of light after max lifetime (safety mechanism)"""
	if blast_light and blast_light.visible:
		blast_light.visible = false
		blast_light.light_energy = 0.0
	light_cleanup_timer = null
