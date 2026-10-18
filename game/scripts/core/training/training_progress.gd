extends RefCounted
const Lessons = preload("res://scripts/core/training/training_lessons.gd")
const PATH := "user://training_progress.cfg"
var completed := {}
func complete(id: String) -> bool:
	if not Lessons.LESSONS.has(id): return false
	completed[id] = true
	return true
func is_complete(id: String) -> bool: return completed.has(id)
func reset() -> void: completed.clear()
func save_to(path := PATH) -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("progress","version",1)
	cfg.set_value("progress","completed",completed.keys())
	var temp := path + ".%s.%s.tmp" % [OS.get_process_id(),Time.get_ticks_usec()]
	var error := cfg.save(temp)
	if error == OK: error = DirAccess.rename_absolute(temp,path)
	if error != OK: DirAccess.remove_absolute(temp)
	return error
func load_from(path := PATH) -> Error:
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null: return ERR_FILE_NOT_FOUND
	if file.get_length() > 16384: return ERR_FILE_CORRUPT
	file.close()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK or cfg.get_value("progress","version",0) != 1: return ERR_FILE_CORRUPT
	var ids: Variant = cfg.get_value("progress","completed",[])
	if not ids is Array or ids.size() > Lessons.LESSONS.size(): return ERR_FILE_CORRUPT
	var candidate := {}
	for id in ids:
		if not id is String or not Lessons.LESSONS.has(id) or candidate.has(id): return ERR_FILE_CORRUPT
		candidate[id] = true
	completed = candidate
	return OK
