extends RefCounted
## Versioned sidecar; replay archives and their authority remain unchanged.
const MAX_ROWS := 200
const MAX_BYTES := 2*1024*1024
const CATEGORIES := ["note","hit","mistake","highlight"]
var _fingerprint := ""
var _count := 0
var _rows: Array[Dictionary] = []
static func failure(reason: String) -> Dictionary: return {"ok":false,"reason":reason}
static func hex_string(value: Variant, length: int) -> bool:
	if not value is String or value.length() != length: return false
	for character in value:
		if character not in "0123456789abcdef": return false
	return true
static func integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= low and value <= high and float(value) == floorf(float(value))
static func text_valid(value: Variant, limit: int, multiline := false, required := false) -> bool:
	if not value is String or value.length() > limit or (required and value.strip_edges().is_empty()): return false
	for character in value:
		var code: int = character.unicode_at(0)
		if (code < 32 and not (multiline and code in [9,10,13])) or (code >= 127 and code <= 159): return false
	return true
static func fingerprint(recorder: RefCounted) -> String: return JSON.stringify(recorder.data,"",true,true).sha256_text()
func bind(value: String, count: Variant) -> Dictionary:
	if not hex_string(value,64) or not integer(count,0,100000): return failure("invalid_binding")
	_fingerprint = value
	_count = int(count)
	_rows.clear()
	return {"ok":true}
func _valid_row(row: Variant) -> bool:
	return row is Dictionary and row.size() == 5 and hex_string(row.get("id"),32) and integer(row.get("index"),0,_count) and text_valid(row.get("title"),80,false,true) and text_valid(row.get("body"),2000,true) and row.get("category") in CATEGORIES
func add(index: Variant, title: String, body: String, category: String) -> Dictionary:
	if _fingerprint.is_empty() or _rows.size() >= MAX_ROWS: return failure("not_bound_or_note_limit")
	var row := {"id":Crypto.new().generate_random_bytes(16).hex_encode(),"index":index,"title":title,"body":body,"category":category}
	if not _valid_row(row): return failure("invalid_note")
	row.index = int(index)
	_rows.append(row)
	return {"ok":true,"id":row.id}
func edit(id: String, patch: Dictionary) -> Dictionary:
	for index in _rows.size():
		if _rows[index].id != id: continue
		var row := _rows[index].duplicate(true)
		for key in patch:
			if key not in ["title","body","category"]: return failure("unsupported_note_field")
			row[key] = patch[key]
		if not _valid_row(row): return failure("invalid_note")
		_rows[index] = row
		return {"ok":true,"id":id}
	return failure("note_not_found")
func remove(id: String) -> Dictionary:
	for index in _rows.size():
		if _rows[index].id == id:
			_rows.remove_at(index)
			return {"ok":true,"id":id}
	return failure("note_not_found")
func list(query := "", category := "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row in _rows:
		if not category.is_empty() and row.category != category: continue
		if not query.is_empty() and not (row.title+"\n"+row.body).to_lower().contains(query.to_lower()): continue
		result.append(row.duplicate(true))
	result.sort_custom(func(a,b): return a.index < b.index if a.index != b.index else a.id < b.id)
	return result
func encode() -> Dictionary: return {"version":1,"fingerprint":_fingerprint,"action_count":_count,"rows":list()}
func decode(payload: Variant, value: String, count: Variant) -> Dictionary:
	if not integer(count,0,100000) or not payload is Dictionary or payload.size() != 4 or payload.get("version") != 1 or payload.get("fingerprint") != value or not hex_string(value,64) or not integer(payload.get("action_count"),0,100000) or int(payload.action_count) != count or not payload.get("rows") is Array or payload.rows.size() > MAX_ROWS: return failure("invalid_or_stale_notebook")
	var candidate = get_script().new()
	candidate.bind(value,count)
	var ids := {}
	for row in payload.rows:
		if not candidate._valid_row(row) or ids.has(row.id): return failure("invalid_or_duplicate_note")
		ids[row.id] = true
		var normalized: Dictionary = row.duplicate(true)
		normalized.index = int(row.index)
		candidate._rows.append(normalized)
	_fingerprint = value
	_count = int(count)
	_rows = candidate._rows.duplicate(true)
	return {"ok":true}
func merge(payload: Variant) -> Dictionary:
	var candidate = get_script().new()
	var decoded: Dictionary = candidate.decode(payload,_fingerprint,_count)
	if not decoded.ok: return decoded
	var combined := {}
	for row in _rows: combined[row.id] = row.duplicate(true)
	for row in candidate._rows:
		if combined.has(row.id) and combined[row.id] != row: return failure("note_id_conflict")
		combined[row.id] = row.duplicate(true)
	if combined.size() > MAX_ROWS: return failure("note_limit")
	_rows.assign(combined.values())
	return {"ok":true}
static func safe_path(path: String) -> bool:
	if not path.is_absolute_path(): return false
	var current := path
	while current != "/" and not current.is_empty():
		var parent := current.get_base_dir()
		var directory := DirAccess.open(parent)
		if directory != null and directory.is_link(current.get_file()): return false
		if current == parent: break
		current = parent
	return true
static func atomic_write(path: String, content: String, replace := false, protected_paths: Array = []) -> Dictionary:
	var absolute := ProjectSettings.globalize_path(path).simplify_path()
	if not safe_path(absolute) or path.begins_with("res://"): return failure("unsafe_output")
	for source in protected_paths:
		if absolute == ProjectSettings.globalize_path(str(source)).simplify_path(): return failure("protected_source")
	if FileAccess.file_exists(absolute) and not replace: return failure("output_exists")
	var temporary := absolute + ".tmp-" + Crypto.new().generate_random_bytes(16).hex_encode()
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file == null: return failure("write_failed")
	file.store_string(content)
	file.flush()
	var error := file.get_error()
	file.close()
	if error == OK and safe_path(absolute): error = DirAccess.rename_absolute(temporary,absolute)
	else: error = ERR_FILE_CANT_WRITE
	if error != OK: DirAccess.remove_absolute(temporary); return failure("write_failed")
	return {"ok":true,"path":path}
func save_to(path: String, replace := true) -> Dictionary:
	if not hex_string(_fingerprint,64): return failure("not_bound")
	var content := JSON.stringify(encode(),"",true,true)
	if content.to_utf8_buffer().size() > MAX_BYTES: return failure("notebook_size_limit")
	return atomic_write(path,content,replace)
func load_from(path: String) -> Dictionary:
	var absolute := ProjectSettings.globalize_path(path).simplify_path()
	if not safe_path(absolute): return failure("unsafe_path")
	var file := FileAccess.open(absolute,FileAccess.READ)
	if file == null: return failure("open_failed")
	if file.get_length() == 0 or file.get_length() > MAX_BYTES: file.close(); return failure("notebook_size_limit")
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	file.close()
	if error != OK: return failure("invalid_json")
	return decode(parser.data,_fingerprint,_count)
