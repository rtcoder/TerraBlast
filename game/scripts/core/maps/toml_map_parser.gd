class_name TomlMapParser
extends RefCounted

const SCHEMA := {"": ["id", "name", "size", "theme"], "spawns": ["position", "team", "slot", "yaw"], "boxes": ["position", "size", "material", "health", "name"], "carves": ["position", "shape", "radius"]}

static func parse(text: String) -> Dictionary:
	var result := {"_errors": []}
	var section := ""
	var current: Dictionary = result
	var line_number := 0
	for raw_line in text.split("\n"):
		line_number += 1
		var line := _strip_comment(raw_line).strip_edges()
		if line.is_empty(): continue
		var context := "Line %d [%s]: " % [line_number, section if not section.is_empty() else "root"]
		if line.begins_with("["):
			if not line.begins_with("[[") or not line.ends_with("]]"):
				result._errors.append(context + "Invalid table header")
				continue
			section = line.substr(2, line.length() - 4).strip_edges()
			if section.is_empty() or not SCHEMA.has(section):
				result._errors.append(context + "Unknown table: " + section)
				current = {}
				continue
			if not result.has(section): result[section] = []
			current = {}
			result[section].append(current)
			continue
		var separator := line.find("=")
		if separator < 0:
			result._errors.append(context + "Expected key = value")
			continue
		var key := line.substr(0, separator).strip_edges()
		if key not in SCHEMA.get(section, []):
			result._errors.append(context + "Unknown key: " + key)
			continue
		if current.has(key):
			result._errors.append(context + "Duplicate key: " + key)
			continue
		var value: Variant = _parse_value(line.substr(separator + 1).strip_edges())
		if value == null:
			result._errors.append(context + "Invalid value: " + key)
			continue
		current[key] = value
	return result

static func _strip_comment(line: String) -> String:
	var quoted := false
	var escaped := false
	for index in range(line.length()):
		var character := line[index]
		if quoted and escaped:
			escaped = false
		elif quoted and character == "\\":
			escaped = true
		elif character == "\"":
			quoted = not quoted
		elif character == "#" and not quoted:
			return line.substr(0, index)
	return line

static func _parse_value(value: String) -> Variant:
	if value.begins_with("\""):
		# JSON basic strings implement our documented escaped-string subset.
		var parser := JSON.new()
		if parser.parse(value) == OK and parser.data is String: return parser.data
		return null
	if value.begins_with("["):
		if not value.ends_with("]"): return null
		return _parse_array(value.substr(1, value.length() - 2))
	if value == "true": return true
	if value == "false": return false
	if value.is_valid_int(): return value.to_int()
	if value.is_valid_float():
		var number := value.to_float()
		return number if is_finite(number) else null
	return null

static func _parse_array(value: String) -> Variant:
	var parsed: Array = []
	if value.strip_edges().is_empty(): return parsed
	# Map arrays contain only numeric coordinates; no nested/string array grammar.
	for item in value.split(","):
		var token := item.strip_edges()
		if not token.is_valid_int(): return null
		parsed.append(token.to_int())
	return parsed
