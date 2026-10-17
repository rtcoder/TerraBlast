class_name LocalArchiveLibrary
extends RefCounted

const Archive = preload("res://scripts/core/replay/replay_archive.gd")
const Session = preload("res://scripts/core/replay/session_store.gd")
const MAX_BYTES := 32 * 1024 * 1024
const MAX_ENTRIES := 100
const FORMAT := "terrablast_library"
var base_path: String

func _init(path: String = "user://archive_library") -> void:
	base_path = ProjectSettings.globalize_path(path).simplify_path()

static func failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func valid_id(id: String) -> bool:
	if id.length() != 32: return false
	for c in id:
		if c not in "0123456789abcdef": return false
	return true

static func valid_title(title: String) -> bool:
	if title.strip_edges().is_empty() or title.length() > 48: return false
	for i in range(title.length()):
		var code := title.unicode_at(i)
		if code < 32 or (code >= 127 and code <= 159): return false
	return true

# Check every path component, including the base directory, without following links.
# macOS /tmp itself is a system symlink; callers should use /private/tmp for strict paths.
func _safe_path(path: String) -> bool:
	var current := path
	while current != "/" and not current.is_empty():
		var parent := current.get_base_dir()
		var directory := DirAccess.open(parent)
		if directory != null and directory.is_link(current.get_file()): return false
		if parent == current: break
		current = parent
	return path.is_absolute_path()

func _ready_directory(create: bool = false) -> Dictionary:
	if not _safe_path(base_path): return failure("unsafe_path")
	if not DirAccess.dir_exists_absolute(base_path):
		if not create: return {"ok": true, "missing": true}
		if DirAccess.make_dir_recursive_absolute(base_path) != OK: return failure("directory_failed")
	return {"ok": true, "missing": false}

func _path(id: String) -> String:
	return base_path.path_join(id + ".json")

func _read(id: String) -> Dictionary:
	if not valid_id(id): return failure("invalid_id")
	var ready := _ready_directory()
	if not ready.ok: return ready
	var path := _path(id)
	if not _safe_path(path): return failure("unsafe_path")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return failure("open_failed")
	if file.get_length() > MAX_BYTES:
		file.close()
		return failure("file_too_large")
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	file.close()
	if error != OK: return failure("invalid_json")
	var envelope: Variant = parser.data
	if not envelope is Dictionary or envelope.size() != 4 or envelope.get("format") != FORMAT or envelope.get("version") != 1 or not envelope.get("metadata") is Dictionary or not envelope.get("payload") is Dictionary:
		return failure("invalid_envelope")
	var metadata: Dictionary = envelope.metadata
	if metadata.size() != 4 or metadata.get("id") != id or metadata.get("kind") not in ["session", "replay"] or not metadata.get("title") is String or not valid_title(metadata.title):
		return failure("invalid_metadata")
	var created: Variant = metadata.get("created")
	if not (created is int or created is float) or not is_finite(float(created)) or created < 0:
		return failure("invalid_metadata")
	return {"ok": true, "envelope": envelope}

func list_entries(kind: String = "") -> Dictionary:
	if kind not in ["", "session", "replay"]: return {"ok": false, "entries": [], "errors": [], "reason": "invalid_kind"}
	var ready := _ready_directory()
	if not ready.ok: return {"ok": false, "entries": [], "errors": [], "reason": ready.reason}
	var entries: Array = []
	var errors: Array = []
	if not ready.missing:
		var count := 0
		for filename in DirAccess.get_files_at(base_path):
			if filename.get_extension() != "json" or not valid_id(filename.get_basename()): continue
			count += 1
			if count > MAX_ENTRIES:
				errors.append({"reason": "entry_limit"})
				break
			var id := filename.get_basename()
			var result := _read(id)
			if not result.ok:
				errors.append({"id": id, "reason": result.reason})
				continue
			var metadata: Dictionary = result.envelope.metadata
			if kind.is_empty() or metadata.kind == kind: entries.append(metadata.duplicate())
	entries.sort_custom(func(a, b): return a.created > b.created if a.created != b.created else a.id < b.id)
	return {"ok": errors.is_empty(), "entries": entries, "errors": errors, "reason": "listed" if errors.is_empty() else "corrupt_entries"}

func save_session(title: String, runner: RefCounted, options: Dictionary, velocities: Dictionary = {}) -> Dictionary:
	if not valid_title(title): return failure("invalid_title")
	return _save_encoded("session", title, Session.encode(runner, options, velocities))

func save_replay(title: String, recorder: RefCounted, runner: RefCounted) -> Dictionary:
	if not valid_title(title): return failure("invalid_title")
	var encoded := Archive.encode(recorder, runner)
	if not encoded.ok: return encoded
	var verified := Archive.decode(encoded.payload)
	if not verified.ok: return verified
	return _save_encoded("replay", title, encoded)

func _save_encoded(kind: String, title: String, encoded: Dictionary) -> Dictionary:
	if not encoded.ok: return encoded
	var ready := _ready_directory(true)
	if not ready.ok: return ready
	var count := 0
	for filename in DirAccess.get_files_at(base_path):
		if filename.get_extension() == "json" and valid_id(filename.get_basename()): count += 1
	if count >= MAX_ENTRIES: return failure("entry_limit")
	var id := Crypto.new().generate_random_bytes(16).hex_encode()
	if not valid_id(id) or FileAccess.file_exists(_path(id)): return failure("id_collision")
	var metadata := {"id": id, "kind": kind, "title": title, "created": Time.get_unix_time_from_system()}
	return _write(id, {"format": FORMAT, "version": 1, "metadata": metadata, "payload": encoded.payload})

func _write(id: String, envelope: Dictionary) -> Dictionary:
	var path := _path(id)
	if not _safe_path(path): return failure("unsafe_path")
	var content := JSON.stringify(envelope, "", true, true)
	if content.to_utf8_buffer().size() > MAX_BYTES: return failure("file_too_large")
	var temporary := path + ".tmp-" + Crypto.new().generate_random_bytes(16).hex_encode()
	if not _safe_path(temporary) or FileAccess.file_exists(temporary): return failure("unsafe_path")
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return failure("write_failed")
	file.store_string(content)
	file.flush()
	var error := file.get_error()
	file.close()
	if error == OK and _safe_path(path): error = DirAccess.rename_absolute(temporary, path)
	else: error = ERR_FILE_CANT_WRITE
	if error != OK:
		DirAccess.remove_absolute(temporary)
		return failure("write_failed")
	return {"ok": true, "id": id, "metadata": envelope.metadata.duplicate()}

func load_entry(id: String) -> Dictionary:
	var result := _read(id)
	if not result.ok: return result
	var envelope: Dictionary = result.envelope
	var decoded: Dictionary = Session.decode(envelope.payload) if envelope.metadata.kind == "session" else Archive.decode(envelope.payload)
	if not decoded.ok: return decoded
	decoded["kind"] = envelope.metadata.kind
	decoded["id"] = id
	decoded["metadata"] = envelope.metadata.duplicate()
	return decoded

func rename_entry(id: String, title: String) -> Dictionary:
	if not valid_title(title): return failure("invalid_title")
	var result := _read(id)
	if not result.ok: return result
	result.envelope.metadata.title = title
	return _write(id, result.envelope)

func delete_entry(id: String) -> Dictionary:
	if not valid_id(id): return failure("invalid_id")
	if not _safe_path(_path(id)): return failure("unsafe_path")
	if not FileAccess.file_exists(_path(id)) or DirAccess.dir_exists_absolute(_path(id)): return failure("open_failed")
	if DirAccess.remove_absolute(_path(id)) != OK: return failure("delete_failed")
	return {"ok": true, "id": id}

func import_file(kind: String, path: String, title: String) -> Dictionary:
	if kind not in ["session", "replay"]: return failure("invalid_kind")
	if not valid_title(title): return failure("invalid_title")
	var loaded: Dictionary = Session.load(path) if kind == "session" else Archive.load_verified(path)
	if not loaded.ok: return loaded
	return save_session(title, loaded.runner, loaded.options, loaded.velocities) if kind == "session" else save_replay(title, loaded.recorder, loaded.runner)
