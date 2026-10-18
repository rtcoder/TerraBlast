class_name ReplayPlayback
extends RefCounted

const Replay = preload("res://scripts/core/replay/match_replay.gd")
# The largest legal tick must fit; excess wall time is intentionally dropped.
const MAX_PENDING_TIME := 600.0
const MAX_ADVANCE_ACTIONS := 4096
var runner: RefCounted
var index := 0
var action_count := 0
var finished: bool:
	get: return index >= action_count
var current_action_type := ""
var elapsed_time := 0.0
var duration := 0.0
var playing := false
var speed := 1.0
var last_error := ""
var _recording: RefCounted
var _times := PackedFloat64Array([0.0])
var _shots := PackedInt32Array()
var _pending_time := 0.0

func load_recording(recorder: RefCounted) -> bool:
	if recorder == null or not recorder.recording_error.is_empty() or not recorder.valid_data():
		last_error = "invalid_recording"
		return false
	var candidate := Replay.new()
	candidate.data = recorder.data.duplicate(true)
	var initial: RefCounted = candidate.initial_runner()
	if initial == null:
		last_error = "invalid_initial_state"
		return false
	var times := PackedFloat64Array([0.0])
	var shots := PackedInt32Array()
	var time := 0.0
	for i in range(candidate.data.actions.size()):
		var action: Dictionary = candidate.data.actions[i]
		if action.type == "tick": time += action.delta
		if action.type == "shot": shots.append(i)
		times.append(time)
	_recording = candidate
	runner = initial
	index = 0
	action_count = candidate.data.actions.size()
	current_action_type = ""
	elapsed_time = 0.0
	duration = time
	_times = times
	_shots = shots
	_pending_time = 0.0
	playing = false
	last_error = ""
	return true

func set_playing(value: bool) -> void:
	playing = value and _recording != null and not finished

func set_speed(value: float) -> bool:
	if not is_finite(value) or value < 0.25 or value > 4.0:
		last_error = "invalid_speed"
		return false
	speed = value
	last_error = ""
	return true

func advance(delta: float, max_actions: int = 256) -> Dictionary:
	if not is_finite(delta) or delta < 0.0:
		return _advance_error("invalid_delta")
	if max_actions <= 0:
		return _advance_error("invalid_budget")
	if _recording == null:
		return _advance_error("not_loaded")
	var results: Array = []
	if finished: playing = false
	if not playing:
		return {"ok": true, "results": results, "changed": false}
	# Clamp before multiplication to keep even huge finite caller deltas finite.
	_pending_time = minf(MAX_PENDING_TIME, _pending_time + minf(delta, MAX_PENDING_TIME / speed) * speed)
	for unused in range(mini(max_actions, MAX_ADVANCE_ACTIONS)):
		if finished: break
		var action: Dictionary = _recording.data.actions[index]
		var cost: float = action.delta if action.type == "tick" else 0.0
		if cost > _pending_time: break
		var result := _execute_next()
		if not result.ok:
			return {"ok": false, "reason": last_error, "results": results, "changed": not results.is_empty()}
		_pending_time = maxf(0.0, _pending_time - cost)
		results.append(result)
	if finished:
		playing = false
		_pending_time = 0.0
	last_error = ""
	return {"ok": true, "results": results, "changed": not results.is_empty()}

func _advance_error(reason: String) -> Dictionary:
	playing = false
	last_error = reason
	return {"ok": false, "reason": reason, "results": [], "changed": false}

func step() -> Dictionary:
	_pending_time = 0.0
	return _execute_next()

func _execute_next() -> Dictionary:
	if _recording == null or finished:
		playing = false
		last_error = "not_loaded" if _recording == null else "finished"
		return {"ok": false, "reason": last_error}
	var action: Dictionary = _recording.data.actions[index]
	var result: Dictionary = Replay.execute_action(runner, action)
	if result.ok:
		index += 1
		current_action_type = action.type
		elapsed_time = _times[index]
		result["type"] = action.type
		result["index"] = index
		last_error = ""
		if finished: playing = false
	else:
		playing = false
		last_error = str(result.get("reason", "action_failed"))
	return result

func seek(target: int) -> bool:
	if _recording == null or target < 0 or target > action_count:
		last_error = "invalid_seek"
		return false
	# Build separately so an invalid timeline cannot destroy the current cursor.
	var candidate: RefCounted = _recording.initial_runner()
	if candidate == null:
		last_error = "invalid_initial_state"
		return false
	for i in range(target):
		var result: Dictionary = Replay.execute_action(candidate, _recording.data.actions[i])
		if not result.ok:
			last_error = str(result.get("reason", "action_failed"))
			return false
	runner = candidate
	index = target
	elapsed_time = _times[target]
	current_action_type = _recording.data.actions[target - 1].type if target > 0 else ""
	_pending_time = 0.0
	if finished: playing = false
	last_error = ""
	return true

func seek_time(target: float) -> bool:
	if _recording == null or not is_finite(target) or target < 0.0 or target > duration:
		last_error = "invalid_seek_time"
		return false
	# Upper bound picks the last boundary, including all zero-time actions.
	var low := 0
	var high := _times.size()
	while low < high:
		var middle := low + (high - low) / 2
		if _times[middle] <= target:
			low = middle + 1
		else:
			high = middle
	return seek(low - 1)

func next_shot() -> bool:
	if _recording == null:
		last_error = "not_loaded"
		return false
	for shot_index in _shots:
		if shot_index >= index:
			return seek(shot_index + 1)
	last_error = "no_next_shot"
	return false

func previous_shot() -> bool:
	if _recording == null:
		last_error = "not_loaded"
		return false
	for i in range(_shots.size()-1,-1,-1):
		if _shots[i]+1 < index: return seek(_shots[i]+1)
	last_error = "no_previous_shot"
	return false

func next_turn() -> bool:
	if _recording == null:
		last_error = "not_loaded"
		return false
	var candidate: RefCounted = _recording.initial_runner()
	for i in index:
		if not Replay.execute_action(candidate,_recording.data.actions[i]).ok:
			last_error = "invalid_action"
			return false
	var turn: int = candidate.state.turn_id
	var generation: int = candidate.state.generation
	for i in range(index,action_count):
		if not Replay.execute_action(candidate,_recording.data.actions[i]).ok:
			last_error = "invalid_action"
			return false
		if candidate.state.turn_id!=turn or candidate.state.generation!=generation: return seek(i+1)
	last_error = "no_next_turn"
	return false

func action_description() -> String:
	if _recording == null or index==0: return "Initial state"
	var action: Dictionary = _recording.data.actions[index-1]
	var actor: String = str(action.get("player_id",""))
	for player in runner.state.players:
		if player.player_id==actor: actor = player.display_name; break
	match action.type:
		"tick": return "Advance simulation %.3f s" % action.delta
		"move": return "Move active player (%.3f s)" % action.delta
		"shot": return "%s — %s (power %.2f)" % [actor,runner.weapons[int(action.weapon_id)].display_name,action.power]
		"surrender": return "%s surrendered" % actor
	return str(action.type)

func recording_copy() -> RefCounted:
	if _recording == null: return null
	var copy := Replay.new()
	copy.data = _recording.data.duplicate(true)
	return copy
