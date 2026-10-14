class_name MatchRunner
extends RefCounted

const Simulation := preload("res://scripts/core/projectiles/projectile_simulation.gd")
const Destruction := preload("res://scripts/core/terrain/voxel_destruction.gd")
const State := preload("res://scripts/core/rules/match_state.gd")
const Player := preload("res://scripts/core/rules/player_state.gd")

var world: RefCounted
var materials: Dictionary
var rules: Resource
var weapons: Dictionary
var state: RefCounted
var initial_materials: PackedInt32Array
var initial_health: PackedInt32Array
var initial_players: Array = []

func _init(initial_world: RefCounted, configs: Dictionary, players: Array, config: Resource, catalog: Dictionary) -> void:
	world = initial_world
	materials = configs
	rules = config
	weapons = catalog
	initial_materials = world.material_ids.duplicate()
	initial_health = world.health_values.duplicate()
	for player in players:
		initial_players.append({"id": player.player_id, "name": player.display_name, "team": player.team_id, "position": player.position, "rotation": player.rotation})
	reset()

func reset() -> void:
	var generation: int = state.generation + 1 if state != null else 0
	world.material_ids = initial_materials.duplicate()
	world.health_values = initial_health.duplicate()
	var players := []
	for data in initial_players:
		var player := Player.new()
		player.player_id = data.id
		player.display_name = data.name
		player.team_id = data.team
		player.position = data.position
		player.rotation = data.rotation
		player.health = rules.starting_health
		players.append(player)
	state = State.new(players)
	state.generation = generation
	state.max_shot_power = rules.max_shot_power
	state.time_remaining = rules.turn_time
	for player in players:
		state.inventory[player.player_id] = {}
		for id in weapons:
			state.inventory[player.player_id][id] = weapons[id].max_uses_per_match

func submit(command: RefCounted) -> Dictionary:
	if command.generation != state.generation:
		return {"ok": false, "reason": "stale_generation"}
	if state.status != "playing":
		return {"ok": false, "reason": "match_ended"}
	if not is_finite(command.shot_power) or not command.aim_direction.is_finite() or command.aim_direction.length_squared() < 0.001:
		return {"ok": false, "reason": "invalid_aim_or_power"}
	if not weapons.has(command.weapon_id):
		return {"ok": false, "reason": "unknown_weapon"}
	var valid: Dictionary = state.validate_action(command)
	if not valid.ok:
		return valid
	if state.time_remaining <= 0:
		return {"ok": false, "reason": "expired_turn"}
	var active = state.get_active_player()
	var ammo: int = state.inventory[active.player_id][command.weapon_id]
	if ammo == 0:
		return {"ok": false, "reason": "no_ammo"}
	if ammo > 0:
		state.inventory[active.player_id][command.weapon_id] -= 1
	command.shot_power = clampf(command.shot_power, rules.min_shot_power, rules.max_shot_power)
	var weapon: Resource = weapons[command.weapon_id]
	var shot := Simulation.simulate(world, active.position + Vector3.UP * 1.3, command.aim_direction, command.shot_power, weapon, rules, materials)
	var deltas: Array = shot.deltas.duplicate(true)
	for delta in deltas:
		world.set_voxel(Vector3i(delta.position[0], delta.position[1], delta.position[2]), delta.material_id, delta.health)
	var events: Array = []
	if shot.hit:
		var center := Vector3i(floori(shot.position.x), floori(shot.position.y), floori(shot.position.z))
		var blast: Array = Destruction.new(world, materials).apply_explosion(center, weapon.explosion_radius, weapon.terrain_damage)
		for delta in blast:
			deltas.append({"position": [delta.position.x, delta.position.y, delta.position.z], "material_id": delta.material_id, "health": delta.health})
		for player in state.players:
			if not player.is_alive:
				continue
			var distance: float = player.position.distance_to(shot.position)
			var amount := int(round(weapon.player_damage * maxf(0.0, 1.0 - distance / maxf(0.01, weapon.explosion_radius + 0.5))))
			if amount > 0:
				player.apply_damage(amount)
				events.append({"type": "PlayerDamaged", "player_id": player.player_id, "amount": amount})
		settle_players(events)
	events.append({"type": "ShotResolved", "hit": shot.hit, "position": [shot.position.x, shot.position.y, shot.position.z], "weapon_id": weapon.id, "turn_id": state.turn_id, "seed": 0, "radius": weapon.explosion_radius})
	advance(events)
	state.revision += 1
	return {"ok": true, "reason": shot.reason, "events": events, "deltas": deltas, "path": shot.path, "state": state_snapshot()}

func settle_players(events: Array = []) -> void:
	for player in state.players:
		if not player.is_alive:
			continue
		var found := false
		for y in range(mini(floori(player.position.y), world.size.y - 1), -1, -1):
			var voxel := Vector3i(floori(player.position.x), y, floori(player.position.z))
			if world.get_material_id(voxel) != 0:
				player.position.y = y + 1.0
				found = true
				break
		if not found:
			var amount: int = player.health
			player.apply_damage(amount)
			events.append({"type": "PlayerDamaged", "player_id": player.player_id, "amount": amount})

func check_end(events: Array) -> bool:
	if not state.has_winner():
		return false
	state.status = "ended"
	var living: Array = state.get_living_players()
	state.winner_team = living[0].team_id if not living.is_empty() else 0
	state.winner_player = living[0].player_id if living.size() == 1 else ""
	events.append({"type": "MatchEnded", "team_id": state.winner_team, "player_id": state.winner_player})
	return true

func advance(events: Array) -> void:
	if check_end(events):
		return
	state.complete_turn()
	state.time_remaining = rules.turn_time
	events.append({"type": "TurnStarted", "turn_id": state.turn_id, "player_id": state.get_active_player().player_id})

func tick(delta: float) -> Array:
	var events: Array = []
	if state.status != "playing" or not is_finite(delta) or delta < 0:
		return events
	if check_end(events):
		state.revision += 1
		return events
	state.time_remaining = maxf(0.0, state.time_remaining - delta)
	if state.time_remaining <= 0:
		advance(events)
		state.revision += 1
	return events

func state_snapshot() -> Dictionary:
	var players := []
	for player in state.players:
		players.append({"id": player.player_id, "name": player.display_name, "team": player.team_id, "position": [player.position.x, player.position.y, player.position.z], "health": player.health, "alive": player.is_alive})
	return {"players": players, "turn_id": state.turn_id, "active_index": state.active_player_index, "status": state.status, "time_remaining": state.time_remaining, "winner_team": state.winner_team, "winner_player": state.winner_player, "inventory": state.inventory.duplicate(true), "revision": state.revision, "generation": state.generation}
