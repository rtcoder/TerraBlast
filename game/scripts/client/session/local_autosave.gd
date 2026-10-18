extends RefCounted
const Store = preload("res://scripts/core/replay/session_store.gd")
var base_path: String
var sequence := {}
var counter := 0
func _init(path := "user://autosaves"):
	base_path = path
	var cfg := ConfigFile.new()
	if cfg.load(base_path.path_join("rotation.cfg")) == OK:
		var value: Variant = cfg.get_value("rotation","sequence",{})
		if value is Dictionary:
			for key in ["slot0.json","slot1.json","slot2.json"]:
				var serial: Variant = value.get(key,0)
				if serial is int and serial >= 0 and serial < 1000000000:
					sequence[key] = serial
					counter = maxi(counter,serial)
func slot_paths() -> Array:
	return [base_path.path_join("slot0.json"),base_path.path_join("slot1.json"),base_path.path_join("slot2.json")]
func save(runner: RefCounted, options: Dictionary, velocities: Dictionary) -> Dictionary:
	var error := DirAccess.make_dir_recursive_absolute(base_path)
	if error != OK: return {"ok":false,"reason":error_string(error)}
	var paths := slot_paths()
	var selected: String = paths[0]
	for path in paths:
		if not FileAccess.file_exists(path):
			selected = path
			break
		if int(sequence.get(path.get_file(),0)) < int(sequence.get(selected.get_file(),0)): selected = path
	error = Store.save(selected,runner,options,velocities)
	if error == OK:
		counter += 1
		sequence[selected.get_file()] = counter
		var cfg := ConfigFile.new()
		cfg.set_value("rotation","sequence",sequence)
		var target := base_path.path_join("rotation.cfg")
		var temp := target + ".%s.%s.tmp" % [OS.get_process_id(),Time.get_ticks_usec()]
		error = cfg.save(temp)
		if error == OK: error = DirAccess.rename_absolute(temp,target)
		if error != OK: DirAccess.remove_absolute(temp)
	return {"ok":error == OK,"reason":error_string(error)}
func latest_valid() -> Dictionary:
	var paths := slot_paths().filter(func(p): return FileAccess.file_exists(p))
	paths.sort_custom(func(a,b):
		var left: int = sequence.get(a.get_file(),0)
		var right: int = sequence.get(b.get_file(),0)
		return left > right if left != right else FileAccess.get_modified_time(a) > FileAccess.get_modified_time(b))
	var skipped := 0
	for path in paths:
		var result: Dictionary = Store.load(path)
		if result.ok:
			result["skipped"] = skipped
			return result
		skipped += 1
	return {"ok":false,"reason":"No valid autosave (%s damaged slots)" % skipped}
