extends Node

## UnitCombatState - Autoload Singleton (the combat "brain")
##
## Single sink for every projectile hit. Tracks per-unit, time-windowed and
## cumulative hit counts per projectile type, and resolves them against the
## damage matrix into visual feedback (flash / static-hold via UnitGlowEffect)
## and independent control locks (turret / move / fire) or a kill.
##
## Projectiles call register_hit(unit, projectile_type, region) and nothing else.
## Controllers query is_locked(unit, channel) / is_dead(unit) at their input sites,
## and may implement apply_kill() / perturb_controls(seconds) for unit-specific
## death / stagger behaviour (e.g. an aircraft jamming its surfaces into a spin).

# --- Shared enums (referenced project-wide as UnitCombatState.PType.* etc.) ---
enum PType { CANNON, MG, AA }              # projectile types
enum Region { GENERIC, TURRET, BODY }      # which part of a unit was struck
enum Channel { MOVE, TURRET, FIRE }        # independently lockable control channels

# Unit type strings stored on the unit root as meta "unit_type"
const UNIT_TANK := "tank"
const UNIT_PLANE := "plane"
const UNIT_AA := "aa"

# Feedback tuning
const FLASH_TIMES := 3            # "flash N times" blink count
const FLASH_PERIOD := 0.18        # seconds per on/off blink cycle
const KILL_FLASH_SECONDS := 7.0   # "static flash for 7 seconds" on a kill
const BLOCK_SECONDS := 7.0        # default control-lock duration on incapacitation
const PERTURB_SECONDS := 1.0      # plane "random control switch / lose control" window

# Per-unit combat record, keyed by instance id.
#   { type:String, dead:bool, cannon:int, mg:Array[int], aa:Array[int],
#     fired:Dictionary, jolt_t:int }
var _state: Dictionary = {}
# Per-unit control locks, keyed by instance id: { Channel -> unlock_time_msec }
var _locks: Dictionary = {}

func _ready() -> void:
	pass

# --- Public API -------------------------------------------------------------

func register_hit(unit: Node, projectile_type: int, region: int = Region.GENERIC) -> void:
	"""Record one confirmed projectile hit on `unit` and resolve the matrix."""
	if unit == null or not is_instance_valid(unit):
		return
	var s: Dictionary = _get_state(unit)
	if s["dead"]:
		return
	var now: int = Time.get_ticks_msec()
	match projectile_type:
		PType.CANNON: s["cannon"] += 1
		PType.MG: s["mg"].append(now)
		PType.AA: s["aa"].append(now)

	match s["type"]:
		UNIT_TANK: _resolve_tank(unit, s, projectile_type, region, now)
		UNIT_PLANE: _resolve_plane(unit, s, projectile_type, now)
		UNIT_AA: _resolve_aa(unit, s, projectile_type, now)
		_: _resolve_tank(unit, s, projectile_type, region, now)

func is_locked(unit: Node, channel: int) -> bool:
	"""True if `channel` is currently blocked (or the unit is dead)."""
	if unit == null or not is_instance_valid(unit):
		return false
	var id := unit.get_instance_id()
	if _state.has(id) and _state[id]["dead"]:
		return true
	if not _locks.has(id):
		return false
	return Time.get_ticks_msec() < int(_locks[id].get(channel, 0))

func is_dead(unit: Node) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	var id := unit.get_instance_id()
	return _state.has(id) and _state[id]["dead"]

func reset_unit(unit: Node) -> void:
	"""Clear all combat state for a unit (call on pool return / despawn)."""
	if unit == null:
		return
	var id := unit.get_instance_id()
	_state.erase(id)
	_locks.erase(id)
	if Engine.has_singleton("UnitGlowEffect") or get_node_or_null("/root/UnitGlowEffect"):
		UnitGlowEffect.clear(unit)

# --- Matrix resolution ------------------------------------------------------

func _resolve_tank(unit: Node, s: Dictionary, p: int, region: int, now: int) -> void:
	match p:
		PType.CANNON:
			# First 2 cannon hits: flash 3x + a region-specific 7s lock. 3rd hit: kill.
			if s["cannon"] >= 3:
				_kill(unit, s)
			else:
				_flash3(unit)
				if region == Region.TURRET:
					_lock(unit, Channel.TURRET, BLOCK_SECONDS)
				else:
					_lock(unit, Channel.MOVE, BLOCK_SECONDS)
		PType.MG:
			# 25 in <3s -> block movement + flash 3x.  50 in <6s -> kill.
			if _recent(s["mg"], now, 6000) >= 50:
				_kill(unit, s)
			elif _recent(s["mg"], now, 3000) >= 25 and _once(s, "mg_move"):
				_flash3(unit)
				_lock(unit, Channel.MOVE, BLOCK_SECONDS)
		PType.AA:
			# 25 in <3s -> incapacitate movement + static flash 3s.  50 in <5s -> kill.
			if _recent(s["aa"], now, 5000) >= 50:
				_kill(unit, s)
			elif _recent(s["aa"], now, 3000) >= 25 and _once(s, "aa_move"):
				_hold(unit, 3.0)
				_lock(unit, Channel.MOVE, 3.0)

func _resolve_plane(unit: Node, s: Dictionary, p: int, now: int) -> void:
	match p:
		PType.CANNON:
			_kill(unit, s)  # direct kill -> static flash 7s + spin (apply_kill)
		PType.MG:
			# 10 in 2s -> flash 3x + 1s control jolt.  50 in <10s -> kill.
			if _recent(s["mg"], now, 10000) >= 50:
				_kill(unit, s)
			elif _recent(s["mg"], now, 2000) >= 10 and _jolt_ready(s, now):
				_flash3(unit)
				_perturb(unit)
		PType.AA:
			# 5 in 5s -> flash 3x + 1s lose-control.  10 in 5s -> kill.
			if _recent(s["aa"], now, 5000) >= 10:
				_kill(unit, s)
			elif _recent(s["aa"], now, 5000) >= 5 and _jolt_ready(s, now):
				_flash3(unit)
				_perturb(unit)

func _resolve_aa(unit: Node, s: Dictionary, p: int, now: int) -> void:
	match p:
		PType.CANNON:
			_kill(unit, s)  # direct kill
		PType.MG:
			# 10 in 3s -> flash 3x + block turret & firing.  30 in <6s -> kill.
			if _recent(s["mg"], now, 6000) >= 30:
				_kill(unit, s)
			elif _recent(s["mg"], now, 3000) >= 10 and _once(s, "mg_incap"):
				_flash3(unit)
				_lock(unit, Channel.TURRET, BLOCK_SECONDS)
				_lock(unit, Channel.FIRE, BLOCK_SECONDS)
		PType.AA:
			# 10 in 5s -> flash 3x + block movement & firing.  30 in 5s -> kill.
			if _recent(s["aa"], now, 5000) >= 30:
				_kill(unit, s)
			elif _recent(s["aa"], now, 5000) >= 10 and _once(s, "aa_incap"):
				_flash3(unit)
				_lock(unit, Channel.MOVE, BLOCK_SECONDS)
				_lock(unit, Channel.FIRE, BLOCK_SECONDS)

# --- Effect helpers ---------------------------------------------------------

func _kill(unit: Node, s: Dictionary) -> void:
	s["dead"] = true
	_hold(unit, KILL_FLASH_SECONDS)
	# Lock everything (dead units are blocked regardless, but make it explicit).
	var far := 3600.0
	_lock(unit, Channel.MOVE, far)
	_lock(unit, Channel.TURRET, far)
	_lock(unit, Channel.FIRE, far)
	if unit.has_method("apply_kill"):
		unit.apply_kill()

func _flash3(unit: Node) -> void:
	UnitGlowEffect.flash(unit, _color(unit), FLASH_TIMES, FLASH_PERIOD)

func _hold(unit: Node, seconds: float) -> void:
	UnitGlowEffect.hold(unit, _color(unit), seconds)

func _perturb(unit: Node) -> void:
	if unit.has_method("perturb_controls"):
		unit.perturb_controls(PERTURB_SECONDS)

func _lock(unit: Node, channel: int, seconds: float) -> void:
	var id := unit.get_instance_id()
	if not _locks.has(id):
		_locks[id] = {}
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	_locks[id][channel] = max(int(_locks[id].get(channel, 0)), until)

func _color(unit: Node) -> Color:
	if unit.has_meta("player_color"):
		return unit.get_meta("player_color")
	return Color.WHITE

# --- Bookkeeping ------------------------------------------------------------

func _get_state(unit: Node) -> Dictionary:
	var id := unit.get_instance_id()
	if not _state.has(id):
		var t: String = UNIT_TANK
		if unit.has_meta("unit_type"):
			t = unit.get_meta("unit_type")
		_state[id] = {
			"type": t,
			"dead": false,
			"cannon": 0,
			"mg": [],
			"aa": [],
			"fired": {},
			"jolt_t": -100000,
		}
	return _state[id]

func _recent(times: Array, now: int, window_ms: int) -> int:
	"""Count (and lazily prune) timestamps within the last window_ms."""
	var cutoff := now - window_ms
	while times.size() > 0 and int(times[0]) < cutoff:
		times.pop_front()
	return times.size()

func _once(s: Dictionary, key: String) -> bool:
	"""Fire a non-fatal threshold at most once until the unit recovers/dies."""
	if s["fired"].has(key):
		return false
	s["fired"][key] = true
	return true

func _jolt_ready(s: Dictionary, now: int) -> bool:
	"""Debounce repeated 1s control-jolts so a stream doesn't spam them."""
	if now - int(s["jolt_t"]) < 2000:
		return false
	s["jolt_t"] = now
	return true
