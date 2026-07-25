class_name MapLoader
extends RefCounted

const MapDefinitionScript := preload("res://scripts/core/maps/map_definition.gd")
const TomlMapParserScript := preload("res://scripts/core/maps/toml_map_parser.gd")

static func load_from_file(path: String) -> RefCounted:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open map file: %s" % path)
		return MapDefinitionScript.new()

	var data: Dictionary = TomlMapParserScript.parse(file.get_as_text())
	return from_dictionary(data)

static func from_dictionary(data: Dictionary) -> RefCounted:
	var definition: RefCounted = MapDefinitionScript.new()
	definition.id = str(data.get("id", ""))
	definition.display_name = str(data.get("name", definition.id))
	definition.size = _vector3i_from_array(data.get("size", [96, 24, 96]))
	definition.theme = str(data.get("theme", ""))
	definition.spawns = _array_of_dictionaries(data.get("spawns", []))
	definition.boxes = _array_of_dictionaries(data.get("boxes", []))
	definition.carves = _array_of_dictionaries(data.get("carves", []))
	return definition

static func _vector3i_from_array(value: Variant) -> Vector3i:
	if not value is Array or value.size() != 3:
		return Vector3i.ZERO
	return Vector3i(int(value[0]), int(value[1]), int(value[2]))

static func _array_of_dictionaries(value: Variant) -> Array[Dictionary]:
	var dictionaries: Array[Dictionary] = []
	if not value is Array:
		return dictionaries
	for item in value:
		if item is Dictionary:
			dictionaries.append(item)
	return dictionaries

