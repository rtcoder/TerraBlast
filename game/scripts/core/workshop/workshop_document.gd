extends RefCounted
## Local editable map. Committed transactions own their snapshots; callers only get copies.
const Definition = preload("res://scripts/core/maps/map_definition.gd")
const Serializer = preload("res://scripts/core/maps/map_serializer.gd")
const Validator = preload("res://scripts/core/maps/map_validator.gd")
const Generator = preload("res://scripts/core/maps/arena_generator.gd")
const Selector = preload("res://scripts/core/maps/spawn_selector.gd")
const HISTORY_LIMIT := 32
const KINDS := ["boxes","carves","spawns"]
var _definition: RefCounted
var revision := 0
var selection := {"kind":"boxes","index":-1}
var source_path := ""
var _saved := ""
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var _validation := {}
func _init() -> void: new_document()
func new_document() -> Dictionary:
	var candidate = Definition.new()
	candidate.id = "local_arena"
	candidate.display_name = "Local Arena"
	candidate.size = Vector3i(32,12,32)
	candidate.theme = "workshop"
	candidate.boxes.append({"position":[0,0,0],"size":[32,1,32],"material":"dirt","name":"Ground"})
	candidate.spawns.append({"position":[3,1,3],"team":1,"slot":0,"yaw":45})
	candidate.spawns.append({"position":[28,1,28],"team":2,"slot":0,"yaw":225})
	return replace_definition(candidate)
func replace_definition(candidate: RefCounted, path := "") -> Dictionary:
	if candidate == null: return _error("Missing map definition")
	_definition = candidate.copy()
	source_path = path
	selection = {"kind":"boxes","index":0 if not _definition.boxes.is_empty() else -1}
	_undo.clear()
	_redo.clear()
	_changed()
	_saved = _content()
	return {"ok":true,"reason":""}
func snapshot() -> RefCounted: return _definition.copy()
func _content() -> String: return JSON.stringify(Serializer.to_dictionary(_definition),"",true)
func is_dirty() -> bool: return _saved != _content()
func mark_saved(path: String) -> void:
	source_path = path
	_saved = _content()
func select(kind: String, index: int) -> void:
	if kind not in KINDS: return
	var entries: Array = _definition.get(kind)
	selection = {"kind":kind,"index":clampi(index,0,entries.size()-1) if not entries.is_empty() else -1}
func _state() -> Dictionary: return {"definition":snapshot(),"selection":selection.duplicate()}
func _restore(state: Dictionary) -> void:
	_definition = state.definition.copy()
	selection = state.selection.duplicate()
	select(selection.kind,selection.index)
	_changed()
func _changed() -> void:
	revision += 1
	_validation = {}
func _commit(candidate: RefCounted, kind := "", index := -1) -> Dictionary:
	if Serializer.to_dictionary(candidate) == Serializer.to_dictionary(_definition): return {"ok":true,"reason":"","changed":false}
	_undo.append(_state())
	if _undo.size() > HISTORY_LIMIT: _undo.pop_front()
	_redo.clear()
	_definition = candidate.copy()
	if not kind.is_empty(): select(kind,index)
	_changed()
	return {"ok":true,"reason":"","changed":true}
func can_undo() -> bool: return not _undo.is_empty()
func can_redo() -> bool: return not _redo.is_empty()
func undo() -> bool:
	if not can_undo(): return false
	_redo.append(_state())
	_restore(_undo.pop_back())
	return true
func redo() -> bool:
	if not can_redo(): return false
	_undo.append(_state())
	_restore(_redo.pop_back())
	return true
func history_summary() -> Dictionary: return {"undo":_undo.size(),"redo":_redo.size()}
func set_metadata(patch: Dictionary) -> Dictionary:
	var candidate := snapshot()
	for key in patch:
		if key not in ["id","name","theme","size"]: return _error("Unknown metadata field: " + str(key))
		if key == "size":
			if not patch[key] is Vector3i: return _error("Dimensions must be integer voxels")
			var extent: Vector3i = patch[key]
			if extent.x <= 0 or extent.y <= 0 or extent.z <= 0 or extent.x > 256 or extent.y > 128 or extent.z > 256 or extent.x*extent.y*extent.z > Validator.MAX_VOLUME: return _error("Dimensions exceed map limits")
			candidate.size = extent
		else:
			if not patch[key] is String: return _error("Metadata must be text")
			var text: String = patch[key]
			if key == "id":
				if text.is_empty() or text.length() > 64: return _error("ID must contain 1–64 characters")
				for character in text:
					if character not in "abcdefghijklmnopqrstuvwxyz0123456789_": return _error("ID uses lowercase letters, digits and underscore")
			else:
				if text.length() > (128 if key == "name" else 64) or (key == "name" and text.strip_edges().is_empty()): return _error("Text length invalid")
				for character in text:
					var code := character.unicode_at(0)
					if code < 32 or (code >= 127 and code <= 159): return _error("Text contains control character")
			candidate.set("display_name" if key == "name" else key,text)
	return _commit(candidate)
func _valid_index(kind: String, index: int) -> bool: return kind in KINDS and index >= 0 and index < _definition.get(kind).size()
func _entry_error(kind: String, entry: Dictionary) -> String:
	var allowed := {"boxes":["position","size","material","health","name"],"carves":["position","shape","radius"],"spawns":["position","team","slot","yaw"]}
	for key in entry:
		if key not in allowed[kind]: return "Unknown entry field: " + str(key)
	if not preload("res://scripts/core/maps/map_loader.gd")._is_vector(entry.get("position")): return "Position requires three integers"
	if kind == "spawns":
		if not entry.get("team") is int or entry.team not in [1,2]: return "Team must be 1 or 2"
		if not entry.get("slot",0) is int or entry.get("slot",0) < 0: return "Slot must be nonnegative integer"
		var yaw: Variant = entry.get("yaw",0)
		if not (yaw is int or yaw is float) or not is_finite(float(yaw)): return "Yaw must be finite"
		return ""
	var probe := snapshot()
	probe.boxes.clear()
	probe.carves.clear()
	probe.spawns.assign([{"position":[0,1,0],"team":1,"slot":0}])
	probe.get(kind).append(entry.duplicate(true))
	var errors := Validator.validate_definition(probe)
	return "; ".join(errors)
func add_entry(kind: String, entry: Dictionary) -> Dictionary:
	if kind not in KINDS: return _error("Unknown collection")
	var error := _entry_error(kind,entry)
	if not error.is_empty(): return _error(error)
	var candidate := snapshot()
	if (kind == "spawns" and candidate.spawns.size() >= Validator.MAX_SPAWNS) or (kind != "spawns" and candidate.boxes.size()+candidate.carves.size() >= Validator.MAX_OPERATIONS): return _error("Collection limit reached")
	candidate.get(kind).append(entry.duplicate(true))
	return _commit(candidate,kind,candidate.get(kind).size()-1)
func update_entry(kind: String, index: int, patch: Dictionary) -> Dictionary:
	if not _valid_index(kind,index): return _error("Select an entry first")
	var candidate := snapshot()
	var entry: Dictionary = candidate.get(kind)[index]
	for key in patch:
		if key == "health" and patch[key] == null: entry.erase(key)
		else: entry[key] = patch[key].duplicate(true) if patch[key] is Array or patch[key] is Dictionary else patch[key]
	if kind == "boxes" and entry.get("material") == "air" and entry.has("health"): entry.health = 0
	var error := _entry_error(kind,entry)
	if not error.is_empty(): return _error(error)
	return _commit(candidate,kind,index)
func duplicate_entry(kind: String, index: int) -> Dictionary:
	if not _valid_index(kind,index): return _error("Select an entry first")
	var candidate := snapshot()
	if (kind == "spawns" and candidate.spawns.size() >= Validator.MAX_SPAWNS) or (kind != "spawns" and candidate.boxes.size()+candidate.carves.size() >= Validator.MAX_OPERATIONS): return _error("Collection limit reached")
	candidate.get(kind).insert(index+1,candidate.get(kind)[index].duplicate(true))
	return _commit(candidate,kind,index+1)
func remove_entry(kind: String, index: int) -> Dictionary:
	if not _valid_index(kind,index): return _error("Select an entry first")
	var candidate := snapshot()
	candidate.get(kind).remove_at(index)
	return _commit(candidate,kind,index)
func move_entry(kind: String, index: int, delta: int) -> Dictionary:
	if not _valid_index(kind,index) or delta not in [-1,1] or not _valid_index(kind,index+delta): return _error("Cannot move beyond list bounds")
	var candidate := snapshot()
	var entries: Array = candidate.get(kind)
	var entry: Dictionary = entries[index]
	entries.remove_at(index)
	entries.insert(index+delta,entry)
	return _commit(candidate,kind,index+delta)
func validate() -> Dictionary:
	if not _validation.is_empty(): return _validation
	var arena := Generator.from_definition(snapshot())
	var counts: Array[int] = []
	if arena.errors.is_empty():
		for count in range(2,11):
			if Selector.select(arena.spawns,count).ok: counts.append(count)
	_validation = {"ok":arena.errors.is_empty(),"errors":arena.errors.duplicate(),"supported_counts":counts,"arena":arena,"revision":revision}
	return _validation
func _error(reason: String) -> Dictionary: return {"ok":false,"reason":reason}
