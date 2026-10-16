class_name BotPlanner
extends RefCounted

const Simulation = preload("res://scripts/core/projectiles/projectile_simulation.gd")
const Command = preload("res://scripts/core/turns/player_action_command.gd")
const MAX_STEP_CANDIDATES := 8
const EASY_CANDIDATES := 18
const NORMAL_CANDIDATES := 72

var finished := true
var evaluated_candidates := 0
var target_id := ""
var command: RefCounted:
	get:
		if not _is_current():
			_best = null
			finished = true
		return _best if finished else null
var _runner: RefCounted
var _revision := -1
var _generation := -1
var _turn := -1
var _player_id := ""
var _candidates: Array = []
var _best: RefCounted
var _best_score := -INF

func begin(runner: RefCounted, difficulty: String = "normal") -> void:
	_runner = runner
	_candidates.clear()
	_best = null
	_best_score = -INF
	evaluated_candidates = 0
	target_id = ""
	finished = true
	if runner == null or difficulty not in ["easy", "normal"] or runner.state.status != "playing" or runner.state.time_remaining <= 0:
		return
	var active = runner.state.get_active_player()
	if active == null or not active.is_alive:
		return
	_revision = runner.state.revision
	_generation = runner.state.generation
	_turn = runner.state.turn_id
	_player_id = active.player_id
	var targets: Array = runner.state.players.filter(func(player): return player.is_alive and _is_enemy(player, active))
	targets.sort_custom(func(a, b):
		var da: float = active.position.distance_squared_to(a.position)
		var db: float = active.position.distance_squared_to(b.position)
		return a.player_id < b.player_id if is_equal_approx(da, db) else da < db)
	if targets.is_empty():
		return
	target_id = targets[0].player_id
	var ids: Array = runner.weapons.keys()
	ids.sort()
	var times: Array = [0.6, 1.0, 1.4, 2.0, 3.0, 4.0] if difficulty == "easy" else [0.6, 0.8, 1.0, 1.2, 1.4, 1.7, 2.0, 2.4, 3.0, 3.5, 4.0, 5.0]
	var limit := EASY_CANDIDATES if difficulty == "easy" else NORMAL_CANDIDATES
	var origin: Vector3 = active.position + Vector3.UP * 1.3
	for target in targets.slice(0, 1 if difficulty == "easy" else 2):
		for id in ids:
			if int(runner.state.inventory.get(_player_id, {}).get(id, 0)) == 0:
				continue
			var weapon: Resource = runner.weapons[id]
			if not weapon.validate():
				continue
			for time in times:
				if _candidates.size() >= limit:
					break
				# Inverse discrete ballistic integration; the shared simulator still
				# decides actual impact, including wind, terrain, drill and bounce.
				var dt: float = runner.rules.projectile_step
				var flight: float = maxf(dt, roundf(float(time) / dt) * dt)
				var acceleration := Vector3(runner.rules.wind, -runner.rules.base_gravity * weapon.gravity_scale, 0)
				var velocity: Vector3 = (target.position - Vector3.UP * 0.25 - origin) / flight - acceleration * (flight + dt) * 0.5
				var ratio := 0.0
				if weapon.projectile_speed > weapon.min_projectile_speed:
					ratio = clampf(inverse_lerp(weapon.min_projectile_speed, weapon.projectile_speed, velocity.length()), 0, 1)
				var candidate = Command.new()
				candidate.player_id = _player_id
				candidate.turn_id = _turn
				candidate.generation = _generation
				candidate.weapon_id = id
				candidate.aim_direction = velocity.normalized()
				candidate.shot_power = lerpf(runner.rules.min_shot_power, runner.rules.max_shot_power, ratio)
				_candidates.append(candidate)
	finished = _candidates.is_empty()

func step(candidate_budget: int) -> void:
	if not _is_current():
		_best = null
		finished = true
		return
	if finished:
		return
	var end := mini(_candidates.size(), evaluated_candidates + clampi(candidate_budget, 0, MAX_STEP_CANDIDATES))
	while evaluated_candidates < end:
		var candidate: RefCounted = _candidates[evaluated_candidates]
		var active = _runner.state.get_active_player()
		var weapon: Resource = _runner.weapons[candidate.weapon_id]
		var shot: Dictionary = Simulation.simulate(_runner.world, active.position + Vector3.UP * 1.3, candidate.aim_direction, candidate.shot_power, weapon, _runner.rules, _runner.materials)
		var score := _score(shot, weapon, active)
		if score > _best_score:
			_best_score = score
			_best = candidate
		evaluated_candidates += 1
	finished = evaluated_candidates == _candidates.size()

static func choose(runner: RefCounted, difficulty: String = "normal") -> RefCounted:
	var planner = load("res://scripts/core/bots/bot_planner.gd").new()
	planner.begin(runner, difficulty)
	while not planner.finished:
		planner.step(MAX_STEP_CANDIDATES)
	return planner.command

func _is_current() -> bool:
	if _runner == null:
		return false
	var state = _runner.state
	var active = state.get_active_player()
	return state.status == "playing" and state.time_remaining > 0 and state.revision == _revision and state.generation == _generation and state.turn_id == _turn and active != null and active.is_alive and active.player_id == _player_id

func _is_enemy(player: RefCounted, active: RefCounted) -> bool:
	return player.player_id != active.player_id and (active.team_id == 0 or player.team_id != active.team_id)

func _score(shot: Dictionary, weapon: Resource, active: RefCounted) -> float:
	var score := 0.0
	var nearest := INF
	for player in _runner.state.players:
		if not player.is_alive:
			continue
		var distance: float = player.position.distance_to(shot.position)
		var damage: int = mini(player.health, weapon.damage_at_distance(distance)) if shot.hit else 0
		if _is_enemy(player, active):
			score += damage
			nearest = minf(nearest, distance)
		else:
			score -= damage * 2.0
	# Small deterministic tie breaker guides misses without outweighing damage.
	return score - minf(nearest, 1000.0) * 0.001
