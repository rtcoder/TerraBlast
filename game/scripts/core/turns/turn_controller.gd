class_name TurnController
extends RefCounted

var players: Array = []
var active_player_index := 0
var turn_id := 0
var max_shot_power := 4.0

func _init(initial_players: Array = []) -> void:
	players = initial_players
	active_player_index = _find_next_alive_index(-1)

func get_active_player() -> Variant:
	if players.is_empty() or active_player_index < 0:
		return null
	return players[active_player_index]

func validate_action(command: RefCounted) -> Dictionary:
	var active_player: Variant = get_active_player()
	if active_player == null:
		return {"ok": false, "reason": "no_active_player"}
	if not active_player.is_alive:
		return {"ok": false, "reason": "active_player_dead"}
	if command.player_id != active_player.player_id:
		return {"ok": false, "reason": "inactive_player"}
	if command.turn_id != turn_id:
		return {"ok": false, "reason": "wrong_turn"}

	command.shot_power = clampf(command.shot_power, 0.0, max_shot_power)
	return {"ok": true, "reason": "accepted"}

func complete_turn() -> void:
	turn_id += 1
	active_player_index = _find_next_alive_index(active_player_index)

func get_living_players() -> Array:
	var living: Array = []
	for player: Variant in players:
		if player.is_alive:
			living.append(player)
	return living

func has_winner() -> bool:
	return get_living_players().size() <= 1

func _find_next_alive_index(from_index: int) -> int:
	if players.is_empty():
		return -1

	for step in range(1, players.size() + 1):
		var candidate := (from_index + step) % players.size()
		if players[candidate].is_alive:
			return candidate

	return -1
