class_name MatchReplay
extends RefCounted

const Runner = preload("res://scripts/core/rules/match_runner.gd")
const World = preload("res://scripts/core/voxels/voxel_world_data.gd")
const Player = preload("res://scripts/core/rules/player_state.gd")
const Command = preload("res://scripts/core/turns/player_action_command.gd")
const Rules = preload("res://scripts/core/rules/game_rules_config.gd")
const Weapon = preload("res://scripts/core/weapons/weapon_config.gd")
const VoxelMaterial = preload("res://scripts/core/voxels/voxel_material_config.gd")
const Motion = preload("res://scripts/core/rules/player_motion.gd")
const MAX_ACTIONS := 100000
const MAX_SHOTS := 256
var _shot_count := 0
var recording_error := ""
var data: Dictionary = {}:
	set(value):
		data = value
		_shot_count = 0
		if value.get("actions") is Array:
			for action in value.actions:
				if action is Dictionary and action.get("type") == "shot":
					_shot_count += 1

static func properties(resource: Resource) -> Dictionary:
	var result := {}
	for property in resource.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			result[property.name] = resource.get(property.name)
	return result

static func configure(resource: Resource, values: Dictionary) -> Resource:
	for key in values:
		resource.set(key, values[key])
	return resource

func capture(runner: RefCounted) -> void:
	recording_error = ""
	var materials := []
	var weapons := []
	for material in runner.materials.values():
		materials.append(properties(material))
	for weapon in runner.weapons.values():
		weapons.append(properties(weapon))
	data = {"version": 1, "size": [runner.world.size.x,runner.world.size.y,runner.world.size.z], "materials": materials, "weapons": weapons, "rules": properties(runner.rules), "terrain": Array(runner.world.material_ids), "health": Array(runner.world.health_values), "state": runner.state_snapshot(), "actions": []}

func submit(runner: RefCounted, command: RefCounted) -> Dictionary:
	var action := {"type": "shot", "player_id": command.player_id, "turn_id": command.turn_id, "generation": command.generation, "weapon_id": command.weapon_id, "power": command.shot_power, "direction": [command.aim_direction.x,command.aim_direction.y,command.aim_direction.z]}
	var result: Dictionary = runner.submit(command)
	if result.ok:
		record_action(action)
	return result

func tick(runner: RefCounted, delta: float) -> Array:
	record_action({"type": "tick", "delta": delta})
	return runner.tick(delta)

func move(runner: RefCounted, velocity: Vector3, input: Vector2, yaw: float, jump: bool, delta: float) -> Vector3:
	record_action({"type": "move", "velocity": [velocity.x,velocity.y,velocity.z], "input": [input.x,input.y], "yaw": yaw, "jump": jump, "delta": delta})
	return Motion.move(runner.world, runner.state.get_active_player(), velocity, input, yaw, jump, delta, runner.rules, runner.materials)

func record_action(action: Dictionary) -> void:
	if not recording_error.is_empty():
		return
	if not data.has("actions"):
		recording_error = "capture_required"
	elif data.actions.size() >= MAX_ACTIONS:
		recording_error = "action_limit"
	elif action.type == "shot" and _shot_count >= MAX_SHOTS:
		recording_error = "shot_limit"
	else:
		data.actions.append(action)
		if action.type == "shot":
			_shot_count += 1

func surrender(runner: RefCounted, player_id: String) -> Dictionary:
	var result: Dictionary = runner.surrender(player_id)
	if result.ok:
		record_action({"type": "surrender", "player_id": player_id})
	return result

func reset(runner: RefCounted) -> void:
	runner.reset()
	capture(runner)

static func vector(values: Array) -> Vector3:
	return Vector3(values[0],values[1],values[2])

func initial_runner() -> RefCounted:
	if not valid_data():
		return null
	var world = World.new(Vector3i(data.size[0],data.size[1],data.size[2]))
	world.material_ids = PackedInt32Array(data.terrain)
	world.health_values = PackedInt32Array(data.health)
	var materials := {}
	var weapons := {}
	for row in data.materials:
		var material = configure(VoxelMaterial.new(),row)
		materials[material.id] = material
	for row in data.weapons:
		var weapon = configure(Weapon.new(),row)
		weapons[weapon.id] = weapon
	var players := []
	for row in data.state.players:
		var player = Player.new()
		player.player_id = row.id
		player.display_name = row.name
		player.team_id = int(row.team)
		player.position = vector(row.position)
		player.rotation = Basis(vector(row.rotation.slice(0,3)),vector(row.rotation.slice(3,6)),vector(row.rotation.slice(6,9)))
		players.append(player)
	var runner = Runner.new(world,materials,players,configure(Rules.new(),data.rules),weapons)
	for i in range(players.size()):
		runner.state.players[i].health = int(data.state.players[i].health)
		runner.state.players[i].is_alive = data.state.players[i].alive
	for key in ["turn_id","status","time_remaining","winner_team","winner_player","revision","generation"]:
		runner.state.set(key,data.state[key])
	runner.statistics = data.state.statistics.duplicate(true)
	runner.history = data.state.history.duplicate(true)
	for metrics in runner.statistics.values():
		for key in metrics:
			metrics[key] = int(metrics[key])
	for row in runner.history:
		for key in ["weapon_id", "turn_id", "damage", "kills", "terrain_changes", "terrain_destroyed"]:
			row[key] = int(row[key])
	runner.state.active_player_index = int(data.state.active_index)
	for player_id in data.state.inventory:
		for weapon_id in data.state.inventory[player_id]:
			runner.state.inventory[player_id][int(weapon_id)] = int(data.state.inventory[player_id][weapon_id])
	return runner

func replay() -> RefCounted:
	var runner = initial_runner()
	if runner == null:
		return null
	for action in data.actions:
		if not execute_action(runner, action).ok:
			return null
	return runner

# Callers validate the complete recording before executing this shared timeline path.
static func execute_action(runner: RefCounted, action: Dictionary) -> Dictionary:
	match action.get("type"):
		"tick":
			return {"ok": true, "events": runner.tick(action.delta)}
		"move":
			if runner.state.status != "playing" or runner.state.get_active_player() == null or not runner.state.get_active_player().is_alive:
				return {"ok": false, "reason": "invalid_move_state"}
			var velocity: Vector3 = Motion.move(runner.world,runner.state.get_active_player(),vector(action.velocity),Vector2(action.input[0],action.input[1]),action.yaw,action.jump,action.delta,runner.rules,runner.materials)
			return {"ok": true, "velocity": velocity}
		"shot":
			var command = Command.new()
			command.player_id = action.player_id
			command.turn_id = int(action.turn_id)
			command.generation = int(action.generation)
			command.weapon_id = int(action.weapon_id)
			command.shot_power = action.power
			command.aim_direction = vector(action.direction)
			var result: Dictionary = runner.submit(command)
			return {"ok": result.ok, "result": result}
		"surrender":
			var result: Dictionary = runner.surrender(action.player_id)
			return {"ok": result.ok, "result": result}
	return {"ok": false, "reason": "unknown_action"}

static func state_hash(runner: RefCounted, full_precision := true) -> String:
	return JSON.stringify({"state": runner.state_snapshot(), "terrain": Array(runner.world.material_ids), "health": Array(runner.world.health_values)}, "", true, full_precision).sha256_text()

static func number(value: Variant, low: float, high: float, integral := false) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= low and value <= high and (not integral or value == floor(value))

static func numbers(value: Variant, count: int, low: float, high: float, integral := false) -> bool:
	if not value is Array or value.size() != count:
		return false
	for component in value:
		if not number(component,low,high,integral):
			return false
	return true

static func text_value(value: Variant, maximum := 128, allow_empty := false) -> bool:
	return value is String and value.length() <= maximum and (allow_empty or not value.is_empty())

# Only declared script data may be assigned. In particular, never accept a script property.
static func valid_config(value: Variant, prototype: Resource) -> bool:
	if not value is Dictionary:
		return false
	var schema := properties(prototype)
	if value.size() != schema.size():
		return false
	for key in schema:
		if not value.has(key):
			return false
		match typeof(schema[key]):
			TYPE_INT:
				if not number(value[key],-1,10000,true): return false
			TYPE_FLOAT:
				if not number(value[key],-100 if key == "wind" else 0,10000): return false
			TYPE_STRING:
				if not text_value(value[key],256,true): return false
			TYPE_BOOL:
				if not value[key] is bool: return false
			_: return false
	return true

func valid_data() -> bool:
	if data.get("version") != 1 or not numbers(data.get("size"),3,1,256,true):
		return false
	var volume := int(data.size[0]) * int(data.size[1]) * int(data.size[2])
	if volume > 2097152 or not data.get("terrain") is Array or not data.get("health") is Array or data.terrain.size() != volume or data.health.size() != volume:
		return false
	if not valid_config(data.get("rules"),Rules.new()) or not configure(Rules.new(),data.rules).validate():
		return false
	var materials := {}
	var codes := {}
	if not data.get("materials") is Array or data.materials.is_empty() or data.materials.size() > 256:
		return false
	for row in data.materials:
		if not valid_config(row,VoxelMaterial.new()) or not number(row.id,0,255,true) or materials.has(int(row.id)) or codes.has(row.code) or row.code.is_empty() or row.blast_resistance <= 0 or not number(row.max_health,0,10000,true):
			return false
		materials[int(row.id)] = row
		codes[row.code] = true
	if not materials.has(0) or materials[0].is_solid or materials[0].max_health != 0:
		return false
	for i in range(volume):
		if not number(data.terrain[i],0,255,true) or not materials.has(int(data.terrain[i])):
			return false
		var id := int(data.terrain[i])
		if not number(data.health[i],0,materials[id].max_health,true) or (id == 0) != (data.health[i] == 0):
			return false
	var weapons := {}
	codes.clear()
	if not data.get("weapons") is Array or data.weapons.is_empty() or data.weapons.size() > 32:
		return false
	for row in data.weapons:
		if not valid_config(row,Weapon.new()) or not configure(Weapon.new(),row).validate() or weapons.has(int(row.id)) or codes.has(row.code):
			return false
		weapons[int(row.id)] = row
		codes[row.code] = true
	var state = data.get("state")
	if not state is Dictionary or not state.get("players") is Array or state.players.is_empty() or state.players.size() > 10 or not state.get("inventory") is Dictionary or state.inventory.size() != state.players.size():
		return false
	for key in ["turn_id","revision","generation"]:
		if not number(state.get(key),0,2147483647,true): return false
	if not number(state.get("active_index"),-1,state.players.size()-1,true) or not state.get("status") in ["playing","ended"] or not number(state.get("time_remaining"),0,data.rules.turn_time) or not number(state.get("winner_team"),0,10,true) or not text_value(state.get("winner_player"),64,true) or state.get("max_shot_power") != data.rules.max_shot_power:
		return false
	var players := {}
	var living := []
	var living_teams := {}
	for row in state.players:
		if not row is Dictionary or not text_value(row.get("id"),64) or players.has(row.id) or not text_value(row.get("name"),128,true) or not number(row.get("team"),0,10,true) or not number(row.get("health"),0,data.rules.starting_health,true) or not row.get("alive") is bool or row.alive != (row.health > 0) or not numbers(row.get("position"),3,-1024,1024) or not numbers(row.get("rotation"),9,-1.001,1.001):
			return false
		var basis := Basis(vector(row.rotation.slice(0,3)),vector(row.rotation.slice(3,6)),vector(row.rotation.slice(6,9)))
		if not is_equal_approx(basis.determinant(),1.0) or not basis.is_equal_approx(basis.orthonormalized()):
			return false
		var ammo = state.inventory.get(row.id)
		if not ammo is Dictionary or ammo.size() != weapons.size(): return false
		var seen := {}
		for key in ammo:
			if not (key is int or (key is String and key.is_valid_int())): return false
			var id := int(key)
			if not weapons.has(id) or seen.has(id) or not number(ammo[key],-1,1000,true): return false
			var maximum: int = weapons[id].max_uses_per_match
			if (maximum == -1 and ammo[key] != -1) or (maximum >= 0 and (ammo[key] < 0 or ammo[key] > maximum)): return false
			seen[id] = true
		players[row.id] = true
		if row.alive:
			living.append(row)
			living_teams[int(row.team)] = true
	if state.status == "playing":
		if state.active_index < 0 or not state.players[int(state.active_index)].alive or state.winner_team != 0 or state.winner_player != "": return false
	elif not (data.rules.max_turns > 0 and state.turn_id >= data.rules.max_turns and state.winner_team == 0 and state.winner_player == ""):
		var team_match: bool = state.players.any(func(row): return row.team != 0)
		if (team_match and living_teams.size() > 1) or (not team_match and living.size() > 1): return false
		if state.winner_team != (living[0].team if not living.is_empty() else 0) or state.winner_player != (living[0].id if living.size() == 1 else ""): return false
	if not state.get("statistics") is Dictionary or state.statistics.size() != players.size() or not state.get("history") is Array or state.history.size() > 32:
		return false
	for id in players:
		var metrics = state.statistics.get(id)
		if not metrics is Dictionary or metrics.size() != 4: return false
		for key in ["shots", "hits", "damage", "kills"]:
			if not number(metrics.get(key),0,2147483647,true): return false
		if metrics.hits > metrics.shots: return false
	for row in state.history:
		if not row is Dictionary or row.size() != 7 or not text_value(row.get("player_id"),64) or not players.has(row.player_id) or not number(row.get("weapon_id"),1,10000,true) or not weapons.has(int(row.weapon_id)): return false
		for key in ["turn_id", "damage", "kills", "terrain_changes", "terrain_destroyed"]:
			if not number(row.get(key),0,2147483647,true): return false
	if not data.get("actions") is Array or data.actions.size() > MAX_ACTIONS: return false
	var shots := 0
	for action in data.actions:
		if not action is Dictionary: return false
		match action.get("type"):
			"tick":
				if action.size() != 2 or not number(action.get("delta"),0,600): return false
			"move":
				if action.size() != 6 or not numbers(action.get("velocity"),3,-100,100) or not numbers(action.get("input"),2,-1,1) or not number(action.get("yaw"),-100000,100000) or not action.get("jump") is bool or not number(action.get("delta"),0,0.3): return false
			"surrender":
				if action.size() != 2 or not text_value(action.get("player_id"),64) or not players.has(action.player_id): return false
			"shot":
				shots += 1
				if shots > MAX_SHOTS or action.size() != 7 or not text_value(action.get("player_id"),64) or not players.has(action.player_id) or not number(action.get("turn_id"),0,2147483647,true) or not number(action.get("generation"),0,2147483647,true) or not number(action.get("weapon_id"),1,10000,true) or not weapons.has(int(action.weapon_id)) or not number(action.get("power"),0,100) or not numbers(action.get("direction"),3,-100,100) or vector(action.direction).length_squared() < 0.001: return false
			_: return false
	return true
