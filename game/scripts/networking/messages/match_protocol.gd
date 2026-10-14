class_name MatchProtocol
extends RefCounted

const VERSION := 1
const MAX_PACKET_BYTES := 4 * 1024 * 1024
const Command := preload("res://scripts/core/turns/player_action_command.gd")
const State := preload("res://scripts/core/rules/match_state.gd")
const Player := preload("res://scripts/core/rules/player_state.gd")

static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func integer(value: Variant, minimum: int, maximum: int) -> bool:
	return number(value) and float(value) == floor(float(value)) and value >= minimum and value <= maximum

static func vector(value: Variant) -> bool:
	return value is Array and value.size() == 3 and number(value[0]) and number(value[1]) and number(value[2])

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
	if not data.get("winner_player") is String:
		return null
	var players := []
	var inventory := {}
	for entry in data.players:
		if not entry is Dictionary or not entry.get("id") is String or inventory.has(entry.id) or not entry.get("name") is String or not vector(entry.get("position")) or not integer(entry.get("health"), 0, 10000) or not integer(entry.get("team"), 0, 10) or not entry.get("alive") is bool or entry.alive != (entry.health > 0):
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
	return state

static func packet(data: Dictionary) -> PackedByteArray:
	return JSON.stringify(data).to_utf8_buffer()

static func unpack(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() > MAX_PACKET_BYTES:
		return {}
	var data = JSON.parse_string(bytes.get_string_from_utf8())
	return data if data is Dictionary and data.get("version") == VERSION else {}
