extends SceneTree
const Replay = preload("res://scripts/core/replay/match_replay.gd")
const Archive = preload("res://scripts/core/replay/replay_archive.gd")
const Factory = preload("res://scripts/core/rules/match_factory.gd")
var failures := 0
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	var recorder = Replay.new()
	check(recorder.has_method("surrender"), "Surrender is recorded")
	check(ResourceLoader.exists("res://scripts/core/replay/replay_playback.gd"), "Step playback exists")
	check(ResourceLoader.exists("res://scripts/core/replay/session_store.gd"), "Session checkpoint exists")
	if failures == 0:
		behavior()
	print("core_replay_oct16: %d failures" % failures)
	quit(1 if failures else 0)
func behavior() -> void:
	var runner = Factory.create_match(2)
	var recorder = Replay.new()
	recorder.capture(runner)
	var velocity := Vector3.ZERO
	for i in range(1800):
		velocity = recorder.move(runner, velocity, Vector2(0.12345, -0.23456), 0.713214, false, 1.0 / 60.0)
		recorder.tick(runner, 1.0 / 60.0)
	var command = load("res://scripts/core/turns/player_action_command.gd").new()
	command.player_id = runner.state.get_active_player().player_id
	command.turn_id = runner.state.turn_id
	command.generation = runner.state.generation
	command.weapon_id = 1
	command.aim_direction = Vector3.UP
	command.shot_power = 0.75
	check(recorder.submit(runner, command).ok, "Recorded shot accepted")
	check(not recorder.surrender(runner, "unknown").ok, "Rejected surrender excluded")
	check(recorder.surrender(runner, runner.state.get_active_player().player_id).ok, "Accepted surrender recorded")
	check(recorder.data.actions.size() == 3602, "Only accepted surrender included")
	var path := "/tmp/replay-oct16-archive.json"
	check(Archive.save(path, recorder, runner) == OK, "Exact float archive saved")
	var loaded := Archive.load_verified(path)
	check(loaded.ok, "Long move/tick archive verifies exactly")
	if loaded.ok:
		check(loaded.has("recorder"), "Verified recording returned")
		var playback = load("res://scripts/core/replay/replay_playback.gd").new()
		check(playback.load_recording(loaded.recorder), "Playback initializes")
		check(playback.index == 0 and playback.action_count == 3602 and not playback.finished, "Playback begins at initial state")
		check(not playback.seek(-1) and not playback.seek(3603) and playback.index == 0, "Seek bounds preserve cursor")
		check(playback.seek(3600), "Seek to shot")
		var shot: Dictionary = playback.step()
		check(shot.ok and shot.result.ok and shot.result.has("path"), "Shot step returns visual result")
		check(playback.step().ok and playback.finished, "Surrender step finishes")
		check(Replay.state_hash(playback.runner) == Replay.state_hash(runner), "Step end equals live state")
		check(not playback.step().ok and playback.seek(0) and playback.index == 0, "Finished step and rewind controlled")
	shot_limit()
	validation_and_legacy()
	checkpoint(runner)
	checkpoint_velocity()
	exact_float_parser_roundtrip()
	exact_codec_validation()
	var limited = Replay.new()
	var live = Factory.create_match(2)
	limited.capture(live)
	for i in range(100001):
		limited.tick(live, 0.00001)
	check(limited.data.actions.size() == 100000 and not limited.recording_error.is_empty(), "Live recording bounded")
	check(live.state.time_remaining < live.rules.turn_time - 1.0, "Live game advances after recording cap")
	check(Archive.save(path, limited, live) == ERR_INVALID_DATA, "Truncated capture cannot save")
	limited.capture(live)
	check(limited.recording_error.is_empty(), "New capture resets error")
	var empty = load("res://scripts/core/replay/replay_playback.gd").new()
	check(empty.load_recording(limited) and empty.finished and empty.seek(0), "Empty playback supports rewind")
	DirAccess.remove_absolute(path)
func checkpoint(runner) -> void:
	var store = load("res://scripts/core/replay/session_store.gd")
	var path := "/tmp/replay-oct16-session.json"
	var options := {"mode": "solo", "difficulty": "normal", "human_team": 1}
	check(store.save(path, runner, options) == OK, "Checkpoint saved")
	var loaded: Dictionary = store.load(path)
	check(loaded.ok and loaded.options == options and Replay.state_hash(loaded.runner) == Replay.state_hash(runner), "Checkpoint restores exact state/options")
	for bad in [{}, {"mode":"online","difficulty":"normal","human_team":1}, {"mode":"solo","difficulty":"hard","human_team":1}, {"mode":"solo","difficulty":"easy","human_team":0}, {"mode":"solo","difficulty":"easy","human_team":true}]:
		check(store.save(path,runner,bad) == ERR_INVALID_DATA, "Invalid session options rejected")
	var file := FileAccess.open(path, FileAccess.READ)
	var original = JSON.parse_string(file.get_as_text())
	file.close()
	for field in ["version", "expected_hash", "recording"]:
		var corrupted: Dictionary = original.duplicate(true)
		corrupted[field] = 99 if field == "version" else ("0".repeat(64) if field == "expected_hash" else {})
		file = FileAccess.open(path,FileAccess.WRITE)
		file.store_string(JSON.stringify(corrupted,"",true,true))
		file.close()
		check(not store.load(path).ok, "Corrupt checkpoint rejected: " + field)
	file = FileAccess.open(path,FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	check(not store.load(path).ok, "Malformed checkpoint rejected")
	file = FileAccess.open(path,FileAccess.WRITE)
	file.seek(32 * 1024 * 1024)
	file.store_8(0)
	file.close()
	check(store.load(path).reason == "file_too_large", "Checkpoint bounded before parsing")
	DirAccess.remove_absolute(path)

func validation_and_legacy() -> void:
	var runner = Factory.create_match(2)
	var recorder := Replay.new()
	recorder.capture(runner)
	var before := Replay.state_hash(runner)
	runner.state.time_remaining -= 0.000000000001
	check(Replay.state_hash(runner) != before, "Hash detects sub-default-precision float changes")
	var path := "/tmp/replay-oct16-legacy.json"
	# Old files used the default JSON precision for both content and hash.
	var initial = recorder.replay()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 1, "recording": recorder.data, "expected_hash": Replay.state_hash(initial, false)}))
	file.close()
	check(Archive.load_verified(path).ok, "Legacy v1 hash still verifies")
	for action in [{"type":"surrender", "player_id":"unknown"}, {"type":"surrender"}, {"type":"tick","delta":INF}, {"type":"tick","delta":-1}, {"type":"unknown"}, {"type":"move","velocity":[0,0,0],"input":[0,0],"yaw":0,"jump":1,"delta":0.01}]:
		var invalid := Replay.new()
		invalid.data = recorder.data.duplicate(true)
		invalid.data.actions.append(action)
		check(not invalid.valid_data() and invalid.replay() == null, "Malformed replay action rejected")
	var impossible := Replay.new()
	impossible.data = recorder.data.duplicate(true)
	impossible.data.actions = [{"type":"surrender","player_id":"blue_1"}, {"type":"surrender","player_id":"blue_1"}]
	check(impossible.replay() == null, "Semantically rejected action fails replay")
	var playback = load("res://scripts/core/replay/replay_playback.gd").new()
	check(playback.load_recording(impossible), "Valid syntax initializes playback")
	check(playback.step().ok and not playback.step().ok and playback.index == 1, "Rejected replay step preserves cursor")
	check(not playback.seek(2) and playback.index == 1, "Failed seek preserves cursor")
	var store = load("res://scripts/core/replay/session_store.gd")
	check(store.save(path, initial, {"mode":"hotseat","difficulty":"easy","human_team":2}) == OK, "Alternative valid session options saved")
	file = FileAccess.open(path, FileAccess.READ)
	var content = JSON.parse_string(file.get_as_text())
	file.close()
	content.recording.actions = [{"type":"tick","delta":0}]
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(content,"",true,true))
	file.close()
	check(not store.load(path).ok, "Session cannot embed a replay timeline")
	DirAccess.remove_absolute(path)

func shot_limit() -> void:
	var runner = Factory.create_match(2)
	runner.rules.max_projectile_lifetime = 0.1
	runner.weapons[1] = runner.weapons[1].duplicate()
	runner.weapons[1].gravity_scale = 0.0
	var recorder := Replay.new()
	recorder.capture(runner)
	for i in range(257):
		var command = load("res://scripts/core/turns/player_action_command.gd").new()
		command.player_id = runner.state.get_active_player().player_id
		command.turn_id = runner.state.turn_id
		command.generation = runner.state.generation
		command.weapon_id = 1
		command.aim_direction = Vector3.UP
		command.shot_power = 1
		check(recorder.submit(runner,command).ok, "Live shot remains accepted at replay budget")
	check(not recorder.recording_error.is_empty() and recorder.data.actions.size() == 256, "Shot budget overflow is explicit and bounded")
	check(runner.state.turn_id == 257, "Shot budget does not stop game")

func checkpoint_velocity() -> void:
	var store = load("res://scripts/core/replay/session_store.gd")
	var runner = Factory.create_match(2)
	var options := {"mode":"solo","difficulty":"normal","human_team":1}
	var path := "/tmp/replay-oct16-airborne.json"
	check(store.save(path,runner,options) == OK, "Velocity fixture saved")
	var loaded: Dictionary = store.load(path)
	check(loaded.has("velocities"), "Checkpoint restores airborne velocities")
	if not loaded.has("velocities"):
		DirAccess.remove_absolute(path)
		return
	var velocities := {"blue_1": Vector3(1.234567,5.4321,-2.345678), "red_1":Vector3.ZERO}
	check(store.save(path,runner,options,velocities) == OK, "Airborne checkpoint saved")
	loaded = store.load(path)
	check(loaded.ok and loaded.velocities == velocities, "Airborne velocity preserved exactly: " + str(loaded))
	if not loaded.ok:
		return
	var motion = load("res://scripts/core/rules/player_motion.gd")
	var live_velocity: Vector3 = motion.move(runner.world,runner.state.get_active_player(),velocities.blue_1,Vector2.ZERO,0,false,0.016,runner.rules,runner.materials)
	var resumed_velocity: Vector3 = motion.move(loaded.runner.world,loaded.runner.state.get_active_player(),loaded.velocities.blue_1,Vector2.ZERO,0,false,0.016,loaded.runner.rules,loaded.runner.materials)
	check(live_velocity == resumed_velocity and runner.state.get_active_player().position == loaded.runner.state.get_active_player().position, "Resumed airborne motion follows same next step")
	for bad in [{"blue_1":Vector3.ZERO}, {"blue_1":Vector3.ZERO,"red_1":Vector3(INF,0,0)}, {"blue_1":Vector3.ZERO,"red_1":Vector3(1001,0,0)}, {"blue_1":[0,0,0],"red_1":Vector3.ZERO}, {"blue_1":Vector3.ZERO,"alien":Vector3.ZERO}]:
		check(store.save(path,runner,options,bad) == ERR_INVALID_DATA, "Malformed live velocities rejected")
	var file := FileAccess.open(path,FileAccess.READ)
	var original = JSON.parse_string(file.get_as_text())
	file.close()
	for bad in [{"blue_1":[0,0,0]}, {"blue_1":[0,0,0],"red_1":[1001,0,0]}, {"blue_1":[0,0],"red_1":[0,0,0]}, {"blue_1":[0,0,0],"red_1":[0,0,0]}]:
		var tampered: Dictionary = original.duplicate(true)
		tampered.velocities = bad
		file = FileAccess.open(path,FileAccess.WRITE)
		file.store_string(JSON.stringify(tampered,"",true,true))
		file.close()
		check(not store.load(path).ok, "Malformed or tampered velocities rejected")
	var legacy: Dictionary = load("res://scripts/core/replay/exact_json.gd").decode(original)
	legacy.version = 1
	legacy.erase("velocities")
	var recorder := Replay.new()
	recorder.data = legacy.recording
	legacy.expected_hash = Replay.state_hash(recorder.replay())
	file = FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy,"",true,true))
	file.close()
	loaded = store.load(path)
	check(loaded.ok and loaded.velocities == {"blue_1":Vector3.ZERO,"red_1":Vector3.ZERO}, "Legacy v1 session has complete zero velocities")
	DirAccess.remove_absolute(path)

func exact_float_parser_roundtrip() -> void:
	var store = load("res://scripts/core/replay/session_store.gd")
	var runner = Factory.create_match(2)
	runner.state.time_remaining = 20.0
	var recorder := Replay.new()
	recorder.capture(runner)
	recorder.tick(runner, 0.1)
	recorder.tick(runner, 0.05)
	var path := "/tmp/replay-oct16-exact-float.json"
	var options := {"mode":"solo","difficulty":"easy","human_team":1}
	check(store.save(path,runner,options) == OK, "Fractional timer snapshot saves")
	var loaded: Dictionary = store.load(path)
	check(loaded.ok and loaded.runner.state.time_remaining == runner.state.time_remaining, "Fractional timer survives JSON parser exactly")
	check(Archive.save(path,recorder,runner) == OK and Archive.load_verified(path).ok, "Fractional tick replay archive verifies")
	# Initial snapshots and action arguments both need exact encoding.
	recorder.capture(runner)
	recorder.tick(runner, 0.12345678901234567)
	check(Archive.save(path,recorder,runner) == OK, "Arbitrary float replay saves")
	loaded = Archive.load_verified(path)
	check(loaded.ok and loaded.runner.state.time_remaining == runner.state.time_remaining, "Arbitrary snapshot and action floats survive parser")
	DirAccess.remove_absolute(path)

func exact_codec_validation() -> void:
	var codec = load("res://scripts/core/replay/exact_json.gd")
	for value in [20.0 - 0.1 - 0.05, 0.12345678901234567, -0.0, 1.0e-200, 1.0e200]:
		var encoded: Variant = codec.encode(value)
		var decoded: Variant = codec.decode(JSON.parse_string(JSON.stringify(encoded,"",true,true)))
		check(codec.encode(decoded) == encoded, "Exact codec preserves IEEE754 bits")
	for tag in [{"$f64":"bad"}, {"$f64":"0123456789abcdeg"}, {"$f64":12}, {"$f64":"000000000000f07f"}, {"$f64":"000000000000f87f"}, {"$f64":"0000000000000000","extra":true}]:
		check(codec.decode(tag) == null, "Malformed or nonfinite float tag rejected")
	var nested: Variant = 1
	for i in range(40):
		nested = [nested]
	check(codec.decode(nested) == null and codec.encode(nested) == null, "Exact codec recursion bounded")
	check(codec.encode(INF) == null and codec.encode(NAN) == null, "Nonfinite float encoding rejected")
	var runner = Factory.create_match(2)
	var recorder := Replay.new()
	recorder.capture(runner)
	recorder.tick(runner,0.01)
	var path := "/tmp/replay-oct16-bad-tag.json"
	check(Archive.save(path,recorder,runner) == OK, "Tag corruption fixture saves")
	var file := FileAccess.open(path,FileAccess.READ)
	var payload = JSON.parse_string(file.get_as_text())
	file.close()
	payload.recording.actions[0].delta = {"$f64":"000000000000f87f"}
	file = FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(payload,"",true,true))
	file.close()
	check(not Archive.load_verified(path).ok, "Archive rejects nonfinite encoded action")
	DirAccess.remove_absolute(path)
