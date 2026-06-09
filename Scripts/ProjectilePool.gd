extends Node

## ProjectilePool - the single pool for every weapon (cannon / MG / AA).
##
## One BaseProjectile scene serves all three types; the caller passes a
## UnitCombatState.PType and the projectile configures its own size, speed,
## colour and behaviour. Pooled to avoid per-shot instantiation on low-spec.

const MAX_ACTIVE_PROJECTILES: int = 80
const PROJECTILE_SCENE: String = "res://Scenes/Units/Projectile.tscn"
const PRE_INSTANTIATE: int = 32

var projectile_scene: PackedScene
var projectile_pool: Array[Area3D] = []
var active_projectiles: Array[Area3D] = []

func _ready() -> void:
	projectile_scene = load(PROJECTILE_SCENE)
	for i in range(PRE_INSTANTIATE):
		var p := projectile_scene.instantiate() as Area3D
		p.visible = false
		p.process_mode = Node.PROCESS_MODE_DISABLED
		p.is_active = false
		add_child(p)
		projectile_pool.append(p)

func spawn(type: int, spawn_position: Vector3, direction: Vector3, platform_velocity: Vector3 = Vector3.ZERO, shooter: Node = null, effect_scale: float = 1.0) -> Area3D:
	"""Spawn a projectile of `type` (UnitCombatState.PType)."""
	if active_projectiles.size() >= MAX_ACTIVE_PROJECTILES:
		return_projectile(active_projectiles[0])

	var p: Area3D
	if projectile_pool.size() > 0:
		p = projectile_pool.pop_back()
	else:
		p = projectile_scene.instantiate() as Area3D
		p.is_active = false
		add_child(p)

	if not is_instance_valid(p):
		return null

	p.process_mode = Node.PROCESS_MODE_INHERIT
	p.visible = true
	p.effect_scale = effect_scale
	p.configure(type)
	p.initialize(spawn_position, direction, platform_velocity, shooter)
	active_projectiles.append(p)
	return p

func return_projectile(projectile: Area3D) -> void:
	"""Return a projectile to the pool, fully quiesced."""
	if projectile == null or not is_instance_valid(projectile):
		return
	projectile.is_active = false
	projectile.visible = false
	projectile.process_mode = Node.PROCESS_MODE_DISABLED
	projectile.global_position = Vector3.ZERO
	projectile.velocity = Vector3.ZERO
	projectile.time_alive = 0.0
	projectile.distance_traveled = 0.0

	var idx := active_projectiles.find(projectile)
	if idx >= 0:
		active_projectiles.remove_at(idx)
	if not projectile_pool.has(projectile):
		projectile_pool.append(projectile)
