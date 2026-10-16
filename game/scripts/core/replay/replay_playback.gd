class_name ReplayPlayback
extends RefCounted

const Replay = preload("res://scripts/core/replay/match_replay.gd")
var runner: RefCounted
var index := 0
var action_count := 0
var finished: bool:
	get: return index >= action_count
var current_action_type := ""
var elapsed_time := 0.0
var _recording: RefCounted

func load_recording(recorder: RefCounted) -> bool:
	if recorder == null or not recorder.recording_error.is_empty() or not recorder.valid_data():
		return false
	var candidate := Replay.new()
	candidate.data = recorder.data.duplicate(true)
	var initial: RefCounted = candidate.initial_runner()
	if initial == null:
		return false
	_recording = candidate
	runner = initial
	index = 0
	action_count = candidate.data.actions.size()
	current_action_type = ""
	elapsed_time = 0.0
	return true

func step() -> Dictionary:
	if _recording == null or finished:
		return {"ok": false, "reason": "finished"}
	var action: Dictionary = _recording.data.actions[index]
	var result: Dictionary = Replay.execute_action(runner, action)
	if result.ok:
		index += 1
		current_action_type = action.type
		if action.type == "tick":
			elapsed_time += action.delta
		result["type"] = action.type
		result["index"] = index
	return result

func seek(target: int) -> bool:
	if _recording == null or target < 0 or target > action_count:
		return false
	# Build separately so an invalid timeline cannot destroy the current cursor.
	var candidate: RefCounted = _recording.initial_runner()
	if candidate == null:
		return false
	var elapsed := 0.0
	for i in range(target):
		var action: Dictionary = _recording.data.actions[i]
		if not Replay.execute_action(candidate, action).ok:
			return false
		if action.type == "tick":
			elapsed += action.delta
	runner = candidate
	index = target
	elapsed_time = elapsed
	current_action_type = _recording.data.actions[target - 1].type if target > 0 else ""
	return true
