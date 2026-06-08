extends Area3D

## AA Projectile with mid-air timed detonation and area damage
## Uses AABlastEffect for explosions
## Separate from tank Projectile for clean code separation

@export var speed: float = 685.0
@export var blast_timer: float = 12.0  # Time until mid-air explosion
@export var explosion_radius: float = 5.0  # Area damage radius
@export var bullet_drop_gravity: float = 4.6
@export var max_distance: float = 140464.0  # Max XZ-plane distance before despawn

var velocity: Vector3 = Vector3.ZERO
var time_alive: float = 0.0
var distance_traveled: float = 0.0
var is_active: bool = false
var spawn_grace_period: float = 0.01  # Prevent immediate collision with spawner

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func initialize(spawn_position: Vector3, direction: Vector3, projectile_speed: float = 685.0, timer: float = 9.0, radius: float = 5.0) -> void:
	"""Initialize AA projectile - called by AAProjectilePool"""
	global_position = spawn_position
	show()
	
	# Set projectile rotation to match firing direction
	var dir_normalized = direction.normalized()
	if dir_normalized.length() > 0.001:
		look_at(global_position + dir_normalized, Vector3.UP)
	
	velocity = dir_normalized * projectile_speed
	blast_timer = timer
	explosion_radius = radius
	is_active = true
	time_alive = 0.0
	distance_traveled = 0.0

func _physics_process(delta: float) -> void:
	if not is_active:
		return
	
	time_alive += delta
	
	# Mid-air detonation after timer expires
	if time_alive >= blast_timer:
		_explode(true)  # Mid-air with light
		return
	
	# Apply bullet drop
	velocity.y -= bullet_drop_gravity * delta
	
	# Move projectile
	var movement = velocity * delta
	global_position += movement
	
	# Track XZ-plane distance
	var xz_movement = Vector2(movement.x, movement.z).length()
	distance_traveled += xz_movement
	
	# Despawn if traveled too far
	if distance_traveled >= max_distance:
		_return_to_pool()

func _on_body_entered(_body: Node) -> void:
	"""Handle terrain collision (StaticBody3D)"""
	if not is_active or time_alive < spawn_grace_period:
		return
	_explode(true)  # Terrain hit with light

func _on_area_entered(_area: Node) -> void:
	"""Handle unit hitbox collision (Area3D)"""
	if not is_active or time_alive < spawn_grace_period:
		return
	_explode(false)  # Unit hit without light (units get glow instead)

func _explode(enable_light: bool) -> void:
	"""Trigger AA blast effect and area damage"""
	is_active = false
	
	# Spawn AABlastEffect
	var aa_blast_pool = get_node_or_null("/root/AABlastEffectPool")
	if aa_blast_pool:
		aa_blast_pool.spawn_effect(global_position, enable_light)
	
	# Apply area damage to nearby units
	if explosion_radius > 0:
		_apply_area_damage()
	
	_return_to_pool()

func _apply_area_damage() -> void:
	"""Deal damage/glow to units within explosion radius"""
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return
	
	var query = PhysicsShapeQueryParameters3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = explosion_radius
	query.shape = sphere
	query.transform = Transform3D(Basis(), global_position)
	query.collision_mask = 2  # Layer 2: Unit hitboxes
	
	var results = space_state.intersect_shape(query, 32)
	for result in results:
		var collider = result.collider
		if collider and collider.get_parent():
			var unit = collider.get_parent()
			if unit.has_meta("player_color"):
				var impact_color = unit.get_meta("player_color")
				var glow_effect = get_node_or_null("/root/UnitGlowEffect")
				if glow_effect:
					glow_effect.apply_glow(unit, impact_color, 3.0)

func _return_to_pool() -> void:
	"""Return projectile to pool for reuse"""
	is_active = false
	hide()
	var aa_pool = get_node_or_null("/root/AAProjectilePool")
	if aa_pool:
		aa_pool.return_projectile(self)
