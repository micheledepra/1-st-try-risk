extends Node3D

## Air Impact Effect combining impact burst + blast smoke
## Triggered by air projectiles on unit area entry or terrain collision
## Color matches tracer color (red or green)

var lifetime_timer: float = 0.0
var is_playing: bool = false
const EFFECT_DURATION: float = 2.0
const LIGHT_ENERGY: float = 7.0
const LIGHT_FADE_DURATION: float = 0.15

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

func play_effect(spawn_position: Vector3, color: Color = Color.WHITE, enable_light: bool = true) -> void:
	"""Play the air impact effect at the given position with tracer color
	@param spawn_position: Impact position
	@param color: Tracer color (red or green)
	@param enable_light: If true, spawns light effect (for terrain). If false, only particles (for units)"""
	global_position = spawn_position
	
	# Set particle colors to match tracer
	if impact_particles and impact_particles.process_material:
		var impact_mat = impact_particles.process_material as ParticleProcessMaterial
		if impact_mat:
			impact_mat.color = color
	
	if blast_particles and blast_particles.process_material:
		var blast_mat = blast_particles.process_material as ParticleProcessMaterial
		if blast_mat:
			# Smoke is slightly tinted with tracer color
			blast_mat.color = Color(
				lerp(0.5, color.r, 0.3),
				lerp(0.5, color.g, 0.3),
				lerp(0.5, color.b, 0.3),
				1.0
			)
	
	# Reset and trigger impact particles (radial burst)
	if impact_particles:
		impact_particles.emitting = false
		impact_particles.restart()
		impact_particles.emitting = true
	
	# Reset and trigger blast particles (smoke/debris)
	if blast_particles:
		blast_particles.emitting = false
		blast_particles.restart()
		blast_particles.emitting = true
	
	is_playing = true
	
	# Reset and enable blast light only if requested
	if blast_light and enable_light:
		blast_light.light_color = color
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
			var pool = get_node_or_null("/root/AirImpactEffectPool")
			if pool:
				pool.return_effect(self)

func _force_light_cleanup() -> void:
	"""Force cleanup of light after max lifetime (safety mechanism)"""
	if blast_light and blast_light.visible:
		blast_light.visible = false
		blast_light.light_energy = 0.0
	light_cleanup_timer = null
