class_name MatchFactory
extends RefCounted

static func materials() -> Dictionary:
	var result := {}
	for row in [[0,"air",0,1.0,false,false], [1,"dirt",100,1.0,true,true], [2,"stone",180,2.0,true,true], [3,"metal",255,4.0,true,false]]:
		var material = load("res://scripts/core/voxels/voxel_material_config.gd").new()
		material.id = row[0]
		material.code = row[1]
		material.max_health = row[2]
		material.blast_resistance = row[3]
		material.is_solid = row[4]
		material.is_destructible = row[5]
		result[material.id] = material
	return result

static func create_match(player_limit: int = 10) -> RefCounted:
	var definition = load("res://scripts/core/maps/map_loader.gd").load_from_file("res://maps/twin_forts.toml")
	var world = load("res://scripts/core/voxels/voxel_world_data.gd").new(definition.size)
	var configs := materials()
	load("res://scripts/core/maps/map_builder.gd").apply_to_world(world, configs, definition)
	var rules = load("res://assets/config/game_rules.tres").duplicate()
	var players := []
	var counts := {1: 0, 2: 0}
	for spawn in definition.spawns.slice(0, player_limit):
		var player = load("res://scripts/core/rules/player_state.gd").new()
		var team: int = spawn.team
		counts[team] += 1
		player.player_id = "%s_%d" % ["blue" if team == 1 else "red", counts[team]]
		player.display_name = "%s %d" % ["Blue" if team == 1 else "Red", counts[team]]
		player.team_id = team
		player.position = Vector3(spawn.position[0] + 0.5, spawn.position[1], spawn.position[2] + 0.5)
		player.rotation = Basis(Vector3.UP, deg_to_rad(float(spawn.get("yaw", 0))))
		player.health = rules.starting_health
		players.append(player)
	return load("res://scripts/core/rules/match_runner.gd").new(world, configs, players, rules, load("res://scripts/core/weapons/weapon_catalog.gd").load_all())
