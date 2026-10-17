extends SceneTree
const Replay = preload("res://scripts/core/replay/match_replay.gd")
const Playback = preload("res://scripts/core/replay/replay_playback.gd")
const Factory = preload("res://scripts/core/rules/match_factory.gd")
var failures := 0
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	var probe = Playback.new()
	check(probe.has_method("advance"), "Timed playback API exists")
	if failures == 0:
		behavior()
	print("replay_timeline: %d failures" % failures)
	quit(1 if failures else 0)
func behavior() -> void:
	var live = Factory.create_match(2)
	var recording = Replay.new()
	recording.capture(live)
	recording.move(live, Vector3.ZERO, Vector2.ZERO, 0, false, 0.1)
	recording.tick(live, 0.25)
	recording.tick(live, 0)
	recording.tick(live, 0.75)
	var playback = Playback.new()
	check(playback.load_recording(recording) and playback.duration == 1.0, "Only ticks contribute duration")
	check(playback.advance(1).results.is_empty() and playback.index == 0, "Paused playback stays unchanged")
	playback.set_playing(true)
	var result: Dictionary = playback.advance(0.125)
	check(result.ok and result.changed and result.results.size() == 1 and playback.index == 1 and playback.elapsed_time == 0, "Move runs but fractional tick waits")
	result = playback.advance(0.125)
	check(result.results.size() == 2 and playback.index == 3 and playback.elapsed_time == 0.25, "Whole tick and zero tick run at boundary")
	check(playback.set_speed(4), "Maximum speed accepted")
	result = playback.advance(0.1875)
	check(result.results.size() == 1 and playback.finished and not playback.playing, "Speed scales wall time and EOF pauses")
	check(Replay.state_hash(playback.runner) == Replay.state_hash(live), "Timed playback preserves exact hash")
	for speed in [0.25, 0.5, 1.0, 2.0, 4.0]:
		check(playback.seek(0) and playback.set_speed(speed), "Rewind and speed accepted")
		playback.set_playing(true)
		for i in range(600):
			if playback.finished: break
			check(playback.advance(0.03125, 1).results.size() <= 1, "Action budget respected")
		check(playback.finished and Replay.state_hash(playback.runner) == Replay.state_hash(live), "Different speed and budget preserve hash")
	check(playback.seek_time(0.24) and playback.index == 1, "Seek floors between tick boundaries")
	check(playback.seek_time(0.25) and playback.index == 3, "Seek includes duplicate time boundaries")
	check(playback.seek_time(0) and playback.index == 1, "Time zero includes leading zero-time actions")
	for invalid in [-1.0, 1.1, NAN, INF]:
		check(not playback.seek_time(invalid) and playback.index == 1, "Invalid time seek is atomic")
	for invalid in [0.0, 0.249, 4.01, NAN, INF]:
		check(not playback.set_speed(invalid) and playback.speed == 4, "Invalid speed rejected without mutation")
	for invalid in [-1.0, NAN, INF]:
		playback.set_playing(true)
		result = playback.advance(invalid)
		check(not result.ok and not playback.playing and playback.index == 1 and not result.reason.is_empty(), "Invalid delta explicitly pauses without mutation")
	playback.set_playing(true)
	check(not playback.advance(0.1, 0).ok and playback.index == 1, "Invalid budget rejected")
	check(not playback.next_shot() and playback.index == 1, "Absent shot leaves cursor intact")
	check(playback.seek(0), "Manual rewind")
	playback.set_speed(1)
	playback.set_playing(true)
	playback.advance(0.2)
	check(playback.seek(0), "Seek clears pending time")
	check(playback.advance(0.1).results.size() == 1 and playback.index == 1, "Old time debt cannot cross next tick after seek")
	empty_and_error()
	shots()
	bounded_time()
	zero_time_budget()
func empty_and_error() -> void:
	var recording = Replay.new()
	recording.capture(Factory.create_match(2))
	var playback = Playback.new()
	check(not playback.advance(0).ok, "Unloaded playback explicit error")
	check(playback.load_recording(recording) and playback.duration == 0 and playback.seek_time(0), "Empty replay supports timeline")
	playback.set_playing(true)
	check(not playback.playing and playback.advance(0).ok, "Empty replay cannot play")
	recording.data.actions = [{"type":"surrender", "player_id":"blue_1"}, {"type":"surrender", "player_id":"blue_1"}]
	check(playback.load_recording(recording), "Syntax-valid semantic error fixture")
	playback.set_playing(true)
	var result: Dictionary = playback.advance(0)
	check(not result.ok and result.changed and result.results.size() == 1 and playback.index == 1 and not playback.playing, "Semantic error pauses and retains prior results")
	var old_runner = playback.runner
	var old_hash := Replay.state_hash(old_runner)
	check(not playback.seek(2) and playback.runner == old_runner and playback.index == 1 and Replay.state_hash(playback.runner) == old_hash, "Failed seek preserves exact live cursor and runner")
func shots() -> void:
	var live = Factory.create_match(2)
	var recording = Replay.new()
	recording.capture(live)
	recording.tick(live, 0.1)
	var command = load("res://scripts/core/turns/player_action_command.gd").new()
	command.player_id = live.state.get_active_player().player_id
	command.turn_id = live.state.turn_id
	command.generation = live.state.generation
	command.weapon_id = 1
	command.aim_direction = Vector3.DOWN
	command.shot_power = 0.75
	check(recording.submit(live, command).ok, "Shot fixture accepted")
	var playback = Playback.new()
	check(playback.load_recording(recording) and playback.next_shot() and playback.index == 2 and playback.current_action_type == "shot", "Next shot lands after shot execution")
	check(Replay.state_hash(playback.runner) == Replay.state_hash(live), "Next shot exact state")
	playback.seek(0)
	playback.set_playing(true)
	var result: Dictionary = playback.advance(0.1)
	check(result.results.size() == 2 and result.results[1].result.has("deltas"), "Advance retains shot visual deltas")
func bounded_time() -> void:
	var live = Factory.create_match(2)
	var recording = Replay.new()
	recording.capture(live)
	for i in range(3): recording.tick(live, 600)
	var playback = Playback.new()
	check(playback.load_recording(recording), "Maximum tick fixture accepted")
	playback.set_playing(true)
	check(playback.advance(1e300, 1).results.size() == 1, "Huge finite wall delta bounded and can execute maximum tick")
	check(playback.advance(0, 1).results.is_empty(), "Huge frame cannot accumulate unbounded time debt")

func zero_time_budget() -> void:
	var recording = Replay.new()
	var live = Factory.create_match(2)
	recording.capture(live)
	for i in range(5000): recording.tick(live, 0)
	var playback = Playback.new()
	check(playback.load_recording(recording), "Zero-time recording loads")
	playback.set_playing(true)
	var result: Dictionary = playback.advance(0, 500000)
	check(result.ok and result.changed and result.results.size() > 0 and result.results.size() < 5000 and not playback.finished, "Caller cannot disable hard action budget for zero-time actions")
	result = playback.advance(0, 500000)
	check(result.ok and playback.finished and not playback.playing and playback.elapsed_time == 0, "Zero-time playback drains and stops at EOF")
	check(Replay.state_hash(playback.runner) == Replay.state_hash(live), "Zero-time budget retains exact state")
	check(playback.seek_time(0) and playback.finished, "Zero-duration timeline seek includes all actions")
