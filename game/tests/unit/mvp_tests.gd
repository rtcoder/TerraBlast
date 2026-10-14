extends SceneTree
var failures := 0
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	var rules_path := "res://assets/config/game_rules.tres"
	check(ResourceLoader.exists(rules_path), "Rules resource must exist")
	if ResourceLoader.exists(rules_path):
		var rules = load(rules_path).duplicate()
		check(rules.validate(), "Default rules valid")
		rules.projectile_step = 0.0
		check(not rules.validate(), "Zero simulation step invalid")
	for code in ["bazooka", "grenade", "drill_missile"]:
		var path := "res://assets/config/weapons/%s.tres" % code
		check(ResourceLoader.exists(path), "Weapon exists: " + code)
		if ResourceLoader.exists(path):
			var weapon = load(path).duplicate()
			check(weapon.validate(), "Valid weapon: " + code)
			weapon.projectile_speed = -1.0
			check(not weapon.validate(), "Reject negative weapon speed")
	_test_projectiles()
	_test_match()
	print("MVP tests: %d failures" % failures)
	quit(1 if failures else 0)

func _test_projectiles() -> void:
	var path := "res://scripts/core/projectiles/projectile_simulation.gd"
	check(ResourceLoader.exists(path), "Pure projectile simulator exists")
	if not ResourceLoader.exists(path):
		return
	var sim = load(path)
	var world = load("res://scripts/core/voxels/voxel_world_data.gd").new(Vector3i(32, 32, 32))
	var rules = load("res://assets/config/game_rules.tres")
	var weapon = load("res://assets/config/weapons/bazooka.tres").duplicate()
	weapon.gravity_scale = 0.0
	world.fill_box(Vector3i(10, 0, 0), Vector3i(11, 32, 32), 1, 100)
	var hit: Dictionary = sim.simulate(world, Vector3(2, 15, 15), Vector3.RIGHT, 4.0, weapon, rules)
	check(hit.hit and hit.position.x >= 10.0 and hit.position.x < 11.0, "Fast projectile hits thin wall")
	var miss: Dictionary = sim.simulate(world, Vector3(2, 15, 15), Vector3.LEFT, 4.0, weapon, rules)
	check(not miss.hit and miss.reason == "miss", "Projectile leaves arena without explosion")
	weapon.gravity_scale = 1.0
	var arc: Dictionary = sim.simulate(world, Vector3(2, 15, 15), Vector3.UP, 0.25, weapon, rules)
	check(is_equal_approx(arc.path[1].y, 15.0 + (10.0 - 18.0 / 30.0) / 30.0), "Fixed 30Hz gravity")
	world.fill_box(Vector3i(0, 0, 0), Vector3i(32, 1, 32), 3, 255)
	var grenade = load("res://assets/config/weapons/grenade.tres")
	var bounce: Dictionary = sim.simulate(world, Vector3(8, 5, 15), Vector3.RIGHT, 0.25, grenade, rules)
	check(bounce.reason == "fuse", "Grenade explodes on fuse after bouncing")
	var drill = load("res://assets/config/weapons/drill_missile.tres").duplicate()
	drill.gravity_scale = 0.0
	var drilled: Dictionary = sim.simulate(world, Vector3(2, 15, 15), Vector3.RIGHT, 4.0, drill, rules)
	check(drilled.deltas.size() == 1, "Drill removes wall voxel")
	check(world.get_material_id(Vector3i(10, 15, 15)) == 1, "Prediction never mutates world")
	world.fill_box(Vector3i(10, 0, 0), Vector3i(11, 32, 32), 3, 255)
	var metal: Dictionary = sim.simulate(world, Vector3(2, 15, 15), Vector3.RIGHT, 4.0, drill, rules)
	check(metal.hit and metal.deltas.is_empty(), "Metal stops drill")

func _test_match() -> void:
	var factory_path := "res://scripts/core/rules/match_factory.gd"
	check(ResourceLoader.exists(factory_path), "Match factory exists")
	if not ResourceLoader.exists(factory_path):
		return
	var runner = load(factory_path).create_match()
	var command = load("res://scripts/core/turns/player_action_command.gd").new()
	command.player_id = "wrong"
	command.weapon_id = 1
	command.aim_direction = Vector3.UP
	command.shot_power = 1.0
	check(not runner.submit(command).ok, "Reject wrong player")
	command.player_id = runner.state.get_active_player().player_id
	command.shot_power = NAN
	check(not runner.submit(command).ok, "Reject nonfinite power")
	command.shot_power = 4.0
	command.weapon_id = 2
	var player_id: String = command.player_id
	var result: Dictionary = runner.submit(command)
	check(result.ok and result.events.size() > 0, "Valid shot emits events")
	check(runner.state.inventory[player_id][2] == 4, "Inventory spent once")
	check(not runner.submit(command).ok, "Duplicate command rejected")
	runner.reset()
	check(runner.state.turn_id == 0 and runner.state.inventory[player_id][2] == 5, "Reset restores turn/ammo")
	runner.state.players[1].apply_damage(100)
	runner.tick(46.0)
	check(runner.state.turn_id == 1 and runner.state.get_active_player().player_id == runner.state.players[2].player_id, "Timeout skips dead player")
	for player in runner.state.players:
		if player.team_id == 2:
			player.apply_damage(100)
	runner.tick(0.01)
	check(runner.state.status == "ended" and runner.state.winner_team == 1, "Last living team wins")
	runner.reset()
	for player in runner.state.players:
		player.apply_damage(100)
	runner.tick(0.01)
	check(runner.state.status == "ended" and runner.state.winner_team == 0, "No survivors is draw")
