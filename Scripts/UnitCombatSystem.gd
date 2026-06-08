extends Node

## UnitCombatSystem
## Self-contained combat system that a unit controller embeds for standalone operation.
## In the main game (autoloads present) it proxies to the existing singletons — zero
## behavior change.  In any other scene (no autoloads) it spins up local pool instances
## as children so the unit works fully without any project-level setup.

var _blast_pool: Node = null
var _proj_pool: Node = null
var _impact_pool: Node = null
var _glow: Node = null


func _ready() -> void:
	if has_node("/root/BlastEffectPool"):
		# Main game — delegate to existing autoload singletons
		_blast_pool  = get_node("/root/BlastEffectPool")
		_proj_pool   = get_node("/root/ProjectilePool")
		_impact_pool = get_node("/root/ImpactEffectPool")
		_glow        = get_node("/root/UnitGlowEffect")
	else:
		# Standalone — create local instances
		_blast_pool = load("res://Scripts/BlastEffectPool.gd").new()
		_blast_pool.name = "LocalBlastEffectPool"
		add_child(_blast_pool)

		_proj_pool = load("res://Scripts/ProjectilePool.gd").new()
		_proj_pool.name = "LocalProjectilePool"
		add_child(_proj_pool)

		_impact_pool = load("res://Scripts/ImpactEffectPool.gd").new()
		_impact_pool.name = "LocalImpactEffectPool"
		add_child(_impact_pool)

		_glow = load("res://Scripts/UnitGlowEffect.gd").new()
		_glow.name = "LocalUnitGlowEffect"
		add_child(_glow)


# ── Public API ────────────────────────────────────────────────────────────────

func spawn_blast(pos: Vector3, dir: Vector3, scale: float) -> void:
	if _blast_pool:
		_blast_pool.spawn_effect(pos, dir, scale)


func spawn_projectile(pos: Vector3, dir: Vector3, speed: float) -> void:
	if _proj_pool == null:
		return
	var p: Area3D = _proj_pool.spawn_projectile(pos, dir, speed)
	if p:
		p.owner_pool        = _proj_pool
		p.owner_impact_pool = _impact_pool
		p.owner_glow_effect = _glow


func return_projectile(proj: Area3D) -> void:
	if _proj_pool:
		_proj_pool.return_projectile(proj)


func spawn_impact(pos: Vector3, color: Color, enable_light: bool) -> void:
	if _impact_pool:
		_impact_pool.spawn_effect(pos, color, enable_light)


func apply_glow(unit: Node3D, color: Color, duration: float) -> void:
	if _glow:
		_glow.apply_glow(unit, color, duration)
