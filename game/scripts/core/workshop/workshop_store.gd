extends RefCounted
const Loader = preload("res://scripts/core/maps/map_loader.gd")
const Serializer = preload("res://scripts/core/maps/map_serializer.gd")
const Validator = preload("res://scripts/core/maps/map_validator.gd")
func load_document(path: String) -> Dictionary:
	var definition := Loader.load_from_file(path)
	var errors := Validator.validate_definition(definition)
	if not errors.is_empty(): return {"ok":false,"reason":"; ".join(errors)}
	return {"ok":true,"definition":definition,"reason":""}
func save_document(path: String, definition: RefCounted) -> Dictionary:
	if path.begins_with("res://") or path.get_extension().to_lower() != "toml": return {"ok":false,"reason":"Choose a local .toml file; shipped maps are read-only"}
	var absolute := ProjectSettings.globalize_path(path).simplify_path()
	var project_root := ProjectSettings.globalize_path("res://").simplify_path().trim_suffix("/")
	if not absolute.is_absolute_path() or absolute == project_root or absolute.begins_with(project_root + "/"): return {"ok":false,"reason":"Choose a file outside the game project"}
	var serialized := Serializer.to_toml(definition)
	if not serialized.ok: return serialized
	var temporary := absolute + ".tmp"
	if FileAccess.file_exists(temporary) or DirAccess.dir_exists_absolute(temporary): return {"ok":false,"reason":"Temporary path already exists; no file was replaced"}
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file == null: return {"ok":false,"reason":"Cannot write file: " + error_string(FileAccess.get_open_error())}
	file.store_string(serialized.text)
	file.flush()
	var error := file.get_error()
	file.close()
	if error == OK: error = DirAccess.rename_absolute(temporary,absolute)
	if error != OK:
		DirAccess.remove_absolute(temporary)
		return {"ok":false,"reason":"Save failed: " + error_string(error)}
	return {"ok":true,"reason":"","path":path}
