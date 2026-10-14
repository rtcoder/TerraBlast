extends RefCounted
## Client-only preferences. Never shared with authoritative simulation.
var volume := 0.8
var muted := false
var sensitivity := 1.0
var invert_y := false
var fullscreen := false
const PATH := "user://preferences.cfg"
func update(values: Dictionary) -> void:
	for field in ["volume", "sensitivity"]:
		var value: Variant = values.get(field)
		if (value is float or value is int) and is_finite(float(value)):
			set(field, clampf(float(value), 0.0 if field == "volume" else 0.1, 1.0 if field == "volume" else 3.0))
	for field in ["muted", "invert_y", "fullscreen"]:
		if values.get(field) is bool:
			set(field, values[field])
func save_to(path: String = PATH) -> Error:
	var config := ConfigFile.new()
	for field in ["volume", "muted", "sensitivity", "invert_y", "fullscreen"]:
		config.set_value("client", field, get(field))
	return config.save(path)
func load_from(path: String = PATH) -> void:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return
	var values := {}
	for field in ["volume", "muted", "sensitivity", "invert_y", "fullscreen"]:
		values[field] = config.get_value("client", field, get(field))
	update(values)
func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(0, muted or volume <= 0)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
