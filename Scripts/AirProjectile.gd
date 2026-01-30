extends Area3D

## Air Projectile for Fighter aircraft
## Alternating red/green tracers with impact-only effects (no mid-air detonation)
## Uses same size as AAProjectile for visual consistency

@export var speed: float = 300.0  # Air projectile speed target
@export var max_distance: float = 40464.0
@export var bullet_drop_gravity: float = 9.0  # Less drop for air-to-air/ground

var velocity: Vector3 = Vector3.ZERO
var time_alive: float = 0.0
var distance_traveled: float = 0.0
var is_active: bool = false
var spawn_grace_period: float = 0.01
var trail_activation_delay: float = 0.1  # Activate trail after 0.1 seconds
var trail_activated: bool = false

# Tracer color set by pool before initialize()
var tracer_color: Color = Color.RED

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var trail: GPUParticles3D = $Trail

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	
	# Start with trail disabled
	if trail:
		trail.emitting = false

func set_tracer_color(color: Color) -> void:
	"""Set tracer color before initialize - called by AirProjectilePool"""
	tracer_color = color
	
	# Apply color to mesh material
	if mesh_instance and mesh_instance.mesh:
		var material = mesh_instance.get_surface_override_material(0)
		if material == null:
			material = StandardMaterial3D.new()
			mesh_instance.set_surface_override_material(0, material)
		
		if material is StandardMaterial3D:
			material.albedo_color = color
			material.emission_enabled = true
			material.emission = color
			material.emission_energy_multiplier = 15.0
			material.metallic = 1.0
			material.roughness = 0.2
	
	# Apply color to trail particles (higher alpha for visibility)
	if trail and trail.process_material:
		var trail_material = trail.process_material as ParticleProcessMaterial
		if trail_material:
			trail_material.color = Color(color.r, color.g, color.b, 0.9)

func initialize(spawn_position: Vector3, direction: Vector3, projectile_speed: float = 200.0, orientation_direction: Vector3 = Vector3.ZERO, up_vector: Vector3 = Vector3.UP) -> void:
	"""Initialize projectile position and launch it - called by AirProjectilePool
	   direction: The firing direction (where bullet travels)
	   orientation_direction: The visual orientation of the bullet (defaults to direction if not provided)
	   up_vector: Up vector from muzzle to preserve plane's roll angle (defaults to Vector3.UP)"""
	global_position = spawn_position
	show()
	
	# Set projectile rotation - use orientation_direction if provided, otherwise use firing direction
	var dir_normalized = direction.normalized()
	var orient_dir = orientation_direction if orientation_direction.length() > 0.001 else dir_normalized
	orient_dir = orient_dir.normalized()
	
	# Use muzzle's up vector to preserve plane's roll angle
	var final_up = up_vector if up_vector.length() > 0.001 else Vector3.UP
	
	if orient_dir.length() > 0.001:
		look_at(global_position + orient_dir, final_up)
	
	velocity = dir_normalized * projectile_speed
	is_active = true
	time_alive = 0.0
	distance_traveled = 0.0
	trail_activated = false
	
	# Ensure trail is disabled at spawn
	if trail:
		trail.emitting = false

func _physics_process(delta: float) -> void:
	if not is_active:
		return
	
	time_alive += delta
	
	# Activate trail after delay
	if not trail_activated and time_alive >= trail_activation_delay:
		trail_activated = true
		if trail:
			trail.emitting = true
	
	# Apply bullet drop (less than ground projectiles)
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
	"""Handle terrain collision (StaticBody3D, layer 1)"""
	if not is_active or time_alive < spawn_grace_period:
		return
	
	# Terrain hit - spawn impact effect with tracer color
	var pool = get_node_or_null("/root/AirImpactEffectPool")
	if pool:
		pool.spawn_effect(global_position, tracer_color, true)
	
	_return_to_pool()

func _on_area_entered(area: Node) -> void:
	"""Handle unit hitbox collision (Area3D, layer 2)"""
	if not is_active or time_alive < spawn_grace_period:
		return
	
	var impact_color: Color = tracer_color
	var hit_unit: Node3D = null
	
	# Check for unit with player_color metadata
	if area.get_parent() and area.get_parent().has_meta("player_color"):
		impact_color = area.get_parent().get_meta("player_color")
		hit_unit = area.get_parent()
	
	# Spawn impact effect (no light for units - they get glow instead)
	var pool = get_node_or_null("/root/AirImpactEffectPool")
	if pool:
		pool.spawn_effect(global_position, impact_color, hit_unit == null)
	
	# Apply glow effect to unit if hit
	if hit_unit:
		var glow_effect = get_node_or_null("/root/UnitGlowEffect")
		if glow_effect:
			glow_effect.apply_glow(hit_unit, impact_color, 5.0)
	
	_return_to_pool()

func _return_to_pool() -> void:
	"""Return projectile to pool for reuse"""
	is_active = false
	trail_activated = false
	
	# Stop trail emission
	if trail:
		trail.emitting = false
	
	hide()
	var pool = get_node_or_null("/root/AirProjectilePool")
	if pool:
		pool.return_projectile(self)
