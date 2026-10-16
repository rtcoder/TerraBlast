class_name ReplayArchive
extends RefCounted

const Replay = preload("res://scripts/core/replay/match_replay.gd")
const Exact = preload("res://scripts/core/replay/exact_json.gd")
const MAX_BYTES := 32 * 1024 * 1024

static func save(path: String, recorder: RefCounted, runner: RefCounted) -> Error:
	if recorder == null or runner == null or not recorder.recording_error.is_empty() or not recorder.valid_data():
		return ERR_INVALID_DATA
	var encoded: Variant = Exact.encode({"version": 2, "recording": recorder.data, "expected_hash": Replay.state_hash(runner), "hash_precision": "full"})
	if encoded == null:
		return ERR_INVALID_DATA
	var content := JSON.stringify(encoded, "", true, true)
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

static func load_verified(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "reason": "open_failed", "runner": null}
	if file.get_length() > MAX_BYTES:
		file.close()
		return {"ok": false, "reason": "file_too_large", "runner": null}
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	file.close()
	if error != OK:
		return {"ok": false, "reason": "invalid_json", "runner": null}
	var parsed: Variant = parser.data
	if parsed is Dictionary and parsed.get("version") == 2:
		parsed = Exact.decode(parsed)
	if not parsed is Dictionary or not Replay.number(parsed.get("version"), 1, 2, true) or not parsed.get("recording") is Dictionary or not parsed.get("expected_hash") is String or parsed.expected_hash.length() != 64:
		return {"ok": false, "reason": "invalid_archive", "runner": null}
	var recorder := Replay.new()
	recorder.data = parsed.recording
	var runner: RefCounted = recorder.replay()
	if runner == null:
		return {"ok": false, "reason": "invalid_recording", "runner": null}
	if parsed.get("hash_precision", "legacy") not in ["full", "legacy"]:
		return {"ok": false, "reason": "invalid_archive", "runner": null}
	if Replay.state_hash(runner, parsed.get("hash_precision", "legacy") == "full") != parsed.expected_hash:
		return {"ok": false, "reason": "hash_mismatch", "runner": null}
	return {"ok": true, "reason": "verified", "runner": runner, "recorder": recorder}
