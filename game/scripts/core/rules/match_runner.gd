class_name MatchRunner
extends RefCounted

const Simulation := preload("res://scripts/core/projectiles/projectile_simulation.gd")
const Destruction := preload("res://scripts/core/terrain/voxel_destruction.gd")
const State := preload("res://scripts/core/rules/match_state.gd")
const Motion := preload("res://scripts/core/rules/player_motion.gd")
const Command := preload("res://scripts/core/turns/player_action_command.gd")
const Player := preload("res://scripts/core/rules/player_state.gd")

var world: RefCounted
var materials: Dictionary
var rules: Resource
var weapons: Dictionary
var state: RefCounted
var initial_materials: PackedInt32Array
var initial_health: PackedInt32Array
var initial_players: Array = []
var statistics: Dictionary = {}
var history: Array = []

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
	statistics.clear()
	history.clear()
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
		statistics[player.player_id] = {"shots": 0, "hits": 0, "damage": 0, "kills": 0}
		state.inventory[player.player_id] = {}
		for id in weapons:
			state.inventory[player.player_id][id] = weapons[id].max_uses_per_match

func submit(command: RefCounted) -> Dictionary:
	if command == null or not command is Command:
		return {"ok": false, "reason": "invalid_command"}
	if not rules.validate() or not weapons.values().all(func(weapon): return weapon.validate()):
		return {"ok": false, "reason": "invalid_config"}
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
	var previous_health := {}
	for player in state.players:
		previous_health[player.player_id] = player.health
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
			var amount: int = weapon.damage_at_distance(distance)
			if amount > 0:
				player.apply_damage(amount)
				events.append({"type": "PlayerDamaged", "player_id": player.player_id, "amount": amount})
			if player.is_alive and distance < weapon.player_damage_radius:
				apply_knockback(player, shot.position, weapon)
	settle_players(events)
	events.append({"type": "ShotResolved", "hit": shot.hit, "position": [shot.position.x, shot.position.y, shot.position.z], "weapon_id": weapon.id, "turn_id": state.turn_id, "seed": 0, "radius": weapon.explosion_radius})
	record_shot(active, weapon.id, previous_health, deltas.size(), deltas.filter(func(change): return change.material_id == 0).size())
	advance(events)
	state.revision += 1
	return {"ok": true, "reason": shot.reason, "events": events, "deltas": deltas, "path": shot.path, "state": state_snapshot()}

func settle_players(events: Array = []) -> void:
	for player in state.players:
		if not player.is_alive:
			continue
		var velocity := Vector3.ZERO
		for tick in range(600):
			velocity.y -= rules.player_gravity / 30.0
			velocity = Motion.displace(world, player, velocity, 1.0 / 30.0, materials)
			if player.position.y < -7:
				var amount: int = player.health
				player.apply_damage(amount)
				events.append({"type": "PlayerDamaged", "player_id": player.player_id, "amount": amount})
				break
			if velocity.y == 0:
				break

func apply_knockback(player: RefCounted, center: Vector3, weapon: Resource) -> void:
	var offset: Vector3 = player.position - center
	var factor := clampf(1.0 - offset.length() / weapon.player_damage_radius, 0.0, 1.0)
	var velocity: Vector3 = (offset.normalized() + Vector3.UP * 0.5).normalized() * weapon.knockback * factor
	for tick in range(60):
		velocity.y -= rules.player_gravity / 30.0
		velocity = Motion.displace(world, player, velocity, 1.0 / 30.0, materials)
		if velocity.y == 0 or player.position.y < -7:
			break

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
	if rules.max_turns > 0 and state.turn_id >= rules.max_turns:
		state.status = "ended"
		state.winner_team = 0
		state.winner_player = ""
		events.append({"type": "MatchEnded", "team_id": 0, "player_id": ""})
		return
	state.time_remaining = rules.turn_time
	events.append({"type": "TurnStarted", "turn_id": state.turn_id, "player_id": state.get_active_player().player_id})

func tick(delta: float) -> Array:
	var events: Array = []
	if state.status != "playing" or not is_finite(delta) or delta < 0:
		return events
	if check_end(events):
		state.revision += 1
		return events
	var active = state.get_active_player()
	if active == null or not active.is_alive:
		advance(events)
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
		players.append({"id": player.player_id, "name": player.display_name, "team": player.team_id, "position": [player.position.x, player.position.y, player.position.z], "rotation": [player.rotation.x.x,player.rotation.x.y,player.rotation.x.z,player.rotation.y.x,player.rotation.y.y,player.rotation.y.z,player.rotation.z.x,player.rotation.z.y,player.rotation.z.z], "health": player.health, "alive": player.is_alive})
	return {"statistics": statistics.duplicate(true), "history": history.duplicate(true), "players": players, "max_shot_power": state.max_shot_power, "turn_id": state.turn_id, "active_index": state.active_player_index, "status": state.status, "time_remaining": state.time_remaining, "winner_team": state.winner_team, "winner_player": state.winner_player, "inventory": state.inventory.duplicate(true), "revision": state.revision, "generation": state.generation}

func record_shot(shooter: RefCounted, weapon_id: int, previous_health: Dictionary, terrain_changes: int, terrain_destroyed: int) -> void:
	var damage := 0
	var kills := 0
	for player in state.players:
		if player.player_id == shooter.player_id or (shooter.team_id != 0 and player.team_id == shooter.team_id):
			continue
		damage += maxi(0, int(previous_health[player.player_id]) - player.health)
		if previous_health[player.player_id] > 0 and not player.is_alive:
			kills += 1
	var metrics: Dictionary = statistics[shooter.player_id]
	metrics.shots += 1
	metrics.hits += 1 if damage > 0 else 0
	metrics.damage += damage
	metrics.kills += kills
	history.append({"player_id": shooter.player_id, "weapon_id": weapon_id, "turn_id": state.turn_id, "damage": damage, "kills": kills, "terrain_changes": terrain_changes, "terrain_destroyed": terrain_destroyed})
	if history.size() > 32:
		history.pop_front()

func surrender(player_id: String) -> Dictionary:
	if state.status != "playing":
		return {"ok": false, "reason": "match_ended"}
	for player in state.players:
		if player.player_id != player_id:
			continue
		if not player.is_alive:
			return {"ok": false, "reason": "player_dead"}
		var was_active: bool = player == state.get_active_player()
		player.apply_damage(player.health)
		var events: Array = [{"type": "PlayerSurrendered", "player_id": player_id}]
		if was_active:
			advance(events)
		else:
			check_end(events)
		state.revision += 1
		return {"ok": true, "reason": "surrendered", "events": events, "deltas": [], "path": PackedVector3Array(), "state": state_snapshot()}
	return {"ok": false, "reason": "unknown_player"}
