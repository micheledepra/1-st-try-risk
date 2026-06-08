extends GPUParticles3D

## Muzzle blast effect for projectile firing
## Creates a quick red flash with dissipating smoke particles
## Optimized for low-spec performance

var lifetime_timer: float = 0.0
var is_playing: bool = false
const EFFECT_DURATION: float = 2.0  # Total effect lifetime
const LIGHT_ENERGY: float = 12.0  # Initial light brightness (muzzle flash)
const LIGHT_FADE_DURATION: float = 0.3  # Orange/red light flash, slow gentle fade
const FLASH_DURATION: float = 0.05  # Bright muzzle flash sprite visible window (very quick)

var blast_light: OmniLight3D
var muzzle_flash: MeshInstance3D  # Bright forward flash sprite at the barrel tip
var fireball: GPUParticles3D  # Independent fireball burst (~0.35s) around the muzzle
var light_cleanup_timer: SceneTreeTimer = null

func _ready() -> void:
	one_shot = true
	emitting = false
	blast_light = get_node_or_null("BlastLight")
	muzzle_flash = get_node_or_null("MuzzleFlash")
	fireball = get_node_or_null("Fireball")
	if muzzle_flash:
		muzzle_flash.visible = false

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
	if muzzle_flash:
		muzzle_flash.visible = false

func play_effect(spawn_position: Vector3, direction: Vector3) -> void:
	"""Play the muzzle blast effect at the given position facing the direction
	@param spawn_position: Spawn position (barrel tip)
	@param direction: Firing direction (for particle emission orientation)"""
	global_position = spawn_position

	# Orient particles to emit in firing direction
	if direction.length() > 0.001:
		look_at(spawn_position + direction, Vector3.UP)
	
	# CRITICAL FIX: Reset particle system state to allow re-emission
	emitting = false
	restart()  # Reset GPUParticles3D internal state
	emitting = true
	is_playing = true

	# Pop the bright muzzle flash sprite (hidden again after FLASH_DURATION)
	if muzzle_flash:
		muzzle_flash.visible = true

	# Trigger the independent fireball burst (quick, bigger than the smoke, then fades)
	if fireball:
		fireball.emitting = false
		fireball.restart()
		fireball.emitting = true

	# Enable and reset light for red flash
	if blast_light:
		blast_light.light_energy = LIGHT_ENERGY
		blast_light.visible = true
		
		# Safety timer: force light cleanup after max duration
		if light_cleanup_timer != null:
			if light_cleanup_timer.timeout.is_connected(_force_light_cleanup):
				light_cleanup_timer.timeout.disconnect(_force_light_cleanup)
		light_cleanup_timer = get_tree().create_timer(LIGHT_FADE_DURATION * 2.0)
		light_cleanup_timer.timeout.connect(_force_light_cleanup)
	
	lifetime_timer = 0.0

func _process(delta: float) -> void:
	if is_playing:
		lifetime_timer += delta

		# Hide the bright flash sprite after its short visible window
		if muzzle_flash and muzzle_flash.visible and lifetime_timer >= FLASH_DURATION:
			muzzle_flash.visible = false

		# Quick fade out of red light (0.1s)
		if blast_light and blast_light.visible:
			var fade_progress = lifetime_timer / LIGHT_FADE_DURATION
			# Gentle exponential fade so the orange flash lingers a moment
			blast_light.light_energy = LIGHT_ENERGY * exp(-3.0 * fade_progress)
			if fade_progress >= 1.0:
				blast_light.visible = false
		
		# Return to pool after effect duration
		if lifetime_timer >= EFFECT_DURATION:
			is_playing = false
			BlastEffectPool.return_effect(self)

func _force_light_cleanup() -> void:
	"""Force cleanup of light after max lifetime (safety mechanism)"""
	if blast_light and blast_light.visible:
		blast_light.visible = false
		blast_light.light_energy = 0.0
	light_cleanup_timer = null
