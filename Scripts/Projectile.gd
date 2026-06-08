extends Area3D

## Simple projectile with linear movement and auto-despawn
## Optimized for low-spec performance
##
## Collision Architecture:
## - Layer 1: Terrain (StaticBody3D) → triggers body_entered
## - Layer 2: Unit Hitboxes (Area3D) → triggers area_entered
## - Layer 4: Projectiles (this)
## - Projectile mask = 3 (detects layers 1 + 2)

@export var speed: float = 25.0
@export var max_distance: float = 40464.0  # Max XZ-plane distance before despawn (matches map size)
@export var bullet_drop_gravity: float = 4.6  # Gravity strength for bullet drop

var velocity: Vector3 = Vector3.ZERO
var time_alive: float = 0.0
var distance_traveled: float = 0.0  # XZ-plane distance tracking
var is_active: bool = false
var spawn_grace_period: float = 0.01  # Prevent immediate collision with spawner

# Back-references set by UnitCombatSystem.spawn_projectile() so projectile
# routes callbacks through its owner's pools rather than global autoloads.
var owner_pool: Node = null
var owner_impact_pool: Node = null
var owner_glow_effect: Node = null

func _ready() -> void:
	# body_entered: Terrain (StaticBody3D, layer 1)
	# area_entered: Unit hitboxes (Area3D, layer 2)
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func initialize(spawn_position: Vector3, direction: Vector3, projectile_speed: float = 25.0) -> void:
	"""Initialize projectile position and launch it - called by ProjectilePool"""
	global_position = spawn_position
	show()  # Ensure projectile is visible when spawned from pool
	
	# Set projectile rotation to match firing direction
	var dir_normalized = direction.normalized()
	if dir_normalized.length() > 0.001:
		# Look in the direction of travel
		look_at(global_position + dir_normalized, Vector3.UP)
	
	launch(direction, projectile_speed)

func launch(direction: Vector3, projectile_speed: float = 25.0) -> void:
	"""Launch projectile in given direction with speed"""
	velocity = direction.normalized() * projectile_speed
	is_active = true
	time_alive = 0.0
	distance_traveled = 0.0

func _physics_process(delta: float) -> void:
	if not is_active:
		return
	
	time_alive += delta
	
	# Apply bullet drop (gravity effect)
	velocity.y -= bullet_drop_gravity * delta
	
	# Move projectile
	var movement = velocity * delta
	global_position += movement
	
	# Track XZ-plane distance
	var xz_movement = Vector2(movement.x, movement.z).length()
	distance_traveled += xz_movement
	
	# Despawn if traveled too far
	if distance_traveled >= max_distance:
		var pp = _get_proj_pool()
		if pp:
			pp.return_projectile(self)

func _on_body_entered(_body: Node) -> void:
	"""Handle terrain collision (StaticBody3D, layer 1)"""
	if not is_active or time_alive < spawn_grace_period:
		return
	is_active = false  # Prevent duplicate hits from multi-face mesh collision

	# Terrain hit - brown impact with light effect
	var ip = _get_impact_pool()
	if ip:
		ip.spawn_effect(global_position, Color.SADDLE_BROWN, true)
	var pp = _get_proj_pool()
	if pp:
		pp.return_projectile.call_deferred(self)

func _on_area_entered(area: Node) -> void:
	"""Handle unit hitbox collision (Area3D, layer 2)"""
	if not is_active or time_alive < spawn_grace_period:
		return

	# Ignore territory hover Area3Ds — only respond to unit hitboxes
	# (unit hitbox parents carry player_color metadata; territory areas don't)
	if not area.get_parent() or not area.get_parent().has_meta("player_color"):
		return

	is_active = false  # Prevent duplicate hits

	var hit_unit: Node3D = area.get_parent()
	var impact_color: Color = hit_unit.get_meta("player_color")

	# Spawn impact effect (no light for units - they get glow instead)
	var ip = _get_impact_pool()
	if ip:
		ip.spawn_effect(global_position, impact_color, false)

	# Apply glow effect to hit unit
	var glow = _get_glow()
	if glow:
		glow.apply_glow(hit_unit, impact_color, 5.0)

	# Return projectile to pool (deferred to avoid physics callback error)
	var pp = _get_proj_pool()
	if pp:
		pp.return_projectile.call_deferred(self)

# ── Pool lookup helpers (local back-ref first, then autoload fallback) ────────

func _get_proj_pool() -> Node:
	if owner_pool:
		return owner_pool
	if has_node("/root/ProjectilePool"):
		return get_node("/root/ProjectilePool")
	return null

func _get_impact_pool() -> Node:
	if owner_impact_pool:
		return owner_impact_pool
	if has_node("/root/ImpactEffectPool"):
		return get_node("/root/ImpactEffectPool")
	return null

func _get_glow() -> Node:
	if owner_glow_effect:
		return owner_glow_effect
	if has_node("/root/UnitGlowEffect"):
		return get_node("/root/UnitGlowEffect")
	return null
