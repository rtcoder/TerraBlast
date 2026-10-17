extends RefCounted
## Physical desktop keys, independent of project InputMap and gameplay state.
const DEFAULT_PATH := "user://bindings.cfg"
const DEFAULTS := {
	"move_left": KEY_A, "move_right": KEY_D, "move_forward": KEY_W, "move_back": KEY_S,
	"jump": KEY_SPACE, "weapon_1": KEY_1, "weapon_2": KEY_2, "weapon_3": KEY_3,
	"restart": KEY_R, "scoreboard": KEY_TAB, "pause": KEY_P,
}
var _keys: Dictionary = DEFAULTS.duplicate()

func key_for(action: String) -> int:
	return int(_keys.get(action, 0))

func label(action: String) -> String:
	return OS.get_keycode_string(key_for(action))

static func event_key(event: InputEventKey) -> int:
	return event.physical_keycode if event.physical_keycode != 0 else event.keycode

func matches(action: String, event: InputEventKey) -> bool:
	return key_for(action) != 0 and event_key(event) == key_for(action)

static func _safe_key(key: int) -> bool:
	return (key >= KEY_A and key <= KEY_Z) or (key >= KEY_0 and key <= KEY_9) or key in [KEY_SPACE, KEY_TAB, KEY_ENTER, KEY_BACKSPACE, KEY_INSERT, KEY_DELETE, KEY_HOME, KEY_END, KEY_PAGEUP, KEY_PAGEDOWN, KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_COMMA, KEY_PERIOD, KEY_SLASH, KEY_BACKSLASH, KEY_SEMICOLON, KEY_APOSTROPHE, KEY_MINUS, KEY_EQUAL, KEY_QUOTELEFT]

func rebind(action: String, key: int) -> Dictionary:
	if not DEFAULTS.has(action):
		return {"ok": false, "error": "Unknown action"}
	if not _safe_key(key):
		return {"ok": false, "error": "Reserved or unsupported key"}
	for other in _keys:
		if other != action and _keys[other] == key:
			return {"ok": false, "error": "Key already assigned to " + other}
	_keys[action] = key
	return {"ok": true, "error": ""}

func reset_defaults() -> void:
	_keys = DEFAULTS.duplicate()

func load_settings(path: String = DEFAULT_PATH) -> Error:
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	if file.get_length() > 16384:
		return ERR_FILE_CORRUPT
	file.close()
	var config := ConfigFile.new()
	var result := config.load(path)
	if result != OK:
		return result
	if config.get_sections().size() != 2 or not config.has_section("meta") or not config.has_section("bindings"):
		return ERR_FILE_CORRUPT
	var version: Variant = config.get_value("meta", "version", -1)
	if typeof(version) != TYPE_INT or version != 1 or config.get_section_keys("meta").size() != 1:
		return ERR_FILE_CORRUPT
	if config.get_section_keys("bindings").size() != DEFAULTS.size():
		return ERR_FILE_CORRUPT
	var candidate := {}
	var used := {}
	for action in DEFAULTS:
		var key: Variant = config.get_value("bindings", action, -1)
		if typeof(key) != TYPE_INT or not _safe_key(key) or used.has(key):
			return ERR_FILE_CORRUPT
		candidate[action] = key
		used[key] = true
	_keys = candidate
	return OK

func save_settings(path: String = DEFAULT_PATH) -> Error:
	var config := ConfigFile.new()
	config.set_value("meta", "version", 1)
	for action in _keys:
		config.set_value("bindings", action, _keys[action])
	var temporary := "%s.%s.%s.tmp" % [path, OS.get_process_id(), Time.get_ticks_usec()]
	var result := config.save(temporary)
	if result != OK:
		return result
	result = DirAccess.rename_absolute(temporary, path)
	if result != OK:
		DirAccess.remove_absolute(temporary)
	return result
