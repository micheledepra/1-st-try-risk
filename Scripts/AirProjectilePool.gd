extends Node

## AirProjectilePool
## Manages air projectile instances with alternating red/green tracers
## Optimized for rapid fire with object pooling

const MAX_ACTIVE: int = 100
const SCENE_PATH: String = "res://Scenes/Units/AirProjectile.tscn"

# Alternating tracer colors
const COLOR_RED: Color = Color(1.0, 0.1, 0.1, 1.0)
const COLOR_GREEN: Color = Color(0.1, 1.0, 0.1, 1.0)

var projectile_scene: PackedScene
var projectile_pool: Array[Area3D] = []
var active_projectiles: Array[Area3D] = []

# Static color toggle for alternating tracers
static var color_toggle: bool = false

func _ready() -> void:
	# Preload projectile scene
	projectile_scene = load(SCENE_PATH)
	
	if not projectile_scene:
		push_error("AirProjectilePool: Failed to load scene at " + SCENE_PATH)
		return
	
	# Pre-instantiate pool (more for rapid fire)
	for i in range(8):
		var projectile = projectile_scene.instantiate() as Area3D
		projectile.visible = false
		projectile.set_physics_process(false)
		add_child(projectile)
		projectile_pool.append(projectile)
	
	print("AirProjectilePool: Initialized with %d pooled projectiles" % projectile_pool.size())

func spawn_projectile(spawn_position: Vector3, direction: Vector3, speed: float = 200.0, orientation_direction: Vector3 = Vector3.ZERO, up_vector: Vector3 = Vector3.UP) -> Area3D:
	"""Spawn an air projectile with alternating red/green tracer
	@param spawn_position: Starting position (muzzle)
	@param direction: Firing direction (where bullet travels)
	@param speed: Projectile speed
	@param orientation_direction: Visual orientation of bullet (defaults to direction if zero)
	@param up_vector: Up vector from muzzle to preserve plane's roll (defaults to Vector3.UP)
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
		push_error("AirProjectilePool: Invalid projectile instance!")
		return null
	
	# Set alternating tracer color
	var tracer_color = COLOR_RED if color_toggle else COLOR_GREEN
	color_toggle = not color_toggle
	
	# Apply color and initialize
	projectile.set_physics_process(true)
	if projectile.has_method("set_tracer_color"):
		projectile.set_tracer_color(tracer_color)
	projectile.initialize(spawn_position, direction, speed, orientation_direction, up_vector)
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
