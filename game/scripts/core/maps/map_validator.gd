class_name MapValidator
extends RefCounted

const Loader := preload("res://scripts/core/maps/map_loader.gd")

static func validate_definition(definition: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	errors.append_array(definition.errors)
	if definition.id.is_empty():
		errors.append("Map id is required")
	var size: Vector3i = definition.size
	if size.x <= 0 or size.y <= 0 or size.z <= 0 or size.x > 256 or size.y > 128 or size.z > 256:
		errors.append("Map dimensions must be positive and at most 256x128x256")
	if definition.spawns.is_empty():
		errors.append("Map must define at least one spawn")
	var positions := {}
	var slots := {}
	var next_slots := {}
	for index in range(definition.spawns.size()):
		var spawn: Dictionary = definition.spawns[index]
		if not Loader._is_vector(spawn.get("position")):
			errors.append("Spawn %d position must contain three integers" % index)
		else:
			var key := str(spawn.position)
			if positions.has(key):
				errors.append("Spawn %d overlaps another spawn" % index)
			positions[key] = true
		var team: Variant = spawn.get("team")
		if not team is int or team not in [1, 2]:
			errors.append("Spawn %d team must be 1 or 2" % index)
			continue
		var slot: Variant = spawn.get("slot", next_slots.get(team, 0))
		if not slot is int or slot < 0:
			errors.append("Spawn %d slot must be a nonnegative integer" % index)
		else:
			var key := "%s:%s" % [team, slot]
			if slots.has(key):
				errors.append("Spawn %d duplicates a team slot" % index)
			slots[key] = true
			next_slots[team] = slot + 1
		var yaw: Variant = spawn.get("yaw", 0)
		if not (yaw is int or yaw is float) or not is_finite(float(yaw)):
			errors.append("Spawn %d yaw must be finite" % index)
	for box: Dictionary in definition.boxes:
		if not Loader._is_vector(box.get("position")) or not Loader._is_vector(box.get("size")):
			errors.append("Box position and size must contain three integers")
			continue
		var pos := Vector3i(box.position[0], box.position[1], box.position[2])
		var extent := Vector3i(box.size[0], box.size[1], box.size[2])
		if extent.x <= 0 or extent.y <= 0 or extent.z <= 0 or pos.x < 0 or pos.y < 0 or pos.z < 0 or pos.x + extent.x > size.x or pos.y + extent.y > size.y or pos.z + extent.z > size.z:
			errors.append("Box must have positive size and fit inside the map")
		if box.get("material", "dirt") not in ["air", "dirt", "stone", "metal"]:
			errors.append("Box uses unknown material")
		var health: Variant = box.get("health", 100)
		if not health is int or health < 0:
			errors.append("Box health must be a nonnegative integer")
	for carve: Dictionary in definition.carves:
		if carve.get("shape", "sphere") != "sphere" or not Loader._is_vector(carve.get("position")):
			errors.append("Carve requires a sphere and integer position")
		var radius: Variant = carve.get("radius", 1)
		if not radius is int or radius <= 0 or radius > 256:
			errors.append("Carve radius must be between 1 and 256")
	return errors

static func validate(definition: RefCounted, world: RefCounted) -> Array[String]:
	var errors := validate_definition(definition)
	if not errors.is_empty():
		return errors
	for index in range(definition.spawns.size()):
		var spawn: Dictionary = definition.spawns[index]
		var position := Vector3i(spawn.position[0], spawn.position[1], spawn.position[2])
		if not world.is_in_bounds(position) or not world.is_in_bounds(position + Vector3i.UP):
			errors.append("Spawn %d is outside map bounds" % index)
			continue
		if world.get_material_id(position) != 0 or world.get_material_id(position + Vector3i.UP) != 0:
			errors.append("Spawn %d is inside solid voxel" % index)
		if position.y <= 0 or world.get_material_id(position + Vector3i.DOWN) == 0:
			errors.append("Spawn %d is not standing on solid ground" % index)
	return errors
