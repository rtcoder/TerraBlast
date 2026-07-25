class_name MapValidator
extends RefCounted

static func validate(definition: RefCounted, world: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	if definition.id.is_empty():
		errors.append("Map id is required")
	if definition.spawns.is_empty():
		errors.append("Map must define at least one spawn")

	for index in range(definition.spawns.size()):
		_validate_spawn(definition.spawns[index], index, world, errors)

	return errors

static func _validate_spawn(spawn: Dictionary, index: int, world: RefCounted, errors: Array[String]) -> void:
	var position := _vector3i_from_array(spawn.get("position", [0, 0, 0]))
	if not world.is_in_bounds(position):
		errors.append("Spawn %d is outside map bounds" % index)
		return
	if world.get_material_id(position) != 0:
		errors.append("Spawn %d is inside solid voxel" % index)
	if position.y <= 0 or world.get_material_id(position + Vector3i.DOWN) == 0:
		errors.append("Spawn %d is not standing on solid ground" % index)

static func _vector3i_from_array(value: Variant) -> Vector3i:
	if not value is Array or value.size() != 3:
		return Vector3i.ZERO
	return Vector3i(int(value[0]), int(value[1]), int(value[2]))

