extends Node

## AAProjectilePool
## Manages AA projectile instances for rapid fire with object pooling
## Separate from ProjectilePool for clean Tank/AA separation

const MAX_ACTIVE: int = 100  # Higher limit for rapid fire AA
const SCENE_PATH: String = "res://Scenes/Units/AAProjectile.tscn"

var projectile_scene: PackedScene
var projectile_pool: Array[Area3D] = []
var active_projectiles: Array[Area3D] = []

func _ready() -> void:
	# Preload projectile scene
	projectile_scene = load(SCENE_PATH)
	
	if not projectile_scene:
		push_error("AAProjectilePool: Failed to load scene at " + SCENE_PATH)
		return
	
	# Pre-instantiate pool (more than tank due to rapid fire)
	for i in range(8):
		var projectile = projectile_scene.instantiate() as Area3D
		projectile.visible = false
		projectile.set_physics_process(false)
		add_child(projectile)
		projectile_pool.append(projectile)
	
	print("AAProjectilePool: Initialized with %d pooled projectiles" % projectile_pool.size())

func spawn_projectile(spawn_position: Vector3, direction: Vector3, speed: float = 685.0, blast_timer: float = 9.0, explosion_radius: float = 5.0) -> Area3D:
	"""Spawn an AA projectile with timed detonation
	@param spawn_position: Starting position (muzzle)
	@param direction: Firing direction
	@param speed: Projectile speed
	@param blast_timer: Seconds until mid-air explosion
	@param explosion_radius: Area damage radius
	@return: The spawned projectile"""
	
	# Check active limit - force cleanup oldest
	if active_projectiles.size() >= MAX_ACTIVE:
		var oldest = active_projectiles[0]
		return_projectile(oldest)
	
	# Get projectile from pool
	var projectile: Area3D
	if projectile_pool.size() > 0:
		projectile = projectile_pool.pop_back()
	else:
		# Pool exhausted, create new one
		projectile = projectile_scene.instantiate() as Area3D
		add_child(projectile)
	
	# Validate projectile
	if not is_instance_valid(projectile):
		push_error("AAProjectilePool: Invalid projectile instance!")
		return null
	
	# Initialize and activate
	projectile.set_physics_process(true)
	projectile.initialize(spawn_position, direction, speed, blast_timer, explosion_radius)
	active_projectiles.append(projectile)
	
	return projectile

func return_projectile(projectile: Area3D) -> void:
	"""Return a projectile to the pool for reuse"""
	if projectile == null or not is_instance_valid(projectile):
		return
	
	# Deactivate
	projectile.visible = false
	projectile.set_physics_process(false)
	projectile.global_position = Vector3.ZERO
	
	# Remove from active list
	var idx = active_projectiles.find(projectile)
	if idx >= 0:
		active_projectiles.remove_at(idx)
	
	# Return to pool
	if not projectile_pool.has(projectile):
		projectile_pool.append(projectile)
