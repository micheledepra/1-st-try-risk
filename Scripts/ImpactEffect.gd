extends GPUParticles3D

## Unified impact effect: coloured spark burst + a smoke puff + an optional
## light pulse. One scene serves terrain, unit, and AA-airburst impacts.
## play(position, color, with_light, unit_scale, big): big = AA airburst.

const DURATION := 0.9
const LIGHT_FADE := 0.12

var is_playing := false
var t := 0.0
var light0 := 6.0

@onready var smoke: GPUParticles3D = $Smoke
@onready var impact_light: OmniLight3D = $ImpactLight

# Per-instance process materials so concurrent impacts can be different colours.
var _spark_pm: ParticleProcessMaterial
var _smoke_pm: ParticleProcessMaterial

func _ready() -> void:
	one_shot = true
	emitting = false
	if process_material is ParticleProcessMaterial:
		_spark_pm = process_material.duplicate()
		process_material = _spark_pm
	if smoke and smoke.process_material is ParticleProcessMaterial:
		_smoke_pm = smoke.process_material.duplicate()
		smoke.process_material = _smoke_pm
	reset_light()

func reset_light() -> void:
	if impact_light:
		impact_light.visible = false
		impact_light.light_energy = 0.0

func play_effect(pos: Vector3, color := Color.WHITE, with_light := true, unit_scale := 1.0, big := false) -> void:
	global_position = pos
	var s: float = max(unit_scale, 0.01) * (1.6 if big else 1.0)
	scale = Vector3.ONE * s

	if _spark_pm:
		_spark_pm.color = color.lightened(0.15)
	if _smoke_pm:
		var sc := Color(0.5, 0.5, 0.5).lerp(color, 0.3)
		sc.a = 0.6
		_smoke_pm.color = sc

	amount = 28 if big else 16
	emitting = false
	restart()
	emitting = true

	if smoke:
		smoke.amount = 20 if big else 12
		smoke.emitting = false
		smoke.restart()
		smoke.emitting = true

	if impact_light and with_light:
		light0 = 10.0 if big else 6.0
		impact_light.light_color = color
		impact_light.light_energy = light0
		impact_light.omni_range = (4.5 if big else 3.0) * s
		impact_light.visible = true
	elif impact_light:
		impact_light.visible = false

	t = 0.0
	is_playing = true

func _process(delta: float) -> void:
	if not is_playing:
		return
	t += delta
	if impact_light and impact_light.visible:
		var p := t / LIGHT_FADE
		impact_light.light_energy = light0 * exp(-6.0 * p)
		if p >= 1.0:
			impact_light.visible = false
	if t >= DURATION:
		is_playing = false
		ImpactEffectPool.return_effect(self)
