extends GPUParticles3D

## Muzzle blast: a light-orange/red light pulse + an additive fireball + a
## randomized-shape burst smoke cloud that leaves a short world-space trail.
## The overall size scales with projectile type (cannon biggest, AA mid, MG
## smallest) and the firing unit's world scale. Pooled (BlastEffectPool).

const Combat = preload("res://Scripts/UnitCombatState.gd")

# Per-type profile: geometry scale + particle counts + light + flash.
const PROFILE := {
	0: {"scale": 1.0, "smoke": 60, "fire": 26, "trail": 16, "light": 9.0, "range": 5.0, "flash": 1.0, "flash_t": 0.05},  # CANNON
	1: {"scale": 0.30, "smoke": 16, "fire": 8, "trail": 8, "light": 3.0, "range": 1.8, "flash": 0.30, "flash_t": 0.03},  # MG
	2: {"scale": 0.68, "smoke": 40, "fire": 18, "trail": 12, "light": 6.0, "range": 3.4, "flash": 0.60, "flash_t": 0.04},  # AA
}

const EFFECT_DURATION := 1.1
const LIGHT_FADE := 0.07  # snappy muzzle-light pulse

var is_playing := false
var lifetime_timer := 0.0
var light_energy0 := 9.0
var flash_seconds := 0.05

@onready var fireball: GPUParticles3D = $Fireball
@onready var flash_core: MeshInstance3D = $FlashCore
@onready var blast_light: OmniLight3D = $BlastLight
@onready var smoke_trail: GPUParticles3D = $SmokeTrail

func _ready() -> void:
	one_shot = true
	emitting = false
	reset_state()

func reset_state() -> void:
	if flash_core:
		flash_core.visible = false
	if blast_light:
		blast_light.visible = false
		blast_light.light_energy = 0.0

func play_effect(pos: Vector3, direction: Vector3, ptype: int = 0, unit_scale: float = 1.0) -> void:
	"""Fire the muzzle blast at `pos` facing `direction`, sized to `ptype`."""
	var p: Dictionary = PROFILE.get(ptype, PROFILE[0])
	global_position = pos
	if direction.length() > 0.001:
		look_at(pos + direction, Vector3.UP)
	# Per-shot shape variation: random roll about the firing axis.
	rotate_object_local(Vector3(0, 0, 1), randf() * TAU)

	var s: float = p["scale"] * max(unit_scale, 0.01)
	scale = Vector3.ONE * s

	# Particle counts come from the profile (not stretched by unit scale).
	amount = p["smoke"]
	emitting = false
	restart()
	emitting = true

	if fireball:
		fireball.amount = p["fire"]
		fireball.emitting = false
		fireball.restart()
		fireball.emitting = true

	if smoke_trail:
		smoke_trail.amount = p["trail"]
		smoke_trail.emitting = false
		smoke_trail.restart()
		smoke_trail.emitting = true

	if flash_core:
		flash_core.scale = Vector3.ONE * p["flash"]
		flash_core.visible = true
	flash_seconds = p["flash_t"]

	if blast_light:
		light_energy0 = p["light"]
		blast_light.light_energy = light_energy0
		blast_light.omni_range = p["range"] * max(unit_scale, 0.01)
		blast_light.visible = true

	lifetime_timer = 0.0
	is_playing = true

func _process(delta: float) -> void:
	if not is_playing:
		return
	lifetime_timer += delta

	if flash_core and flash_core.visible and lifetime_timer >= flash_seconds:
		flash_core.visible = false

	if blast_light and blast_light.visible:
		var progress := lifetime_timer / LIGHT_FADE
		blast_light.light_energy = light_energy0 * exp(-9.0 * progress)
		if progress >= 1.0:
			blast_light.visible = false

	if lifetime_timer >= EFFECT_DURATION:
		is_playing = false
		BlastEffectPool.return_effect(self)
