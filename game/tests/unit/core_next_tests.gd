extends SceneTree
var failures := 0
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	var factory = load("res://scripts/core/rules/match_factory.gd")
	var runner = factory.create_match(2)
	check(runner.get("statistics") is Dictionary, "Statistics initialized")
	check(runner.get("history") is Array, "History initialized")
	check(runner.has_method("surrender"), "Authoritative surrender supported")
	check(runner.rules.get("max_turns") == 0, "Unlimited turns default")
	check(runner.rules.get("wind") == 0.0, "Zero wind default")
	check(ResourceLoader.exists("res://scripts/core/rules/rule_presets.gd"), "Preset registry exists")
	check(ResourceLoader.exists("res://scripts/core/voxels/voxel_raycast.gd"), "Shared voxel raycast exists")
	check(ResourceLoader.exists("res://scripts/core/replay/replay_archive.gd"), "Bounded replay archive exists")
	if failures == 0:
		behavior(factory)
	print("core_next: %d failures" % failures)
	quit(1 if failures else 0)
func behavior(factory) -> void:
	var runner = factory.create_match(2)
	var id: String = runner.state.get_active_player().player_id
	var terrain = runner.world.material_ids.duplicate()
	check(runner.surrender(id).ok and runner.state.status == "ended", "Surrender resolves winner")
	check(not runner.surrender(id).ok and runner.world.material_ids == terrain, "Repeat surrender rejected without terrain change")
	runner.reset()
	runner.rules.max_turns = 1
	runner.tick(runner.rules.turn_time)
	check(runner.state.status == "ended" and runner.state.winner_team == 0, "Turn limit draws")
	runner.reset()
	check(runner.state.status == "playing" and runner.history.is_empty() and runner.statistics[id].shots == 0, "Reset clears match metrics")
	var quick = factory.create_match(2,"res://maps/twin_forts.toml","quick")
	var training = factory.create_match(2,"res://maps/twin_forts.toml","training")
	check(quick.rules.turn_time < runner.rules.turn_time and training.state.players[0].health > 100, "Presets affect matches")
	check(factory.create_match(2,"res://maps/twin_forts.toml","invalid") == null, "Unknown preset rejected")
	var world = load("res://scripts/core/voxels/voxel_world_data.gd").new(Vector3i(20,20,20))
	var mats: Dictionary = factory.materials()
	mats[1] = mats[1].duplicate()
	mats[1].is_solid = false
	world.set_voxel(Vector3i(4,4,4),1,100)
	world.set_voxel(Vector3i(6,4,4),2,100)
	var ray = load("res://scripts/core/voxels/voxel_raycast.gd")
	check(ray.first_solid(world,Vector3(0.5,4.5,4.5),Vector3.RIGHT,mats) == Vector3i(6,4,4), "Ray skips nonsolid")
	check(ray.first_solid(world,Vector3.ZERO,Vector3.ZERO,mats) == Vector3i(-1,-1,-1), "Zero ray misses")
	check(ray.first_solid(world,Vector3(0.5,4.5,4.5),Vector3.RIGHT,mats,3) == Vector3i(-1,-1,-1), "Ray distance bounded")
	check(ray.first_solid(world,Vector3(-2,4.5,4.5),Vector3.RIGHT,mats) == Vector3i(6,4,4), "Ray enters from outside bounds")
	world.set_voxel(Vector3i(7,7,7),2,100)
	check(ray.first_solid(world,Vector3(0.5,0.5,0.5),Vector3.ONE,mats) == Vector3i(7,7,7), "Diagonal ray finds first solid")
	var motion = load("res://scripts/core/rules/player_motion.gd")
	check(not motion.blocked(world,Vector3(4.5,4,4.5),mats), "Nonsolid does not block pawn")
	var sim = load("res://scripts/core/projectiles/projectile_simulation.gd")
	var weapon = runner.weapons[1].duplicate()
	weapon.gravity_scale = 0.0
	var shot = sim.simulate(world,Vector3(0.5,4.5,4.5),Vector3.RIGHT,1.0,weapon,runner.rules,mats)
	check(shot.hit and shot.position.x >= 6, "Projectile skips nonsolid")
	runner.rules.wind = 5.0
	var windy = sim.simulate(world,Vector3(10,10,10),Vector3.UP,1.0,weapon,runner.rules,mats)
	check(windy.position.x > 10 and windy == sim.simulate(world,Vector3(10,10,10),Vector3.UP,1.0,weapon,runner.rules,mats), "Wind deterministic positive X")
	runner.rules.wind = -5.0
	var negative = sim.simulate(world,Vector3(10,10,10),Vector3.UP,1.0,weapon,runner.rules,mats)
	check(negative.position.x < 10,"Negative wind accelerates left")
	runner.rules.wind = INF
	check(not runner.rules.validate(),"Nonfinite wind rejected")
	quick.rules.starting_health = 20
	check(factory.create_match(2).rules.starting_health == 100,"Preset instances isolated")
	var multi = factory.create_match(4)
	var active: String = multi.state.get_active_player().player_id
	check(multi.surrender(multi.state.players[1].player_id).ok and multi.state.get_active_player().player_id == active,"Inactive surrender preserves active turn")
	check(not multi.surrender("unknown").ok,"Unknown surrender rejected")
	damage_metrics(factory)
	replay_and_stats(factory)
func replay_and_stats(factory) -> void:
	var runner = factory.create_match(2)
	runner.weapons[1] = runner.weapons[1].duplicate()
	runner.weapons[1].gravity_scale = 0.0
	var recorder = load("res://scripts/core/replay/match_replay.gd").new()
	recorder.capture(runner)
	for i in range(35):
		var cmd = load("res://scripts/core/turns/player_action_command.gd").new()
		cmd.player_id = runner.state.get_active_player().player_id
		cmd.turn_id = runner.state.turn_id
		cmd.weapon_id = 1
		cmd.shot_power = 1
		cmd.aim_direction = Vector3.UP
		check(recorder.submit(runner,cmd).ok,"Shot accepted")
	check(runner.history.size() == 32 and runner.history[0].turn_id == 3,"History drops oldest shot")
	check(runner.statistics.blue_1.shots == 18 and runner.statistics.red_1.shots == 17,"Exact per-player shot totals")
	var archive = load("res://scripts/core/replay/replay_archive.gd")
	var path := "/tmp/core-next-replay.json"
	check(archive.save(path,recorder,runner) == OK,"Archive saved atomically")
	check(archive.load_verified(path).ok,"Archive replay hash matches")
	var file = FileAccess.open(path,FileAccess.READ)
	if file == null:
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	data.recording.actions[0].direction = [0,-1,0]
	file = FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	check(not archive.load_verified(path).ok,"Changed command rejected by expected hash")
	check(not archive.load_verified("/tmp/missing-next-replay.json").ok,"Missing file controlled")
	check(archive.save("/tmp/missing-folder/replay.json",recorder,runner) != OK,"Invalid destination controlled")
	file = FileAccess.open(path,FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	check(not archive.load_verified(path).ok,"Malformed JSON rejected")
	file = FileAccess.open(path,FileAccess.WRITE)
	file.seek(archive.MAX_BYTES)
	file.store_8(0)
	file.close()
	check(archive.load_verified(path).reason == "file_too_large","Oversized archive rejected before parsing")
	DirAccess.remove_absolute(path)
	recorder.capture(runner)
	check(recorder.valid_data(), "Mid-match capture accepts complete shot history")
	check(archive.save(path,recorder,runner) == OK, "Mid-match archive saved")
	check(archive.load_verified(path).ok, "Mid-match history archive roundtrip")
	DirAccess.remove_absolute(path)

func damage_metrics(factory) -> void:
	var runner = factory.create_match(2)
	runner.world = load("res://scripts/core/voxels/voxel_world_data.gd").new(Vector3i(20,20,20))
	runner.world.fill_box(Vector3i.ZERO,Vector3i(20,1,20),3,100)
	runner.world.set_voxel(Vector3i(6,2,4),3,100)
	runner.state.players[0].position = Vector3(2.5,1,4.5)
	runner.state.players[1].position = Vector3(6.5,1,4.5)
	runner.state.players[1].health = 7
	runner.weapons[1] = runner.weapons[1].duplicate()
	runner.weapons[1].gravity_scale = 0.0
	var cmd = load("res://scripts/core/turns/player_action_command.gd").new()
	cmd.player_id = "blue_1"
	cmd.weapon_id = 1
	cmd.aim_direction = Vector3.RIGHT
	cmd.shot_power = 1
	check(runner.submit(cmd).ok,"Damage shot accepted")
	check(runner.statistics.blue_1 == {"shots":1,"hits":1,"damage":7,"kills":1},"Damage capped to victim HP; one hit and kill")
	check(runner.history[0].damage == 7 and runner.history[0].kills == 1,"History carries actual damage and kills")
	var snapshot: Dictionary = runner.state_snapshot()
	snapshot.statistics.blue_1.damage = 999
	check(runner.statistics.blue_1.damage == 7,"Snapshot metrics isolated")
