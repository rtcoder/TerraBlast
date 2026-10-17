class_name MatchProtocol
extends RefCounted

const VERSION := 2
const MAX_PACKET_BYTES := 4 * 1024 * 1024
const Command := preload("res://scripts/core/turns/player_action_command.gd")
const State := preload("res://scripts/core/rules/match_state.gd")
const Player := preload("res://scripts/core/rules/player_state.gd")

static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func integer(value: Variant, minimum: int, maximum: int) -> bool:
	return number(value) and float(value) == floor(float(value)) and value >= minimum and value <= maximum

static func vector(value: Variant) -> bool:
	return value is Array and value.size() == 3 and number(value[0]) and number(value[1]) and number(value[2]) and absf(value[0]) <= 1e6 and absf(value[1]) <= 1e6 and absf(value[2]) <= 1e6

static func encode_command(command: RefCounted) -> Dictionary:
	return {"version": VERSION, "player_id": command.player_id, "turn_id": command.turn_id, "generation": command.generation, "weapon_id": command.weapon_id, "aim_direction": [command.aim_direction.x, command.aim_direction.y, command.aim_direction.z], "shot_power": command.shot_power}

static func decode_command(data: Variant) -> RefCounted:
	if not data is Dictionary or data.get("version") != VERSION or not data.get("player_id") is String or data.player_id.length() > 64:
		return null
	if not integer(data.get("turn_id"), 0, 2147483647) or not integer(data.get("generation"), 0, 2147483647) or not integer(data.get("weapon_id"), 1, 3) or not vector(data.get("aim_direction")) or not number(data.get("shot_power")):
		return null
	var command := Command.new()
	command.player_id = data.player_id
	command.turn_id = int(data.turn_id)
	command.generation = int(data.generation)
	command.weapon_id = int(data.weapon_id)
	command.aim_direction = Vector3(data.aim_direction[0], data.aim_direction[1], data.aim_direction[2])
	if command.aim_direction.length_squared() < 0.001 or command.aim_direction.length_squared() > 1e6:
		return null
	command.shot_power = data.shot_power
	return command

static func valid_delta(world: RefCounted, data: Variant) -> bool:
	if not data is Dictionary or not vector(data.get("position")) or not integer(data.get("material_id"), 0, 3) or not integer(data.get("health"), 0, 255):
		return false
	for axis in data.position:
		if not integer(axis, 0, 1023):
			return false
	return world.is_in_bounds(Vector3i(data.position[0], data.position[1], data.position[2])) and ((data.material_id == 0 and data.health == 0) or (data.material_id > 0 and data.health > 0))

static func apply_deltas(world: RefCounted, deltas: Variant) -> bool:
	if not deltas is Array or deltas.size() > 100000:
		return false
	for delta in deltas:
		if not valid_delta(world, delta):
			return false
	for delta in deltas:
		world.set_voxel(Vector3i(delta.position[0], delta.position[1], delta.position[2]), int(delta.material_id), int(delta.health))
	return true

static func chunk_snapshot(world: RefCounted, chunk: Vector3i) -> Dictionary:
	var cells := []
	var start: Vector3i = chunk * world.chunk_size
	for z in range(start.z, mini(start.z + world.chunk_size, world.size.z)):
		for y in range(start.y, mini(start.y + world.chunk_size, world.size.y)):
			for x in range(start.x, mini(start.x + world.chunk_size, world.size.x)):
				var p := Vector3i(x, y, z)
				cells.append([world.get_material_id(p), world.get_health(p)])
	return {"version": VERSION, "chunk": [chunk.x, chunk.y, chunk.z], "cells": cells}

static func apply_chunk(world: RefCounted, data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != VERSION or not vector(data.get("chunk")) or not data.get("cells") is Array:
		return false
	for axis in data.chunk:
		if not integer(axis, 0, 1023):
			return false
	var start := Vector3i(data.chunk[0], data.chunk[1], data.chunk[2]) * int(world.chunk_size)
	if not world.is_in_bounds(start):
		return false
	var extent: Vector3i = (world.size - start).min(Vector3i.ONE * world.chunk_size)
	if data.cells.size() != extent.x * extent.y * extent.z:
		return false
	var deltas := []
	var index := 0
	for z in range(start.z, start.z + extent.z):
		for y in range(start.y, start.y + extent.y):
			for x in range(start.x, start.x + extent.x):
				var cell = data.cells[index]
				if not cell is Array or cell.size() != 2:
					return false
				deltas.append({"position": [x, y, z], "material_id": cell[0], "health": cell[1]})
				index += 1
	return apply_deltas(world, deltas)

static func encode_result(result: Dictionary) -> Dictionary:
	var copy := result.duplicate(true)
	var points := []
	for point in result.get("path", []):
		points.append([point.x, point.y, point.z])
	copy.path = points
	copy.version = VERSION
	return copy

static func decode_path(data: Variant) -> PackedVector3Array:
	var result := PackedVector3Array()
	if not data is Array or data.size() > 10000:
		return result
	for point in data:
		if not vector(point):
			return PackedVector3Array()
		result.append(Vector3(point[0], point[1], point[2]))
	return result

static func decode_state(data: Variant) -> RefCounted:
	if not data is Dictionary or not data.get("players") is Array or data.players.is_empty() or data.players.size() > 10:
		return null
	if not integer(data.get("turn_id"), 0, 2147483647) or not integer(data.get("active_index"), -1, data.players.size() - 1) or not data.get("status") in ["playing", "ended"] or not number(data.get("time_remaining")) or not data.get("inventory") is Dictionary:
		return null
	for field in ["revision", "generation", "winner_team"]:
		if not integer(data.get(field), 0, 2147483647):
			return null
	if not data.get("winner_player") is String or data.winner_player.length() > 64 or data.time_remaining < 0 or data.time_remaining > 3600 or data.inventory.size() != data.players.size():
		return null
	if not valid_summary(data):
		return null
	var players := []
	var inventory := {}
	for entry in data.players:
		if not entry is Dictionary or not entry.get("id") is String or entry.id.is_empty() or entry.id.length() > 64 or inventory.has(entry.id) or not entry.get("name") is String or not vector(entry.get("position")) or not integer(entry.get("health"), 0, 10000) or not integer(entry.get("team"), 0, 10) or not entry.get("alive") is bool or entry.alive != (entry.health > 0):
			return null
		var ammo = data.inventory.get(entry.id)
		if not ammo is Dictionary:
			return null
		inventory[entry.id] = {}
		for id in [1, 2, 3]:
			var count = ammo.get(id, ammo.get(str(id)))
			if not integer(count, -1, 10000):
				return null
			inventory[entry.id][id] = int(count)
		var player := Player.new()
		player.player_id = entry.id
		player.display_name = entry.name
		player.team_id = int(entry.team)
		player.health = int(entry.health)
		player.is_alive = entry.alive
		player.position = Vector3(entry.position[0], entry.position[1], entry.position[2])
		if entry.has("rotation"):
			if not entry.rotation is Array or entry.rotation.size() != 9:
				return null
			for component in entry.rotation:
				if not number(component) or absf(component) > 1.001:
					return null
			var basis := Basis(Vector3(entry.rotation[0], entry.rotation[1], entry.rotation[2]), Vector3(entry.rotation[3], entry.rotation[4], entry.rotation[5]), Vector3(entry.rotation[6], entry.rotation[7], entry.rotation[8]))
			if not is_equal_approx(basis.determinant(), 1.0) or not basis.is_equal_approx(basis.orthonormalized()):
				return null
			player.rotation = basis
		players.append(player)
	var state := State.new(players)
	state.inventory = inventory
	state.turn_id = int(data.turn_id)
	state.active_player_index = int(data.active_index)
	state.status = data.status
	state.time_remaining = float(data.time_remaining)
	state.revision = int(data.revision)
	state.generation = int(data.generation)
	state.winner_team = int(data.winner_team)
	state.winner_player = data.winner_player
	if data.has("max_shot_power"):
		if not number(data.max_shot_power) or data.max_shot_power <= 0 or data.max_shot_power > 100:
			return null
		state.max_shot_power = float(data.max_shot_power)
	if state.status == "playing":
		if state.get_active_player() == null or not state.get_active_player().is_alive or state.winner_team != 0 or not state.winner_player.is_empty():
			return null
	else:
		if state.winner_team == 0 and state.winner_player.is_empty():
			return state
		if not state.has_winner():
			return null
		var living: Array = state.get_living_players()
		var expected_team: int = living[0].team_id if not living.is_empty() else 0
		var expected_player: String = living[0].player_id if living.size() == 1 else ""
		if state.winner_team != expected_team or state.winner_player != expected_player:
			return null
	return state

static func packet(data: Dictionary) -> PackedByteArray:
	return JSON.stringify(data, "", true, true).to_utf8_buffer()

static func unpack(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() > MAX_PACKET_BYTES:
		return {}
	var data = JSON.parse_string(bytes.get_string_from_utf8())
	return data if data is Dictionary and data.get("version") == VERSION else {}

static func valid_events(events: Variant) -> bool:
	if not events is Array or events.size() > 64:
		return false
	for event in events:
		if not event is Dictionary:
			return false
		match event.get("type", ""):
			"ShotResolved":
				if not event.get("hit") is bool or not vector(event.get("position")) or not integer(event.get("weapon_id"), 1, 3) or not integer(event.get("turn_id"), 0, 2147483647) or not integer(event.get("seed"), 0, 2147483647) or not integer(event.get("radius"), 0, 64):
					return false
			"TurnStarted":
				if not event.get("player_id") is String or not integer(event.get("turn_id"), 0, 2147483647):
					return false
			"PlayerDamaged":
				if not event.get("player_id") is String or not integer(event.get("amount"), 0, 10000):
					return false
			"MatchEnded":
				if not event.get("player_id") is String or not integer(event.get("team_id"), 0, 10):
					return false
			_:
				return false
	return true

static func terrain_checksum(world: RefCounted) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(world.material_ids.to_byte_array())
	context.update(world.health_values.to_byte_array())
	return context.finish().hex_encode()

static func valid_snapshot_metadata(data: Dictionary) -> bool:
	if not data.get("configuration") is Dictionary or not integer(data.get("transfer_id"), 1, 2147483647):
		return false
	if not data.get("player_id") is String or data.player_id.is_empty() or data.player_id.length() > 64 or not vector(data.get("size")) or not integer(data.get("chunk_size"), 1, 32):
		return false
	var count := 1
	var volume := 1
	for axis in data.size:
		if not integer(axis, 1, 256):
			return false
		volume *= int(axis)
		count *= ceili(float(axis) / float(data.chunk_size))
	return volume <= 2097152 and count <= 8192 and data.get("chunk_count") == count and integer(data.get("terrain_revision"), 0, 2147483647) and integer(data.get("generation"), 0, 2147483647) and integer(data.get("revision"), 0, 2147483647) and data.get("resume_token", "") is String

static func valid_result(result: Variant) -> bool:
	return result is Dictionary and result.get("version") == VERSION and result.get("ok") == true and result.get("reason") is String and valid_events(result.get("events")) and decode_state(result.get("state")) != null and not decode_path(result.get("path")).is_empty() and result.get("deltas") is Array

# Only exported primitive fields cross the wire; resources/scripts never do.
static func encode_config(resource: Resource) -> Dictionary:
	var output := {}
	for property in resource.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.usage & PROPERTY_USAGE_EDITOR:
			output[property.name] = resource.get(property.name)
	return output

static func decode_config(data: Variant, resource: Resource) -> Resource:
	if not data is Dictionary:
		return null
	var defaults := encode_config(resource)
	if data.size() != defaults.size():
		return null
	for key in defaults:
		if not data.has(key):
			return null
		var value = data[key]
		match typeof(defaults[key]):
			TYPE_INT:
				if not integer(value, -100000, 100000):
					return null
			TYPE_FLOAT:
				if not number(value):
					return null
			TYPE_STRING:
				if not value is String or value.length() > 128:
					return null
			_:
				return null
		resource.set(key, value)
	return resource if resource.validate() else null

static func encode_configuration(runner: RefCounted) -> Dictionary:
	var weapons := {}
	for id in runner.weapons:
		weapons[str(id)] = encode_config(runner.weapons[id])
	return {"rules": encode_config(runner.rules), "weapons": weapons}

static func decode_configuration(data: Variant) -> Dictionary:
	if not data is Dictionary or not data.get("weapons") is Dictionary or data.weapons.size() != 3:
		return {}
	var rules = decode_config(data.get("rules"), load("res://scripts/core/rules/game_rules_config.gd").new())
	if rules == null:
		return {}
	var weapons := {}
	for id in [1, 2, 3]:
		var weapon = decode_config(data.weapons.get(str(id)), load("res://scripts/core/weapons/weapon_config.gd").new())
		if weapon == null or weapon.id != id:
			return {}
		weapons[id] = weapon
	return {"rules": rules, "weapons": weapons}

static func valid_arena_players(state: RefCounted, size: Vector3i) -> bool:
	for player in state.players:
		var p: Vector3 = player.position
		if player.is_alive and (p.x < -1 or p.z < -1 or p.y < -4 or p.x > size.x + 1 or p.z > size.z + 1 or p.y > size.y + 16):
			return false
	return true

static func valid_summary(data: Dictionary) -> bool:
	var stats = data.get("statistics")
	var history = data.get("history")
	if not stats is Dictionary or not history is Array or stats.size() != data.players.size() or history.size() > 32:
		return false
	for player in data.players:
		if not player is Dictionary or not player.get("id") is String:
			return false
		var row = stats.get(player.id)
		if not row is Dictionary or row.size() != 4:
			return false
		for key in ["shots", "hits", "damage", "kills"]:
			if not integer(row.get(key), 0, 2147483647):
				return false
	for row in history:
		if not row is Dictionary or not stats.has(row.get("player_id")) or not integer(row.get("weapon_id"), 1, 3):
			return false
		for key in ["turn_id", "damage", "kills", "terrain_changes", "terrain_destroyed"]:
			if not integer(row.get(key), 0, 2147483647):
				return false
	return true

static func valid_configured_state(state: RefCounted, runner: RefCounted) -> bool:
	if not valid_arena_players(state, runner.world.size):
		return false
	if state.status == "ended" and state.winner_team == 0 and state.winner_player.is_empty() and not state.get_living_players().is_empty():
		return runner.rules.max_turns > 0 and state.turn_id >= runner.rules.max_turns
	return true

static func valid_display_name(value: Variant) -> bool:
	if not value is String or value.to_utf8_buffer().size() > 96:
		return false
	var trimmed: String = value.strip_edges()
	if trimmed.is_empty() or trimmed.length() > 24:
		return false
	for index in range(value.length()):
		var code: int = value.unicode_at(index)
		if code < 32 or (code >= 127 and code <= 159):
			return false
	return true

static func valid_lobby(data: Variant) -> bool:
	if not data is Dictionary or not integer(data.get("capacity"), 2, 10) or not data.get("require_ready") is bool or not data.get("started") is bool or not integer(data.get("generation"), 0, 2147483647):
		return false
	if not data.get("roster") is Array or data.roster.size() != data.capacity:
		return false
	var ids := {}
	for row in data.roster:
		if not row is Dictionary or not row.get("id") is String or row.id.is_empty() or row.id.length() > 64 or ids.has(row.id) or not valid_display_name(row.get("name")) or not integer(row.get("team"), 1, 2):
			return false
		for key in ["connected", "ready", "rematch"]:
			if not row.get(key) is bool:
				return false
		if not row.connected and (row.ready or row.rematch):
			return false
		ids[row.id] = true
	return true
