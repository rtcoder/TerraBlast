extends RefCounted
const Library = preload("res://scripts/core/storage/local_archive_library.gd")
var path := "user://library_preferences.json"
var favorites: Array = []
var filters := {"query":"","kind":"","sort":"newest","favorites_only":false}
var cursors := {}
func _init(file_path := "user://library_preferences.json") -> void: path = file_path
func load_from() -> bool:
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null: return false
	if file.get_length()>65536:
		file.close()
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary or parsed.get("version")!=1 or not parsed.get("favorites") is Array or not parsed.get("filters") is Dictionary or not parsed.get("cursors") is Dictionary: return false
	if parsed.favorites.size()>100 or parsed.cursors.size()>100: return false
	var unique := {}
	for id in parsed.favorites:
		if not id is String or not Library.valid_id(id) or unique.has(id): return false
		unique[id] = true
	var f: Dictionary = parsed.filters
	if f.size()!=4 or not f.get("query") is String or f.query.length()>100 or f.get("kind") not in ["","session","replay"] or f.get("sort") not in ["newest","oldest","title","kind"] or not f.get("favorites_only") is bool: return false
	for id in parsed.cursors:
		var row: Variant = parsed.cursors[id]
		if not Library.valid_id(id) or not row is Dictionary or row.size()!=2 or not row.get("fingerprint") is String or row.fingerprint.length()!=64 or not (row.get("index") is int or row.get("index") is float) or row.index!=floor(row.index) or row.index<0 or row.index>100000: return false
	favorites = parsed.favorites.duplicate()
	filters = f.duplicate()
	cursors = parsed.cursors.duplicate(true)
	return true
func save_to() -> Error:
	return Library._export_atomic(path,JSON.stringify({"version":1,"favorites":favorites,"filters":filters,"cursors":cursors}))
func toggle_favorite(id: String) -> bool:
	if not Library.valid_id(id): return false
	if favorites.has(id): favorites.erase(id)
	elif favorites.size()<100: favorites.append(id)
	else: return false
	return true
func remember(id: String, fingerprint: String, index: int) -> void:
	if not Library.valid_id(id) or fingerprint.length()!=64 or index<0 or index>100000: return
	if not cursors.has(id) and cursors.size()>=100: cursors.erase(cursors.keys()[0])
	cursors[id] = {"fingerprint":fingerprint,"index":index}
func cursor(id: String, fingerprint: String, count: int) -> int:
	var row: Dictionary = cursors.get(id,{})
	return int(row.index) if row.get("fingerprint")==fingerprint and row.get("index",-1)>=0 and row.get("index",-1)<=count else 0
