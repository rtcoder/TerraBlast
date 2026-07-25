class_name TomlMapParser
extends RefCounted

static func parse(text: String) -> Dictionary:
	var result := {}
	var current_array_name := ""
	var current_item: Dictionary = {}

	for raw_line in text.split("\n"):
		var line := _strip_comment(raw_line).strip_edges()
		if line.is_empty():
			continue

		if line.begins_with("[[") and line.ends_with("]]"):
			current_array_name = line.substr(2, line.length() - 4).strip_edges()
			if not result.has(current_array_name):
				result[current_array_name] = []
			current_item = {}
			result[current_array_name].append(current_item)
			continue

		var separator := line.find("=")
		if separator < 0:
			continue

		var key := line.substr(0, separator).strip_edges()
		var value: Variant = _parse_value(line.substr(separator + 1).strip_edges())
		if current_array_name.is_empty():
			result[key] = value
		else:
			current_item[key] = value

	return result

static func _strip_comment(line: String) -> String:
	var in_string := false
	for index in range(line.length()):
		var character := line[index]
		if character == "\"":
			in_string = not in_string
		elif character == "#" and not in_string:
			return line.substr(0, index)
	return line

static func _parse_value(value: String) -> Variant:
	if value.begins_with("\"") and value.ends_with("\""):
		return value.substr(1, value.length() - 2)
	if value.begins_with("[") and value.ends_with("]"):
		return _parse_array(value.substr(1, value.length() - 2))
	if value == "true":
		return true
	if value == "false":
		return false
	if value.contains("."):
		return value.to_float()
	return value.to_int()

static func _parse_array(value: String) -> Array:
	var parsed: Array = []
	for item in value.split(","):
		parsed.append(_parse_value(item.strip_edges()))
	return parsed
