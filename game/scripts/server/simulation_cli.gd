extends Node
## Seeded, render-free scenario runner for reproducible diagnostics.
const BotPlanner = preload("res://scripts/core/bots/bot_planner.gd")
const Replay = preload("res://scripts/core/replay/match_replay.gd")
const Archive = preload("res://scripts/core/replay/replay_archive.gd")

func _ready() -> void:
	var runner = load("res://scripts/core/rules/match_factory.gd").create_match(int(GameConfig.argument("--players", "2")), GameConfig.map_path(), GameConfig.argument("--preset", "classic"))
	if runner == null:
		printerr("Arena could not be generated")
		get_tree().quit(2)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(GameConfig.argument("--seed", "1"))
	var limit := int(GameConfig.argument("--shots", "20"))
	var difficulty: String = GameConfig.argument("--bots", "")
	var record_path: String = GameConfig.argument("--record", "")
	var recorder = Replay.new() if not record_path.is_empty() else null
	if recorder != null:
		recorder.capture(runner)
	var accepted := 0
	var deltas := 0
	for index in limit:
		if runner.state.status != "playing":
			break
		var command = BotPlanner.choose(runner, difficulty) if not difficulty.is_empty() else _seeded_command(runner, rng)
		if command == null:
			break
		var result: Dictionary = recorder.submit(runner, command) if recorder != null else runner.submit(command)
		if not result.ok:
			printerr("Simulation rejected command: " + str(result))
			get_tree().quit(1)
			return
		accepted += 1
		deltas += result.deltas.size()
	var checksum := HashingContext.new()
	checksum.start(HashingContext.HASH_SHA256)
	checksum.update(runner.world.material_ids.to_byte_array())
	checksum.update(runner.world.health_values.to_byte_array())
	var summary := JSON.stringify({"map": GameConfig.argument("--map", "twin_forts"), "seed": rng.seed, "shots": accepted, "bot_difficulty": difficulty, "bot_decisions": accepted if not difficulty.is_empty() else 0, "deltas": deltas, "terrain_hash": checksum.finish().hex_encode(), "state": runner.state_snapshot()})
	print(summary)
	var output: String = GameConfig.argument("--output", "")
	if not output.is_empty():
		var error: Error = load("res://scripts/server/utility_cli.gd").write_atomic(output, summary)
		if error != OK:
			printerr("Cannot write summary: " + error_string(error))
			get_tree().quit(2)
			return
	if recorder != null:
		var error: Error = Archive.save(record_path, recorder, runner)
		if error != OK:
			printerr("Cannot write replay: " + error_string(error))
			get_tree().quit(2)
			return
	get_tree().quit(0)

func _seeded_command(runner: RefCounted, rng: RandomNumberGenerator) -> RefCounted:
	var active = runner.state.get_active_player()
	var target = null
	for player in runner.state.players:
		if player.is_alive and player.team_id != active.team_id:
			target = player
			break
	if target == null:
		return null
	var command = load("res://scripts/core/turns/player_action_command.gd").new()
	command.player_id = active.player_id
	command.turn_id = runner.state.turn_id
	command.generation = runner.state.generation
	command.weapon_id = 1
	command.aim_direction = (target.position - active.position + Vector3.UP * rng.randf_range(3.0, 15.0)).normalized()
	command.shot_power = rng.randf_range(0.25, 0.6)
	return command
