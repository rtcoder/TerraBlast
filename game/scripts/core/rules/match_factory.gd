class_name MatchFactory
extends RefCounted

static func materials() -> Dictionary:
	return load("res://scripts/core/maps/arena_generator.gd").materials()

static func create_match(player_limit: int = 10, map_path: String = "res://maps/twin_forts.toml", preset: String = "classic") -> RefCounted:
	var arena: Dictionary = load("res://scripts/core/maps/arena_generator.gd").generate(map_path)
	if not arena.errors.is_empty() or player_limit <= 0:
		return null
	var world = arena.world
	var configs: Dictionary = arena.materials
	var rules = load("res://scripts/core/rules/rule_presets.gd").create(preset)
	if rules == null:
		return null
	var players := []
	var counts := {1: 0, 2: 0}
	for spawn in arena.spawns.slice(0, player_limit):
		var player = load("res://scripts/core/rules/player_state.gd").new()
		var team: int = spawn.team
		counts[team] += 1
		player.player_id = "%s_%d" % ["blue" if team == 1 else "red", counts[team]]
		player.display_name = "%s %d" % ["Blue" if team == 1 else "Red", counts[team]]
		player.team_id = team
		player.position = Vector3(spawn.position.x + 0.5, spawn.position.y, spawn.position.z + 0.5)
		player.rotation = Basis(Vector3.UP, deg_to_rad(float(spawn.yaw)))
		player.health = rules.starting_health
		players.append(player)
	return load("res://scripts/core/rules/match_runner.gd").new(world, configs, players, rules, load("res://scripts/core/weapons/weapon_catalog.gd").load_all())
