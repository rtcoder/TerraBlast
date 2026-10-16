class_name SessionStore
extends RefCounted

const Replay = preload("res://scripts/core/replay/match_replay.gd")
const Exact = preload("res://scripts/core/replay/exact_json.gd")
const MAX_BYTES := 32 * 1024 * 1024

static func valid_options(options: Variant) -> bool:
	return options is Dictionary and options.size() == 3 and options.get("mode") in ["hotseat", "solo"] and options.get("difficulty") in ["easy", "normal"] and Replay.number(options.get("human_team"), 1, 2, true)

static func save(path: String, runner: RefCounted, options: Dictionary, velocities: Dictionary = {}) -> Error:
	if runner == null or not valid_options(options):
		return ERR_INVALID_DATA
	var recorder := Replay.new()
	recorder.capture(runner)
	if not recorder.valid_data():
		return ERR_INVALID_DATA
	var encoded := {}
	if not velocities.is_empty() and velocities.size() != runner.state.players.size():
		return ERR_INVALID_DATA
	for player in runner.state.players:
		if not velocities.is_empty() and not velocities.has(player.player_id):
			return ERR_INVALID_DATA
		var velocity: Variant = velocities.get(player.player_id, Vector3.ZERO)
		if not velocity is Vector3 or not velocity.is_finite():
			return ERR_INVALID_DATA
		var components := [velocity.x, velocity.y, velocity.z]
		if not Replay.numbers(components, 3, -1000, 1000):
			return ERR_INVALID_DATA
		encoded[player.player_id] = components
	var payload: Variant = Exact.encode({"format": "terrablast_session", "version": 2, "recording": recorder.data, "options": options, "velocities": encoded, "expected_hash": session_hash(runner, options, encoded)})
	if payload == null:
		return ERR_INVALID_DATA
	var content := JSON.stringify(payload, "", true, true)
	if content.to_utf8_buffer().size() > MAX_BYTES:
		return ERR_OUT_OF_MEMORY
	var temporary := path + ".tmp-" + str(OS.get_process_id()) + "-" + str(Time.get_ticks_usec())
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(content)
	file.flush()
	var error := file.get_error()
	file.close()
	if error == OK:
		error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		DirAccess.remove_absolute(temporary)
	return error

static func failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "runner": null, "options": {}, "velocities": {}}

static func load(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return failure("open_failed")
	if file.get_length() > MAX_BYTES:
		file.close()
		return failure("file_too_large")
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	file.close()
	if error != OK:
		return failure("invalid_json")
	var parsed: Variant = parser.data
	if parsed is Dictionary and parsed.get("version") == 2:
		parsed = Exact.decode(parsed)
	if not parsed is Dictionary or parsed.get("format") != "terrablast_session" or not Replay.number(parsed.get("version"), 1, 2, true) or not parsed.get("recording") is Dictionary or not parsed.get("expected_hash") is String or parsed.expected_hash.length() != 64 or not valid_options(parsed.get("options")):
		return failure("invalid_session")
	var expected_keys := ["format", "version", "recording", "options", "expected_hash"]
	if parsed.version == 2:
		expected_keys.append("velocities")
	if parsed.size() != expected_keys.size():
		return failure("invalid_session")
	for key in expected_keys:
		if not parsed.has(key):
			return failure("invalid_session")
	var recorder := Replay.new()
	recorder.data = parsed.recording
	if not recorder.valid_data() or not recorder.data.actions.is_empty():
		return failure("invalid_snapshot")
	var runner: RefCounted = recorder.initial_runner()
	if runner == null:
		return failure("invalid_snapshot")
	var encoded := {}
	var velocities := {}
	if parsed.version == 2 and (not parsed.velocities is Dictionary or parsed.velocities.size() != runner.state.players.size()):
		return failure("invalid_velocities")
	for player in runner.state.players:
		var components: Variant = parsed.velocities.get(player.player_id) if parsed.version == 2 else [0, 0, 0]
		if not Replay.numbers(components, 3, -1000, 1000):
			return failure("invalid_velocities")
		# Canonicalize through Vector3, matching runtime float precision.
		var velocity := Replay.vector(components)
		velocities[player.player_id] = velocity
		encoded[player.player_id] = [velocity.x, velocity.y, velocity.z]
	var expected := session_hash(runner, parsed.options, encoded) if parsed.version == 2 else Replay.state_hash(runner)
	if expected != parsed.expected_hash:
		return failure("hash_mismatch")
	var options: Dictionary = parsed.options.duplicate()
	options.human_team = int(options.human_team)
	return {"ok": true, "reason": "verified", "runner": runner, "options": options, "velocities": velocities}

static func session_hash(runner: RefCounted, options: Dictionary, encoded_velocities: Dictionary) -> String:
	var canonical_options := {"mode": options.mode, "difficulty": options.difficulty, "human_team": int(options.human_team)}
	return JSON.stringify({"state_hash": Replay.state_hash(runner), "options": canonical_options, "velocities": encoded_velocities}, "", true, true).sha256_text()
