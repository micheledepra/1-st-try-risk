extends Area3D

## BaseProjectile - the single projectile for cannon (tank), MG (aircraft) and AA.
##
## One swept-raycast move loop (no tunnelling at any speed), inheriting the firing
## platform's velocity (no "bullet hanging at the muzzle"), with per-type size,
## tracer colour, speed and (AA only) a small detonation splash. Every confirmed
## unit hit is funnelled through UnitCombatState.register_hit().
##
## Collision: layer 4 (Projectiles), mask 3 (terrain layer 1 + unit hitboxes layer 2).
## Sizes use the world scale of ~4.3 game units per metre and real calibres:
##   CANNON ~88 mm shell, AA ~60 mm flak round, MG ~12.7 mm (.50 cal) tracer.

const Combat = preload("res://Scripts/UnitCombatState.gd")

# Per-type config. length/radius are the rendered round in world units.
const CONFIG := {
	0: {  # CANNON  (~0.93 m x 0.088 m shell)
		"speed": 4020.0, "length": 4.0, "radius": 0.19,
		"color": Color(1.0, 0.45, 0.12), "emission": 11.0,
		"drag": 0.1, "gravity": 42.0, "min_speed": 150.0,
		"trail_amount": 14, "trail_size": 0.35, "trail_life": 0.35, "trail_emission": 3.0, "splash": 0.0,
	},
	1: {  # MG  (~0.058 m x 0.0127 m .50 cal tracer)
		"speed": 3800.0, "length": 0.26, "radius": 0.03,
		"color": Color(1.0, 0.85, 0.35), "emission": 14.0,
		"drag": 0.06, "gravity": 9.0, "min_speed": 120.0,
		"trail_amount": 16, "trail_size": 0.10, "trail_life": 0.22, "trail_emission": 4.0, "splash": 0.0,
	},
	2: {  # AA  (~0.62 m x 0.06 m flak round, between tank and MG)
		"speed": 3655.0, "length": 2.67, "radius": 0.13,
		"color": Color(1.0, 0.7, 0.2), "emission": 12.0,
		"drag": 0.07, "gravity": 18.0, "min_speed": 130.0,
		"trail_amount": 16, "trail_size": 0.22, "trail_life": 0.28, "trail_emission": 3.5, "splash": 6.0,
	},
}

@export var max_distance: float = 40464.0

var ptype: int = Combat.PType.CANNON
var velocity: Vector3 = Vector3.ZERO
var speed: float = 4020.0
var drag: float = 0.1
var gravity_accel: float = 42.0
var min_speed: float = 150.0
var splash_radius: float = 0.0
var tracer_color: Color = Color(1, 0.5, 0.15)
var effect_scale: float = 1.0

var time_alive: float = 0.0
var distance_traveled: float = 0.0
var is_active: bool = false
var spawn_grace_period: float = 0.01
var _shooter: Node = null
var _exclude: Array = []
var _cfg_type: int = -1
# Per-instance trail resources (so concurrent shots of different types don't bleed).
var _trail_pm: ParticleProcessMaterial
var _trail_mat: StandardMaterial3D
var _trail_mesh: SphereMesh
var _trail_life: float = 0.2  # spent trail lingers this long after impact
var _gen: int = 0             # invalidates a pending linger when the round is reused

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var trail: GPUParticles3D = $Trail

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	_setup_trail()

func _setup_trail() -> void:
	"""World-space emissive smoke trail left BEHIND to mark the trajectory
	(local_coords=false). Cheap: a few glowing billboard puffs, no GPU particle
	trails (those rendered a vertical tube at the muzzle and cost frames)."""
	if not trail:
		return
	trail.local_coords = false
	trail.one_shot = false
	trail.trail_enabled = false
	if trail.process_material is ParticleProcessMaterial:
		_trail_pm = trail.process_material.duplicate()
		_trail_pm.inherit_velocity_ratio = 0.0
		_trail_pm.initial_velocity_min = 0.0
		_trail_pm.initial_velocity_max = 0.0
		_trail_pm.gravity = Vector3(0, 0.5, 0)  # smoke drifts up slightly
		_trail_pm.spread = 8.0
		trail.process_material = _trail_pm
	if trail.draw_pass_1:
		_trail_mesh = trail.draw_pass_1.duplicate() as SphereMesh
		if _trail_mesh == null:
			_trail_mesh = SphereMesh.new()
			_trail_mesh.radial_segments = 6
			_trail_mesh.rings = 3
		if _trail_mesh.material:
			_trail_mat = _trail_mesh.material.duplicate() as StandardMaterial3D
		else:
			_trail_mat = StandardMaterial3D.new()
			_trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_trail_mat.vertex_color_use_as_albedo = true
		_trail_mesh.material = _trail_mat
		trail.draw_pass_1 = _trail_mesh

func configure(type: int) -> void:
	"""Apply the per-type visuals/physics. Cheap; only rebuilds on type change."""
	ptype = type
	var c: Dictionary = CONFIG[type]
	speed = c["speed"]
	drag = c["drag"]
	gravity_accel = c["gravity"]
	min_speed = c["min_speed"]
	splash_radius = c["splash"]
	tracer_color = c["color"]
	if _cfg_type == type:
		return
	_cfg_type = type
	# Capsule sized to the calibre; long axis baked to -Z (travel) via mesh rotation.
	var cap := CapsuleMesh.new()
	cap.radius = c["radius"]
	cap.height = max(c["length"] - 2.0 * c["radius"], 0.02)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c["color"]
	mat.emission_enabled = true
	mat.emission = c["color"]
	mat.emission_energy_multiplier = c["emission"]
	mat.metallic = 1.0
	mat.roughness = 0.25
	mat.disable_receive_shadows = true
	if mesh_instance:
		mesh_instance.mesh = cap
		mesh_instance.material_override = mat
		mesh_instance.rotation = Vector3(-PI / 2.0, 0, 0)  # capsule +Y -> -Z forward
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var col := CapsuleShape3D.new()
	col.radius = max(c["radius"] + 0.04, 0.08)
	col.height = c["length"]
	if collision_shape:
		collision_shape.shape = col
		collision_shape.rotation = Vector3(-PI / 2.0, 0, 0)
	_trail_life = c["trail_life"]
	if trail:
		trail.amount = c["trail_amount"]
		trail.lifetime = c["trail_life"]  # longer = the trajectory smoke lingers
		if _trail_pm:
			_trail_pm.color = Color(c["color"].r, c["color"].g, c["color"].b, 0.85)
			_trail_pm.scale_min = 0.7
			_trail_pm.scale_max = 1.3
		if _trail_mesh:
			_trail_mesh.radius = c["trail_size"]
			_trail_mesh.height = c["trail_size"] * 2.0
		if _trail_mat:
			_trail_mat.emission_enabled = true  # glow like a hot tracer
			_trail_mat.emission = c["color"]
			_trail_mat.emission_energy_multiplier = c["trail_emission"]

func initialize(spawn_position: Vector3, direction: Vector3, platform_velocity: Vector3 = Vector3.ZERO, shooter: Node = null) -> void:
	"""Position, orient and launch. Inherits the platform's velocity."""
	global_position = spawn_position
	show()
	if mesh_instance:
		mesh_instance.visible = true
	_gen += 1  # invalidate any pending post-impact linger from a prior use
	var dir := direction.normalized()
	if dir.length() > 0.001:
		look_at(global_position + dir, Vector3.UP)
	velocity = dir * speed + platform_velocity
	is_active = true
	time_alive = 0.0
	distance_traveled = 0.0
	_shooter = shooter
	_exclude = [get_rid()]
	if shooter and is_instance_valid(shooter):
		for c in _find_colliders(shooter):
			_exclude.append(c.get_rid())
	if trail:
		trail.restart()
		trail.emitting = true

func _physics_process(delta: float) -> void:
	if not is_active:
		return
	time_alive += delta
	velocity *= exp(-drag * delta)
	velocity.y -= gravity_accel * delta

	var movement := velocity * delta
	var next_position := global_position + movement

	if time_alive >= spawn_grace_period:
		var space := get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(global_position, next_position, collision_mask)
		query.collide_with_areas = true
		query.collide_with_bodies = true
		query.exclude = _exclude
		var hit := space.intersect_ray(query)
		if hit:
			_impact(hit["collider"], hit["position"])
			return

	global_position = next_position
	distance_traveled += Vector2(movement.x, movement.z).length()

	if velocity.length() < min_speed or distance_traveled >= max_distance:
		_despawn()

func _impact(collider: Node, at: Vector3) -> void:
	is_active = false
	global_position = at
	if splash_radius > 0.0:
		_detonate(at)
	else:
		var unit := _owning_unit(collider)
		if unit != null:
			_hit_unit(collider, unit, at)
		else:
			_hit_terrain(at)
	_despawn()

func _on_area_entered(area: Node) -> void:
	if not is_active or time_alive < spawn_grace_period:
		return
	_impact(area, global_position)

func _on_body_entered(_body: Node) -> void:
	if not is_active or time_alive < spawn_grace_period:
		return
	_impact(_body, global_position)

func _hit_terrain(at: Vector3) -> void:
	ImpactEffectPool.spawn_effect(at, Color.SADDLE_BROWN, true, effect_scale, false)

func _hit_unit(hitbox: Node, unit: Node, at: Vector3) -> void:
	var color := tracer_color
	var unit_scale := effect_scale
	if unit.has_meta("player_color"):
		color = unit.get_meta("player_color")
	if unit.has_meta("effect_scale"):
		unit_scale = unit.get_meta("effect_scale")
	ImpactEffectPool.spawn_effect(at, color, false, unit_scale, false)
	UnitCombatState.register_hit(unit, ptype, _region(hitbox))

func _detonate(at: Vector3) -> void:
	"""AA airburst: a coloured blast plus a small radius that registers a hit on
	every distinct unit caught in it (so near-miss flak still counts)."""
	ImpactEffectPool.spawn_effect(at, tracer_color, true, effect_scale, true)
	var space := get_world_3d().direct_space_state
	if not space:
		return
	var shape := SphereShape3D.new()
	shape.radius = splash_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), at)
	query.collision_mask = 3  # terrain (skipped) + unit bodies/hitboxes
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = _exclude
	var seen := {}
	for r in space.intersect_shape(query, 32):
		var unit := _owning_unit(r.collider)
		if unit and not seen.has(unit.get_instance_id()):
			seen[unit.get_instance_id()] = true
			UnitCombatState.register_hit(unit, ptype, _region(r.collider))

func _owning_unit(node: Node) -> Node:
	"""Climb to the unit root (carries unit_type / player_color meta); null = terrain."""
	var n := node
	while n != null:
		if n.has_meta("unit_type") or n.has_meta("player_color"):
			return n
		n = n.get_parent()
	return null

func _region(hitbox: Node) -> int:
	if hitbox and hitbox.has_meta("hit_region"):
		match hitbox.get_meta("hit_region"):
			"turret": return Combat.Region.TURRET
			"body": return Combat.Region.BODY
	return Combat.Region.GENERIC

func _find_colliders(node: Node) -> Array:
	var out: Array = []
	if node is CollisionObject3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_find_colliders(child))
	return out

func _despawn() -> void:
	# Hide the round but leave the trail to fade in place, marking where it went.
	is_active = false
	if trail:
		trail.emitting = false
	if mesh_instance:
		mesh_instance.visible = false
	var g := _gen
	get_tree().create_timer(_trail_life + 0.1).timeout.connect(func(): _finish_linger(g))

func _finish_linger(g: int) -> void:
	if g != _gen:
		return  # the round was already reused; this linger is stale
	hide()
	ProjectilePool.return_projectile.call_deferred(self)
