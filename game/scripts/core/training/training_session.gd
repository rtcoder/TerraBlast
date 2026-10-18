extends RefCounted
const Store = preload("res://scripts/core/replay/session_store.gd")
const Lessons = preload("res://scripts/core/training/training_lessons.gd")
const History = preload("res://scripts/core/training/attempt_history.gd")
var active := false
var lesson_id := ""
var phase := "ready"
var assistance := "full"
var elapsed_active := 0.0
var attempts: RefCounted = History.new()
var _initial := {}
var _last := {}
var _origin := Vector3.ZERO
var _jumped := false
var _airborne := false
var _aim_stage := 0
var _powers := {}
var _weapons := {}
var _required_weapons := []
var _counter := 0
var _pending := false
var _demonstration := false
var _context := {}
func begin(id: String, snapshot: Dictionary) -> Dictionary:
	if Lessons.get_lesson(id).is_empty(): return {"ok":false,"reason":"Unknown lesson"}
	var decoded: Dictionary = Store.decode(snapshot)
	if not decoded.ok: return decoded
	var player = decoded.runner.state.get_active_player()
	if player == null or decoded.runner.state.status != "playing": return {"ok":false,"reason":"Start a playing local match first"}
	_initial = snapshot.duplicate(true)
	_last.clear()
	active = true
	lesson_id = id
	phase = "ready"
	assistance = "none" if id == "blind_accuracy" else "full"
	elapsed_active = 0
	attempts = History.new()
	_origin = player.position
	_jumped = false
	_airborne = false
	_aim_stage = 0
	_powers.clear()
	_weapons.clear()
	_required_weapons.clear()
	_counter = 0
	_pending = false
	for weapon in decoded.runner.state.inventory[player.player_id]:
		if decoded.runner.state.inventory[player.player_id][weapon] != 0: _required_weapons.append(weapon)
	return decoded
func arm() -> bool:
	if not active or phase == "complete": return false
	phase = "armed"
	return true
func observe_motion(position: Vector3, velocity: Vector3, grounded: bool, accepted_jump: bool) -> void:
	if not active or phase != "armed": return
	if lesson_id == "movement" and Vector2(position.x-_origin.x,position.z-_origin.z).length() >= 3: phase = "complete"
	if accepted_jump: _jumped = true
	if _jumped and not grounded: _airborne = true
	if lesson_id == "jump" and _jumped and _airborne and grounded and velocity.y <= 0: phase = "complete"
func observe_intent(kind: String) -> void:
	if not active or phase != "armed" or lesson_id != "cancel_aim": return
	if kind == "aim": _aim_stage = 1
	elif kind == "charge" and _aim_stage == 1: _aim_stage = 2
	elif kind == "cancel" and _aim_stage == 2: phase = "complete"
func before_shot(snapshot: Dictionary, command: RefCounted, demonstration := false) -> bool:
	if not active or phase != "armed": return false
	var decoded: Dictionary = Store.decode(snapshot)
	if not decoded.ok: return false
	_last = snapshot.duplicate(true)
	var player = decoded.runner.state.get_active_player()
	_context = {"team":player.team_id,"teams":{},"target":player.position}
	var nearest := INF
	for other in decoded.runner.state.players:
		_context.teams[other.player_id] = other.team_id
		if other.is_alive and other.team_id != player.team_id and player.position.distance_squared_to(other.position) < nearest:
			nearest = player.position.distance_squared_to(other.position)
			_context.target = other.position
	_context["weapon"] = command.weapon_id
	_pending = true
	_demonstration = demonstration
	return true
func cancel_pending() -> void: _pending = false
func after_shot(command: RefCounted, result: Dictionary, _unused := {}) -> void:
	if not active or not _pending or not result.get("ok",false): return
	_pending = false
	var enemy := 0
	var friendly := 0
	var impact: Vector3 = _context.target
	for event in result.get("events",[]):
		if event.type == "PlayerDamaged":
			if _context.teams.get(event.player_id) == _context.team: friendly += int(event.amount)
			else: enemy += int(event.amount)
		elif event.type == "ShotResolved": impact = Vector3(event.position[0],event.position[1],event.position[2])
	_counter += 1
	var entry := {"event_id":str(_counter),"weapon":command.weapon_id,"power":command.shot_power,"impact":impact,"distance":impact.distance_to(_context.target),"enemy_damage":enemy,"friendly_damage":friendly,"hit":enemy > 0,"demonstration":_demonstration}
	attempts.append(entry)
	phase = "result"
	if _demonstration: return
	_weapons[command.weapon_id] = true
	if command.shot_power <= 1: _powers["low"] = true
	if command.shot_power >= 3: _powers["high"] = true
	var passed := false
	match lesson_id:
		"accuracy", "wind": passed = enemy > 0
		"safe_fire": passed = enemy > 0 and friendly == 0
		"blind_accuracy": passed = enemy > 0 and assistance == "none"
		"power": passed = _powers.size() == 2
		"weapons": passed = _required_weapons.all(func(id): return _weapons.has(id))
		"streak": passed = attempts.streak() >= 3
		"ammo_budget":
			var summary_data := summary()
			passed = summary_data.attempts <= 3 and summary_data.enemy_damage >= 30 and _weapons.size() == summary_data.attempts
	if passed: phase = "complete"
func tick(delta: float, paused: bool) -> void:
	if active and phase == "armed" and not paused and is_finite(delta) and delta > 0: elapsed_active += minf(delta,1)
func retry_lesson() -> Dictionary:
	var result := begin(lesson_id,_initial.duplicate(true))
	if result.ok: arm()
	return result
func retry_attempt() -> Dictionary:
	if _last.is_empty(): return {"ok":false,"reason":"No previous shot"}
	var result: Dictionary = Store.decode(_last.duplicate(true))
	if result.ok: phase = "armed"
	return result
func summary() -> Dictionary:
	var result := {"lesson":lesson_id,"phase":phase,"attempts":0,"hits":0,"enemy_damage":0,"friendly_damage":0,"seconds":elapsed_active,"best":attempts.best(),"streak":attempts.streak(),"last":{}}
	for attempt in attempts.entries():
		result.last = attempt
		if attempt.demonstration: continue
		result.attempts += 1
		result.hits += 1 if attempt.hit else 0
		result.enemy_damage += attempt.enemy_damage
		result.friendly_damage += attempt.friendly_damage
	return result
func exit() -> void:
	active = false
	_pending = false
	_initial.clear()
	_last.clear()

static func wind_description(value: float) -> String:
	if is_zero_approx(value): return "Wind: calm (0.00)"
	return "Wind: %.2f — %s" % [absf(value),"left ←" if value<0 else "right →"]
