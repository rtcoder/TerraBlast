extends SceneTree

const Factory = preload("res://scripts/core/rules/match_factory.gd")
var failures := 0

func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)

func _initialize() -> void:
	var script = load("res://scripts/core/bots/bot_planner.gd") if FileAccess.file_exists("res://scripts/core/bots/bot_planner.gd") else null
	check(script != null, "Bot planner exists")
	if script == null:
		quit(1)
		return
	for arena in ["twin_forts", "two_islands"]:
		var runner = Factory.create_match(10, "res://maps/%s.toml" % arena)
		var snapshot: Dictionary = runner.state_snapshot()
		var materials: PackedInt32Array = runner.world.material_ids.duplicate()
		var health: PackedInt32Array = runner.world.health_values.duplicate()
		var first = script.choose(runner)
		var second = script.choose(runner)
		check(first != null and second != null, arena + " produces a command")
		if first == null or second == null:
			continue
		check(first.weapon_id == second.weapon_id and first.aim_direction == second.aim_direction and first.shot_power == second.shot_power, "Deterministic command")
		check(snapshot == runner.state_snapshot() and materials == runner.world.material_ids and health == runner.world.health_values, "Planning does not mutate state or terrain")
		var result: Dictionary = runner.submit(first)
		check(result.ok, arena + " accepts normal command")
		check(runner.statistics[first.player_id].damage > 0, arena + " normal shot damages an enemy")
		check(runner.submit(script.choose(runner, "easy")).ok, arena + " accepts easy command")
	var runner = Factory.create_match()
	var easy = script.new()
	easy.begin(runner, "easy")
	while not easy.finished:
		easy.step(8)
	check(easy.evaluated_candidates == script.EASY_CANDIDATES, "Easy uses declared search budget")
	var tactical = script.new()
	tactical.begin(runner)
	var active = runner.state.get_active_player()
	var enemy = runner.state.players.filter(func(p): return p.team_id != active.team_id)[0]
	var friend = runner.state.players.filter(func(p): return p.team_id == active.team_id and p != active)[0]
	var weapon: Resource = runner.weapons[1]
	var enemy_shot := {"hit": true, "position": enemy.position}
	var self_shot := {"hit": true, "position": active.position}
	check(tactical._score(enemy_shot, weapon, active) > tactical._score(self_shot, weapon, active), "Enemy damage beats own damage")
	var safe_score: float = tactical._score(enemy_shot, weapon, active)
	friend.position = enemy.position
	check(tactical._score(enemy_shot, weapon, active) < safe_score, "Friendly damage penalizes otherwise equal enemy hit")
	runner.reset()
	active = runner.state.get_active_player()
	for player in runner.state.players:
		if player.team_id != active.team_id:
			player.position = active.position + Vector3(20, 0, 0)
	tactical.begin(runner)
	check(tactical.target_id == "red_1", "Equal distance tie resolved by player ID")
	for player in runner.state.players:
		if player.player_id == "red_1":
			player.apply_damage(player.health)
	tactical.begin(runner)
	check(tactical.target_id == "red_2", "Dead enemies skipped")
	runner.reset()
	var planner = script.new()
	planner.begin(runner)
	check(not planner.finished and planner.command == null, "Begin does not evaluate")
	planner.step(0)
	check(planner.evaluated_candidates == 0, "Zero budget does no work")
	planner.step(1)
	check(planner.evaluated_candidates == 1, "One candidate per budget unit")
	planner.step(99999)
	check(planner.evaluated_candidates <= 1 + script.MAX_STEP_CANDIDATES, "Large requested budgets are capped")
	while not planner.finished:
		planner.step(4)
	check(planner.evaluated_candidates == script.NORMAL_CANDIDATES and planner.command != null, "Bounded complete normal search")
	check(planner.evaluated_candidates > easy.evaluated_candidates, "Normal evaluates more candidates than easy")
	runner.state.revision += 1
	check(planner.command == null, "Completed command invalidated by revision before sending")
	for field in ["revision", "turn_id", "generation"]:
		planner.begin(runner)
		runner.state.set(field, runner.state.get(field) + 1)
		planner.step(1)
		check(planner.finished and planner.command == null, "Invalidated by " + field)
	planner.begin(runner)
	runner.reset()
	planner.step(1)
	check(planner.finished and planner.command == null, "Reset invalidates plan")
	for id in runner.state.inventory[runner.state.get_active_player().player_id]:
		runner.state.inventory[runner.state.get_active_player().player_id][id] = 0
	check(script.choose(runner) == null, "No ammo returns null")
	runner.reset()
	for player in runner.state.players:
		player.team_id = 1
	check(script.choose(runner) == null, "No enemies returns null")
	runner.reset()
	runner.state.status = "ended"
	check(script.choose(runner) == null, "Ended game returns null")
	print("BOT OCT16 TESTS: %s" % ("PASS" if failures == 0 else "FAIL %d" % failures))
	quit(0 if failures == 0 else 1)
