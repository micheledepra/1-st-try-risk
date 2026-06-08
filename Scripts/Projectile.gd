extends Area3D

## Simple projectile with linear movement and auto-despawn
## Optimized for low-spec performance
##
## Collision Architecture:
## - Layer 1: Terrain (StaticBody3D) → triggers body_entered
## - Layer 2: Unit Hitboxes (Area3D) → triggers area_entered
## - Layer 4: Projectiles (this)
## - Projectile mask = 3 (detects layers 1 + 2)

# SCALE CONVENTION: this world runs at ~4.3 game units per metre (a ~6.8 m tank renders ~29 units).
# Physical constants below are real-world values multiplied by 4.3 so the round behaves like a
# real shell relative to the tank's on-screen size.
@export var speed: float = 100000.0
@export var max_distance: float = 40464.0  # Max XZ-plane distance before despawn (matches map size)
@export var bullet_drop_gravity: float = 42.0  # 9.81 m/s^2 * 4.3 u/m (real gravity at this scale)
@export var drag: float = 0.1  # Air resistance (per-second exponential decay). Small, like a real shell: leaves fast, bleeds speed gradually
@export var min_speed: float = 150.0  # ~35 m/s * 4.3: below this the spent round despawns

var velocity: Vector3 = Vector3.ZERO
var effect_scale: float = 1.0  # World scale of the firing unit, used to size terrain impacts
var time_alive: float = 0.0
var distance_traveled: float = 0.0  # XZ-plane distance tracking
var is_active: bool = false
var spawn_grace_period: float = 0.01  # Prevent immediate collision with spawner

func _ready() -> void:
	# body_entered: Terrain (StaticBody3D, layer 1)
	# area_entered: Unit hitboxes (Area3D, layer 2)
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func initialize(spawn_position: Vector3, direction: Vector3, projectile_speed: float = 100000.0, platform_velocity: Vector3 = Vector3.ZERO, bullet_scale: float = 1.0) -> void:
	"""Initialize projectile position and launch it - called by ProjectilePool
	@param platform_velocity: velocity of the firing vehicle, added to muzzle velocity (moving-shooter physics)
	@param bullet_scale: visual/collision size of the round. Same scene for every weapon - a tank
	cannon uses the full-size round (1.0); an aircraft machine gun uses a smaller version (e.g. 0.45)."""
	global_position = spawn_position
	show()  # Ensure projectile is visible when spawned from pool

	# Set projectile rotation to match firing direction
	var dir_normalized = direction.normalized()
	if dir_normalized.length() > 0.001:
		# Look in the direction of travel
		look_at(global_position + dir_normalized, Vector3.UP)

	# Cannon vs MG: same round, different size
	scale = Vector3.ONE * bullet_scale

	launch(direction, projectile_speed, platform_velocity)

func launch(direction: Vector3, projectile_speed: float = 100000.0, platform_velocity: Vector3 = Vector3.ZERO) -> void:
	"""Launch projectile in given direction with speed.
	The firing vehicle's velocity is added so a round fired on the move keeps the
	tank's momentum (it tracks straight ahead in the tank's frame instead of
	appearing to drift opposite the direction of travel)."""
	velocity = direction.normalized() * projectile_speed + platform_velocity
	is_active = true
	time_alive = 0.0
	distance_traveled = 0.0

func _physics_process(delta: float) -> void:
	if not is_active:
		return
	
	time_alive += delta

	# Air drag: exponential decay so the round is fast at the muzzle and slows with distance.
	# exp(-drag*delta) is framerate-independent and never flips the velocity sign.
	velocity *= exp(-drag * delta)

	# Apply bullet drop (gravity effect) after drag, so the round still arcs down as it slows
	velocity.y -= bullet_drop_gravity * delta

	# Swept movement: raycast from current to next position so fast rounds don't
	# tunnel through targets. At ~4000 u/s a round covers ~67 units per frame, which
	# is larger than a tank, so plain Area3D overlap would miss most hits.
	var movement = velocity * delta
	var next_position = global_position + movement

	if time_alive >= spawn_grace_period:
		var space = get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(global_position, next_position, collision_mask)
		query.collide_with_areas = true   # unit hitboxes are Area3D (layer 2)
		query.collide_with_bodies = true  # terrain is StaticBody3D (layer 1)
		query.exclude = [self]
		var hit = space.intersect_ray(query)
		if hit:
			is_active = false
			var hit_pos: Vector3 = hit["position"]
			global_position = hit_pos
			if hit["collider"] is Area3D:
				_resolve_unit_hit(hit["collider"], hit_pos)
			else:
				_resolve_terrain_hit(hit_pos)
			ProjectilePool.return_projectile.call_deferred(self)
			return

	# No hit this step - advance
	global_position = next_position

	# Track XZ-plane distance
	var xz_movement = Vector2(movement.x, movement.z).length()
	distance_traveled += xz_movement

	# Despawn once the round has bled off its energy or travelled too far
	if velocity.length() < min_speed:
		ProjectilePool.return_projectile(self)
		return
	if distance_traveled >= max_distance:
		ProjectilePool.return_projectile(self)

func _resolve_terrain_hit(at: Vector3) -> void:
	"""Brown terrain impact with light, sized to the firing unit's world scale."""
	ImpactEffectPool.spawn_effect(at, Color.SADDLE_BROWN, true, effect_scale)

func _resolve_unit_hit(hitbox: Node, at: Vector3) -> void:
	"""Coloured unit impact (no light - units get a glow instead)."""
	var impact_color: Color = Color.SADDLE_BROWN
	var hit_unit: Node3D = null
	if hitbox.get_parent() and hitbox.get_parent().has_meta("player_color"):
		impact_color = hitbox.get_parent().get_meta("player_color")
		hit_unit = hitbox.get_parent()
	var impact_scale = effect_scale
	if hit_unit and hit_unit.has_meta("effect_scale"):
		impact_scale = hit_unit.get_meta("effect_scale")
	ImpactEffectPool.spawn_effect(at, impact_color, hit_unit == null, impact_scale)
	if hit_unit:
		UnitGlowEffect.apply_glow(hit_unit, impact_color, 5.0)

func _on_body_entered(_body: Node) -> void:
	"""Backstop for terrain collision via Area3D overlap (slow / already-overlapping cases)."""
	if not is_active or time_alive < spawn_grace_period:
		return
	is_active = false
	_resolve_terrain_hit(global_position)
	ProjectilePool.return_projectile.call_deferred(self)

func _on_area_entered(area: Node) -> void:
	"""Backstop for unit-hitbox collision via Area3D overlap (slow / already-overlapping cases)."""
	if not is_active or time_alive < spawn_grace_period:
		return
	is_active = false
	_resolve_unit_hit(area, global_position)
	ProjectilePool.return_projectile.call_deferred(self)
