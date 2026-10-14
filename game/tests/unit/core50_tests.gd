extends SceneTree
const Motion = preload("res://scripts/core/rules/player_motion.gd")
const Sim = preload("res://scripts/core/projectiles/projectile_simulation.gd")
var failures := 0
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	var rules = load("res://assets/config/game_rules.tres").duplicate()
	var weapon = load("res://assets/config/weapons/bazooka.tres").duplicate()
	rules.sweep_step = 0.00000001
	check(not rules.validate(), "Reject unbounded simulation cost")
	rules = load("res://assets/config/game_rules.tres").duplicate()
	weapon.projectile_speed = 1e9
	check(not weapon.validate(), "Reject unbounded projectile speed")
	var world = load("res://scripts/core/voxels/voxel_world_data.gd").new(Vector3i(24,24,24))
	world.fill_box(Vector3i.ZERO, Vector3i(24,1,24), 1,100)
	world.fill_box(Vector3i(6,1,0), Vector3i(7,12,24), 1,100)
	var player = load("res://scripts/core/rules/player_state.gd").new()
	player.position = Vector3(5,1,5)
	Motion.move(world, player, Vector3.ZERO, Vector2(0,1), PI/2, false, 0.3, rules)
	check(player.position.x < 6 and player.position.y < 2, "Wall blocks motion without roof teleport")
	player.position = Vector3(3,1,3)
	world.fill_box(Vector3i(2,3,2), Vector3i(5,4,5), 1,100)
	Motion.move(world, player, Vector3.ZERO, Vector2.ZERO, 0, true, 0.2, rules)
	check(player.position.y <= 1.21, "Jump respects headroom")
	weapon = load("res://assets/config/weapons/bazooka.tres").duplicate()
	check(weapon.get("player_damage_radius") != null, "Explicit player damage radius")
	check(weapon.has_method("damage_at_distance"), "Configurable player damage falloff")
	var catalog = load("res://scripts/core/weapons/weapon_catalog.gd")
	check(catalog.has_method("from_configs"), "Catalog rejects duplicate IDs and codes")
	var runner = load("res://scripts/core/rules/match_factory.gd").create_match()
	check(runner.state_snapshot().get("max_shot_power") == runner.rules.max_shot_power, "Snapshot carries configured maximum shot power")
	check(not runner.submit(null).ok, "Null command rejected safely")
	weapon.player_damage_radius = 10.0
	weapon.player_damage = 100
	weapon.player_damage_falloff = 2.0
	check(weapon.damage_at_distance(5.0) == 25 and weapon.damage_at_distance(10.0) == 0, "Falloff exponent and radius control damage")
	check(catalog.from_configs([weapon, weapon.duplicate()]).is_empty(), "Duplicate weapon ID rejected")
	var duplicate = weapon.duplicate()
	duplicate.id = 99
	check(catalog.from_configs([weapon, duplicate]).is_empty(), "Duplicate weapon code rejected")
	player.position = Vector3(5,1,5)
	var old_position: Vector3 = player.position
	runner.world = world
	runner.apply_knockback(player, Vector3(4,1,5), weapon)
	check(player.position.x < 6 and player.position.x > old_position.x, "Knockback moves pawn but wall blocks it")
	player.position = Vector3(3,8,8)
	runner.state.players = [player]
	runner.settle_players()
	check(player.position.y >= 1 and player.position.y < 1.2, "Settle lands on surviving support")
	world.fill_box(Vector3i(0,0,0), Vector3i(5,1,24), 0,0)
	runner.settle_players()
	check(not player.is_alive, "Unsupported pawn dies before next turn")
	check(ResourceLoader.exists("res://scripts/core/replay/match_replay.gd"), "Replay module exists")
	_test_replay_validation()
	_test_motion_edges()
	_test_drill_settle()
	_test_replay()
	_test_simulation()
	print("Core50 tests: %d failures" % failures)
	quit(1 if failures else 0)

func _test_simulation() -> void:
	var rules = load("res://assets/config/game_rules.tres").duplicate()
	var weapon = load("res://assets/config/weapons/bazooka.tres").duplicate()
	var world = load("res://scripts/core/voxels/voxel_world_data.gd").new(Vector3i(24,24,24))
	weapon.gravity_scale = 0.5
	rules.base_gravity = 24
	var shot: Dictionary = Sim.simulate(world, Vector3(12,12,12), Vector3.UP, 0.25, weapon, rules)
	check(is_equal_approx(shot.path[1].y, 12.0 + (10.0 - 12.0/30)/30), "Global gravity multiplied by weapon scale")
	var expensive_rules = rules.duplicate()
	expensive_rules.max_projectile_lifetime = 20
	expensive_rules.sweep_step = 0.05
	var fast = weapon.duplicate()
	fast.projectile_speed = 200
	fast.gravity_scale = 0
	var bounded: Dictionary = Sim.simulate(world, Vector3(12,12,12), Vector3.UP, 4.0, fast, expensive_rules)
	check(bounded.reason == "simulation_budget", "Hard sample budget bounds legal worst case")
	world.fill_box(Vector3i(0,0,0), Vector3i(24,1,24), 3,255)
	world.fill_box(Vector3i(12,0,0), Vector3i(13,24,24), 3,255)
	weapon = load("res://assets/config/weapons/grenade.tres").duplicate()
	weapon.fuse_time = 0.05
	var short_fuse: Dictionary = Sim.simulate(world, Vector3(5,10,5), Vector3.UP, 0.25, weapon, rules)
	var expected_y := 10.0 + (10.0 - 24.0/30.0)/30.0 + (10.0 - 24.0*0.05)*(0.05-1.0/30.0)
	check(is_equal_approx(short_fuse.position.y, expected_y), "Fuse ends at exact configured time between fixed ticks")
	weapon.fuse_time = 3.0
	var first: Dictionary = Sim.simulate(world, Vector3(11,2,12), Vector3(1,-1,0), 0.25, weapon, rules)
	var second: Dictionary = Sim.simulate(world, Vector3(11,2,12), Vector3(1,-1,0), 0.25, weapon, rules)
	check(first == second and first.reason == "fuse", "Corner grenade deterministic and respects fuse")
	for point in first.path:
		check(world.get_material_id(Vector3i(floori(point.x),floori(point.y),floori(point.z))) == 0, "Grenade never enters floor or wall")

func _test_replay() -> void:
	if not ResourceLoader.exists("res://scripts/core/replay/match_replay.gd"):
		return
	var replay = load("res://scripts/core/replay/match_replay.gd").new()
	var runner = load("res://scripts/core/rules/match_factory.gd").create_match()
	replay.capture(runner)
	var command = load("res://scripts/core/turns/player_action_command.gd").new()
	command.player_id = runner.state.get_active_player().player_id
	command.weapon_id = 1
	command.aim_direction = Vector3.DOWN
	command.shot_power = 1
	replay.submit(runner, command)
	replay.tick(runner, 46.0)
	replay.move(runner, Vector3.ZERO, Vector2(0,1), 0.7, false, 0.1)
	var expected: String = replay.state_hash(runner)
	var serialized: String = JSON.stringify(replay.data)
	replay.data = JSON.parse_string(serialized)
	var restored = replay.replay()
	check(restored != null and restored.state.get_active_player().rotation.is_equal_approx(runner.state.get_active_player().rotation), "Replay preserves facing after movement")
	check(restored != null and restored.state.players[0].rotation.is_equal_approx(runner.state.players[0].rotation), "Replay preserves spawn facing")
	check(restored != null and replay.state_hash(restored) == expected, "JSON replay reproduces arena HP positions inventory and turn hash")

func _test_drill_settle() -> void:
	var world = load("res://scripts/core/voxels/voxel_world_data.gd").new(Vector3i(24,24,24))
	world.set_voxel(Vector3i(3,0,5),1,100)
	world.set_voxel(Vector3i(10,2,5),1,100)
	var players := []
	for i in range(2):
		var player = load("res://scripts/core/rules/player_state.gd").new()
		player.player_id = str(i)
		player.team_id = i+1
		player.position = Vector3(3.5,1,5.5) if i == 0 else Vector3(10.5,3,5.5)
		players.append(player)
	var weapon = load("res://assets/config/weapons/drill_missile.tres").duplicate()
	weapon.gravity_scale = 0
	var runner = load("res://scripts/core/rules/match_runner.gd").new(world,load("res://scripts/core/rules/match_factory.gd").materials(),players,load("res://assets/config/game_rules.tres"),{3: weapon})
	var command = load("res://scripts/core/turns/player_action_command.gd").new()
	command.player_id = "0"
	command.weapon_id = 3
	command.aim_direction = Vector3.RIGHT
	command.shot_power = 4
	var result: Dictionary = runner.submit(command)
	check(result.ok and not runner.state.players[1].is_alive and runner.state.status == "ended", "Drill terrain changes settle victims even when projectile exits arena")

func _test_replay_validation() -> void:
	var replay = load("res://scripts/core/replay/match_replay.gd").new()
	replay.capture(load("res://scripts/core/rules/match_factory.gd").create_match())
	var valid: Dictionary = replay.data.duplicate(true)
	for mutation in ["version", "action", "numeric", "dimensions", "terrain", "material", "weapon", "players", "inventory", "command", "script", "extra_action_field", "null_config", "fractional_hp", "rotation", "ammo", "missing"]:
		replay.data = valid.duplicate(true)
		match mutation:
			"version": replay.data.version = 99
			"action": replay.data.actions.append({"type": "surprise"})
			"numeric": replay.data.actions.append({"type": "tick", "delta": INF})
			"dimensions": replay.data.size = [9999999,1,1]
			"terrain": replay.data.terrain.pop_back()
			"material": replay.data.terrain[0] = 999
			"weapon": replay.data.weapons.append(replay.data.weapons[0].duplicate())
			"players": replay.data.state.players[1].id = replay.data.state.players[0].id
			"inventory": replay.data.state.inventory.clear()
			"command": replay.data.actions.append({"type": "shot", "player_id": "wrong"})
			"script": replay.data.rules.script = "res://scripts/client/main.gd"
			"extra_action_field": replay.data.actions.append({"type": "tick", "delta": 1, "extra": true})
			"null_config": replay.data.weapons[0] = null
			"fractional_hp": replay.data.health[0] = 0.5
			"rotation": replay.data.state.players[0].rotation = [0,0,0,0,0,0,0,0,0]
			"ammo": replay.data.state.inventory[replay.data.state.players[0].id][1] = 999
			"missing": replay.data = {"version": 1}
		check(replay.replay() == null, "Malformed replay rejected: " + mutation)

func _test_motion_edges() -> void:
	var world = load("res://scripts/core/voxels/voxel_world_data.gd").new(Vector3i(12,12,12))
	world.fill_box(Vector3i.ZERO,Vector3i(12,1,12),1,100)
	world.set_voxel(Vector3i(6,1,5),1,100)
	var player = load("res://scripts/core/rules/player_state.gd").new()
	var rules = load("res://assets/config/game_rules.tres")
	player.position = Vector3(5,1,5.5)
	Motion.move(world,player,Vector3.ZERO,Vector2(0,1),PI/2,false,0.3,rules)
	check(player.position.x < 5.71 and player.position.y < 1.1, "Low step blocks walking without upward teleport")
	player.position = Vector3(0.4,1,5.5)
	Motion.move(world,player,Vector3.ZERO,Vector2(0,1),-PI/2,false,0.3,rules)
	check(player.position.x >= 0.3, "Pawn remains inside map edge")
	var grenade = load("res://assets/config/weapons/grenade.tres").duplicate()
	grenade.min_projectile_speed = 0.01
	grenade.projectile_speed = 0.01
	var shot: Dictionary = Sim.simulate(world,Vector3(5.9,1.01,5.5),Vector3.RIGHT,0.25,grenade,rules)
	check(shot.reason == "fuse", "Low speed corner grenade reaches fuse")
	for point in shot.path:
		check(point.is_finite() and world.get_material_id(Vector3i(floori(point.x),floori(point.y),floori(point.z))) == 0,"Low speed grenade remains outside floor and corner")
