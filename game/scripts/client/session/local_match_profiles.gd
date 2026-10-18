extends RefCounted
const DEFAULT_PATH := "user://local_match_profiles.cfg"
const Registry = preload("res://scripts/core/maps/map_registry.gd")
var profiles := {}
var last_config := {}
func templates() -> Dictionary:
	var base := {"map":"two_islands", "count":2, "preset":"classic", "mode":"hotseat", "difficulty":"normal", "human_team":1}
	var easy := base.duplicate()
	easy.mode = "solo"
	easy.difficulty = "easy"
	var normal := easy.duplicate()
	normal.difficulty = "normal"
	return {"hotseat":base,"solo_easy":easy,"solo_normal":normal}
func validate(config: Variant) -> Dictionary:
	if not config is Dictionary or config.size() != 6:
		return {"ok":false,"reason":"Invalid configuration"}
	if not config.get("map") is String or not GameConfig.MAPS.has(config.map) or config.get("preset") not in ["classic","quick","training"] or config.get("mode") not in ["hotseat","solo"] or config.get("difficulty") not in ["easy","normal"] or not config.get("human_team") is int or config.get("human_team") not in [1,2]:
		return {"ok":false,"reason":"Unknown configuration option"}
	var capacity: int = Registry.describe(config.map).get("player_capacity",10)
	if not config.get("count") is int or config.count < 2 or config.count > mini(10,capacity):
		return {"ok":false,"reason":"Player count exceeds arena capacity"}
	return {"ok":true,"config":config.duplicate()}
func set_last(config: Dictionary) -> Dictionary:
	var result := validate(config)
	if result.ok: last_config = result.config
	return result
func put_profile(title: String, config: Dictionary) -> Dictionary:
	if title.strip_edges().is_empty() or title.length() > 48:
		return {"ok":false,"reason":"Name must contain 1–48 printable characters"}
	for value in title.to_utf8_buffer():
		if value < 32 or value == 127: return {"ok":false,"reason":"Control character in name"}
	if not profiles.has(title) and profiles.size() >= 12:
		return {"ok":false,"reason":"Maximum 12 profiles"}
	var result := validate(config)
	if result.ok: profiles[title] = result.config
	return result
func remove_profile(title: String) -> Dictionary:
	return {"ok":profiles.erase(title)}
func save_to(path: String = DEFAULT_PATH) -> Error:
	var config := ConfigFile.new()
	config.set_value("profiles","version",1)
	config.set_value("profiles","entries",profiles)
	config.set_value("profiles","last",last_config)
	var temp := path + ".%s.%s.tmp" % [OS.get_process_id(),Time.get_ticks_usec()]
	var error := config.save(temp)
	if error == OK: error = DirAccess.rename_absolute(temp,path)
	if error != OK: DirAccess.remove_absolute(temp)
	return error
func load_from(path: String = DEFAULT_PATH) -> Error:
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null: return ERR_FILE_NOT_FOUND
	if file.get_length() > 65536: return ERR_FILE_CORRUPT
	file.close()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK or cfg.get_value("profiles","version",0) != 1: return ERR_FILE_CORRUPT
	var entries: Variant = cfg.get_value("profiles","entries",{})
	var last: Variant = cfg.get_value("profiles","last",{})
	if not entries is Dictionary or entries.size() > 12 or not last is Dictionary: return ERR_FILE_CORRUPT
	var candidate = get_script().new()
	for title in entries:
		if not title is String or not candidate.put_profile(title,entries[title]).ok: return ERR_FILE_CORRUPT
	if not last.is_empty() and not candidate.set_last(last).ok: return ERR_FILE_CORRUPT
	profiles = candidate.profiles
	last_config = candidate.last_config
	return OK
