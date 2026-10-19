extends RefCounted
const Replay = preload("res://scripts/core/replay/match_replay.gd")
const Notes = preload("res://scripts/core/replay/replay_notebook.gd")
const MAX_STEP := 4096
var index := 0
var finished := true
var error := ""
var result_recorder: RefCounted
var result_runner: RefCounted
var _source: RefCounted
var _runner: RefCounted
var _start := 0
var _end := 0
func begin(recording: RefCounted, start: Variant, end: Variant) -> bool:
	cancel()
	error = "invalid_range"
	if recording == null or not recording.valid_data() or not recording.recording_error.is_empty() or not start is int or not end is int or start < 0 or end <= start or end > recording.data.actions.size(): return false
	_source = Replay.new()
	_source.data = recording.data.duplicate(true)
	_runner = _source.initial_runner()
	if _runner == null: error = "invalid_initial_state"; return false
	_start = start
	_end = end
	index = 0
	finished = false
	error = ""
	if _start == 0: _capture()
	return true
func _capture() -> void:
	result_recorder = Replay.new()
	result_recorder.capture(_runner)
func step(budget := 32) -> Dictionary:
	if finished: return {"ok":error.is_empty(),"reason":error,"finished":true,"index":index,"phase":"complete"}
	if budget <= 0: return {"ok":false,"reason":"invalid_budget","index":index,"phase":"prefix" if index < _start else "clip"}
	var work := 0
	while index < _end and work < mini(budget,MAX_STEP):
		var action: Dictionary = _source.data.actions[index]
		var executed: Dictionary = Replay.execute_action(_runner,action)
		if not executed.ok:
			error = str(executed.get("reason","action_failed"))
			finished = true
			result_recorder = null
			return {"ok":false,"reason":error,"finished":true,"index":index}
		if index >= _start: result_recorder.record_action(action.duplicate(true))
		index += 1
		work += 1
		if index == _start: _capture()
	if index == _end:
		finished = true
		result_runner = _runner
	return {"ok":true,"finished":finished,"index":index,"end":_end,"work":work,"phase":"complete" if finished else ("prefix" if index < _start else "clip")}
func cancel() -> void:
	finished = true
	error = "cancelled"
	result_recorder = null
	result_runner = null
	_source = null
	_runner = null
func notebook_for_clip(notebook: RefCounted) -> RefCounted:
	var notes := Notes.new()
	if not finished or result_recorder == null: return notes
	notes.bind(Notes.fingerprint(result_recorder),_end-_start)
	for row in notebook.list():
		if row.index >= _start and row.index <= _end: notes.add(row.index-_start,row.title,row.body,row.category)
	return notes
