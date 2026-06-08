extends Node

## ProjectilePool
## Manages projectile instances to reduce instantiation overhead
## Optimized for low-spec performance with object pooling

# Shared by tank cannons (slow fire) and aircraft machine guns (rapid fire, multiple
# muzzles), so the active cap must be high enough to sustain an MG stream.
const MAX_ACTIVE_PROJECTILES: int = 48
const PROJECTILE_SCENE: String = "res://Scenes/Units/Projectile.tscn"

var projectile_scene: PackedScene
var projectile_pool: Array[Area3D] = []
var active_projectiles: Array[Area3D] = []

func _ready() -> void:
	# Preload projectile scene
	projectile_scene = load(PROJECTILE_SCENE)
	
	# Pre-instantiate pool of projectiles
	for i in range(16):
		var projectile = projectile_scene.instantiate() as Area3D
		projectile.visible = false
		projectile.process_mode = Node.PROCESS_MODE_DISABLED
		projectile.is_active = false
		add_child(projectile)
		projectile_pool.append(projectile)
	
	print("ProjectilePool: Initialized with %d pooled projectiles" % projectile_pool.size())

func spawn_projectile(spawn_position: Vector3, direction: Vector3, speed: float, effect_scale: float = 1.0, platform_velocity: Vector3 = Vector3.ZERO, bullet_scale: float = 1.0) -> Area3D:
	"""Spawn a projectile from the pool or create a new one
	@param effect_scale: World scale of the firing unit, forwarded to terrain impact effects
	@param platform_velocity: velocity of the firing vehicle, added to the muzzle velocity
	@param bullet_scale: visual size of the round (cannon = 1.0, machine gun smaller)"""
	
	# Check active projectile limit
	if active_projectiles.size() >= MAX_ACTIVE_PROJECTILES:
		# Remove oldest projectile
		var oldest = active_projectiles[0]
		return_projectile(oldest)
	
	# Get projectile from pool
	var projectile: Area3D
	if projectile_pool.size() > 0:
		projectile = projectile_pool.pop_back()
	else:
		# Pool exhausted, create new one
		projectile = projectile_scene.instantiate() as Area3D
		projectile.is_active = false
		add_child(projectile)
		print("ProjectilePool: Pool exhausted, created new projectile")
	
	# Validate projectile
	if not is_instance_valid(projectile):
		push_error("ProjectilePool: Invalid projectile instance!")
		return null
	
	# Initialize and activate projectile
	projectile.effect_scale = effect_scale
	projectile.initialize(spawn_position, direction, speed, platform_velocity, bullet_scale)
	projectile.visible = true
	projectile.process_mode = Node.PROCESS_MODE_INHERIT
	active_projectiles.append(projectile)
	
	return projectile

func return_projectile(projectile: Area3D) -> void:
	"""Return a projectile to the pool for reuse"""
	if projectile == null or not is_instance_valid(projectile):
		return
	
	# Deactivate projectile
	projectile.is_active = false
	projectile.visible = false
	projectile.process_mode = Node.PROCESS_MODE_DISABLED
	projectile.global_position = Vector3.ZERO
	projectile.velocity = Vector3.ZERO
	projectile.scale = Vector3.ONE  # reset bullet-size scaling for reuse
	projectile.time_alive = 0.0
	
	# Remove from active list
	var idx = active_projectiles.find(projectile)
	if idx >= 0:
		active_projectiles.remove_at(idx)
	
	# Return to pool if not already there
	if not projectile_pool.has(projectile):
		projectile_pool.append(projectile)
