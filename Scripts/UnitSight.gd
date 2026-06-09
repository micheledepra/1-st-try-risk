extends CanvasLayer
class_name UnitSight

## Reusable gun sight for any controllable unit (tank, AA, fighter).
##
## Two layers, drawn procedurally so each unit gets its own style and stays crisp
## at any resolution / zoom:
##   * A FIXED reticle (circle + cross + range ticks, or concentric rings) centred
##     on the BORESIGHT — the vanishing point of the gun's aim direction. This is
##     where the gun points "at infinity" (parallax- and elevation-correct).
##   * A floating PIPPER drawn at the TRUE ballistic impact point. It is found by
##     replaying the exact same gravity+drag integration BaseProjectile uses, from
##     the muzzle, until the swept ray hits terrain/a unit. The gap between pipper
##     and boresight IS the bullet drop + muzzle/camera parallax — so aligning the
##     pipper on a target guarantees the round lands there.
##
## The owning controller supplies get_aim_ray() (origin/dir/platform_velocity/ptype),
## the SAME values it feeds ProjectilePool.spawn(), so the sight can never drift out
## of sync with the gun.

const BaseProjectileScript = preload("res://Scripts/BaseProjectile.gd")
const UnitViewControllerScript = preload("res://Scripts/UnitViewController.gd")

enum Style { TANK, AA, FIGHTER }

# === Tunables =============================================================
@export var sight_color: Color = Color(0.55, 1.0, 0.6, 0.85)   # phosphor green reticle
@export var pipper_color: Color = Color(1.0, 0.82, 0.2, 0.95)  # amber true-impact dot
@export_range(0.0, 1.0) var pipper_fill_alpha: float = 0.5     # centre dot opacity (see target through it)
@export var line_width: float = 1.5
# Ballistic preview integration (matches BaseProjectile._physics_process).
@export var sim_max_steps: int = 90
@export var sim_dt: float = 1.0 / 60.0

var style: int = Style.TANK

# === Wiring (set in bind()) ==============================================
var _view: UnitViewControllerScript = null
var _aim_provider: Object = null      # must expose get_aim_ray() -> Dictionary
var _exclude_rids: Array = []

# === Per-frame computed ==================================================
var _reticle: Reticle = null
var _boresight: Vector2 = Vector2.ZERO
var _pipper: Vector2 = Vector2.ZERO
var _show_fixed: bool = false
var _show_pipper: bool = false
var _zoom: float = 1.0


## Inner Control that owns the actual _draw() pass; delegates back to the sight.
class Reticle extends Control:
	var sight: UnitSight = null
	func _draw() -> void:
		if sight != null:
			sight._render(self)


func _ready() -> void:
	layer = 2  # above the 3D viewport (and the fighter HUD's default layer)
	_reticle = Reticle.new()
	_reticle.sight = self
	_reticle.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reticle.visible = false
	add_child(_reticle)


func bind(unit: Node3D, view_controller: UnitViewControllerScript, aim_provider: Object, sight_style: int) -> void:
	_view = view_controller
	_aim_provider = aim_provider
	style = sight_style
	_exclude_rids = _gather_colliders(unit)  # so the preview ray never hits our own unit


func _process(_delta: float) -> void:
	if _reticle == null:
		return
	if _view == null or _aim_provider == null or not _aim_provider.has_method("get_aim_ray"):
		_set_visible(false)
		return
	# Draw ONLY when this unit's camera is the one actually rendering the viewport.
	# Exactly one Camera3D is current at a time, so this guarantees a single sight
	# even in test scenes with many controllable units and no ModeManager.
	var cam: Camera3D = _view.get_active_camera()
	var vp := get_viewport()
	if cam == null or vp == null or vp.get_camera_3d() != cam:
		_set_visible(false)
		return

	var ray: Dictionary = _aim_provider.get_aim_ray()
	var origin: Vector3 = ray["origin"]
	var dir: Vector3 = (ray["dir"] as Vector3).normalized()
	var plat_vel: Vector3 = ray.get("platform_velocity", Vector3.ZERO)
	var ptype: int = ray["ptype"]

	# Boresight: vanishing point of the gun direction. The fixed reticle only makes
	# sense screen-locked in first person; in follow view we show just the pipper.
	var far_point: Vector3 = origin + dir * 100000.0
	_show_fixed = _view.get_view() == UnitViewControllerScript.View.FIRST_PERSON and not cam.is_position_behind(far_point)
	if _show_fixed:
		_boresight = cam.unproject_position(far_point)

	# Pipper: true ballistic impact, projected to screen.
	var impact: Dictionary = _simulate_impact(origin, dir, plat_vel, ptype)
	_show_pipper = impact["hit"] and not cam.is_position_behind(impact["point"])
	if _show_pipper:
		_pipper = cam.unproject_position(impact["point"])

	# Keep tick spacing angularly constant as the RMB aim narrows the FOV.
	var base_fov: float = _view.get_base_fov()
	_zoom = clamp(base_fov / max(cam.fov, 1.0), 0.5, 4.0)

	_set_visible(_show_fixed or _show_pipper)
	if _reticle.visible:
		_reticle.queue_redraw()


func _set_visible(v: bool) -> void:
	if _reticle.visible != v:
		_reticle.visible = v


# === Ballistic preview ====================================================

func _simulate_impact(origin: Vector3, dir: Vector3, plat_vel: Vector3, ptype: int) -> Dictionary:
	"""Replay BaseProjectile's exact integration until the swept ray hits something
	or the round slows below min_speed. Returns the impact (or end-of-flight) point."""
	if not BaseProjectileScript.CONFIG.has(ptype):
		return {"hit": false, "point": origin}
	var cfg: Dictionary = BaseProjectileScript.CONFIG[ptype]
	var drag: float = cfg["drag"]
	var grav: float = cfg["gravity"]
	var min_speed: float = cfg["min_speed"]

	var space := get_viewport().find_world_3d().direct_space_state if get_viewport() else null
	var pos: Vector3 = origin
	var vel: Vector3 = dir * float(cfg["speed"]) + plat_vel
	var t: float = 0.0
	const GRACE := 0.01  # BaseProjectile.spawn_grace_period: clears the muzzle before colliding

	for _i in sim_max_steps:
		t += sim_dt
		vel *= exp(-drag * sim_dt)
		vel.y -= grav * sim_dt
		var next_pos: Vector3 = pos + vel * sim_dt
		if t >= GRACE and space != null:
			var q := PhysicsRayQueryParameters3D.create(pos, next_pos, 3)  # terrain (1) + unit hitboxes (2)
			q.collide_with_areas = true
			q.collide_with_bodies = true
			q.exclude = _exclude_rids
			var hit := space.intersect_ray(q)
			if hit:
				return {"hit": true, "point": hit["position"]}
		pos = next_pos
		if vel.length() < min_speed:
			break
	return {"hit": true, "point": pos}  # nothing struck in range: mark the end of flight


# === Drawing ==============================================================

func _render(c: Control) -> void:
	if _show_fixed:
		match style:
			Style.FIGHTER:
				_draw_fighter(c, _boresight)
			_:  # TANK and AA share the ranged-tick reticle
				_draw_tank(c, _boresight)
	if _show_pipper:
		_draw_pipper(c, _pipper)


func _draw_tank(c: Control, ctr: Vector2) -> void:
	"""Circle + centre cross + stadia ticks marking distance on each axis."""
	var r: float = 26.0 * _zoom
	var arm: float = 78.0 * _zoom
	var gap: float = 7.0 * _zoom
	var tick_spacing: float = 18.0 * _zoom
	var tick_len: float = 6.0 * _zoom

	c.draw_arc(ctr, r, 0.0, TAU, 48, sight_color, line_width, true)
	# Cross with a clear centre.
	c.draw_line(ctr + Vector2(-arm, 0), ctr + Vector2(-gap, 0), sight_color, line_width, true)
	c.draw_line(ctr + Vector2(gap, 0), ctr + Vector2(arm, 0), sight_color, line_width, true)
	c.draw_line(ctr + Vector2(0, -arm), ctr + Vector2(0, -gap), sight_color, line_width, true)
	c.draw_line(ctr + Vector2(0, gap), ctr + Vector2(0, arm), sight_color, line_width, true)
	# Distance ticks ("sticks") on the horizontal and vertical lines.
	for k in range(1, 4):
		var off: float = float(k) * tick_spacing
		# Horizontal axis -> vertical ticks.
		c.draw_line(ctr + Vector2(off, -tick_len), ctr + Vector2(off, tick_len), sight_color, line_width)
		c.draw_line(ctr + Vector2(-off, -tick_len), ctr + Vector2(-off, tick_len), sight_color, line_width)
		# Vertical axis -> horizontal ticks.
		c.draw_line(ctr + Vector2(-tick_len, off), ctr + Vector2(tick_len, off), sight_color, line_width)
		c.draw_line(ctr + Vector2(-tick_len, -off), ctr + Vector2(tick_len, -off), sight_color, line_width)
	c.draw_circle(ctr, 1.5 * _zoom, sight_color)


func _draw_fighter(c: Control, ctr: Vector2) -> void:
	"""Concentric ranging rings + a small centre cross (deflection-shooting aid)."""
	var radii: Array = [14.0, 26.0, 40.0]
	for rr in radii:
		c.draw_arc(ctr, float(rr) * _zoom, 0.0, TAU, 40, sight_color, line_width, true)
	var arm: float = 52.0 * _zoom
	var gap: float = 6.0 * _zoom
	c.draw_line(ctr + Vector2(-arm, 0), ctr + Vector2(-gap, 0), sight_color, line_width, true)
	c.draw_line(ctr + Vector2(gap, 0), ctr + Vector2(arm, 0), sight_color, line_width, true)
	c.draw_line(ctr + Vector2(0, -arm), ctr + Vector2(0, -gap), sight_color, line_width, true)
	c.draw_line(ctr + Vector2(0, gap), ctr + Vector2(0, arm), sight_color, line_width, true)
	c.draw_circle(ctr, 1.5 * _zoom, sight_color)


func _draw_pipper(c: Control, p: Vector2) -> void:
	"""The true-impact marker: a translucent centre dot (so it never hides the target)
	inside a solid ring + tiny ticks, distinct from the reticle."""
	var ring: float = 6.0 * _zoom
	var fill := Color(pipper_color.r, pipper_color.g, pipper_color.b, pipper_color.a * pipper_fill_alpha)
	c.draw_circle(p, 2.5 * _zoom, fill)
	c.draw_arc(p, ring, 0.0, TAU, 24, pipper_color, line_width, true)
	var t: float = 3.0 * _zoom
	c.draw_line(p + Vector2(-ring - t, 0), p + Vector2(-ring, 0), pipper_color, line_width)
	c.draw_line(p + Vector2(ring, 0), p + Vector2(ring + t, 0), pipper_color, line_width)
	c.draw_line(p + Vector2(0, -ring - t), p + Vector2(0, -ring), pipper_color, line_width)
	c.draw_line(p + Vector2(0, ring), p + Vector2(0, ring + t), pipper_color, line_width)


# === Helpers =============================================================

func _gather_colliders(node: Node) -> Array:
	var out: Array = []
	if node is CollisionObject3D:
		out.append((node as CollisionObject3D).get_rid())
	for child in node.get_children():
		out.append_array(_gather_colliders(child))
	return out
