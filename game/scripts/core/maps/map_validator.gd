class_name MapValidator
extends RefCounted

const MAX_WORK := 32000000
const Ray = preload("res://scripts/core/voxels/voxel_raycast.gd")
const Motion = preload("res://scripts/core/rules/player_motion.gd")

const MAX_VOLUME := 2097152
const MAX_OPERATIONS := 4096
const MAX_SPAWNS := 32

const Loader := preload("res://scripts/core/maps/map_loader.gd")

static func validate_definition(definition: RefCounted, materials: Dictionary = {}) -> Array[String]:
	var errors: Array[String] = []
	errors.append_array(definition.errors)
	if definition.id.is_empty() or definition.id.length() > 64:
		errors.append("Map id must contain 1–64 characters")
	for character in definition.id:
		if character not in "abcdefghijklmnopqrstuvwxyz0123456789_":
			errors.append("Map id must use lowercase letters, digits or underscore")
			break
	for pair in [[definition.display_name,128,false],[definition.theme,64,true]]:
		if pair[0].length() > pair[1] or (not pair[2] and pair[0].strip_edges().is_empty()): errors.append("Map text length invalid")
		for i in range(pair[0].length()):
			var code: int = pair[0].unicode_at(i)
			if code < 32 or (code >= 127 and code <= 159):
				errors.append("Map text contains a control character")
				break
	var size: Vector3i = definition.size
	if size.x <= 0 or size.y <= 0 or size.z <= 0 or size.x > 256 or size.y > 128 or size.z > 256:
		errors.append("Map dimensions must be positive and at most 256x128x256")
	elif size.x * size.y * size.z > MAX_VOLUME:
		errors.append("Map volume exceeds 2097152 voxels")
	if definition.boxes.size() + definition.carves.size() > MAX_OPERATIONS:
		errors.append("Map exceeds 4096 construction operations")
	if definition.spawns.size() > MAX_SPAWNS:
		errors.append("Map exceeds 32 spawns")
	if not errors.is_empty():
		return errors
	if definition.spawns.is_empty():
		errors.append("Map must define at least one spawn")
	var work := 0
	var positions := {}
	var slots := {}
	var next_slots := {}
	for index in range(definition.spawns.size()):
		var spawn: Dictionary = definition.spawns[index]
		_check_keys(spawn, ["position","team","slot","yaw"], errors)
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
		_check_keys(box, ["position","size","material","health","name"], errors)
		if not Loader._is_vector(box.get("position")) or not Loader._is_vector(box.get("size")):
			errors.append("Box position and size must contain three integers")
			continue
		var pos := Vector3i(box.position[0], box.position[1], box.position[2])
		var extent := Vector3i(box.size[0], box.size[1], box.size[2])
		if extent.x <= 0 or extent.y <= 0 or extent.z <= 0 or pos.x < 0 or pos.y < 0 or pos.z < 0 or pos.x + extent.x > size.x or pos.y + extent.y > size.y or pos.z + extent.z > size.z:
			errors.append("Box must have positive size and fit inside the map")
		var codes: Array = ["air", "dirt", "stone", "metal"] if materials.is_empty() else materials.values().map(func(m): return m.code)
		if box.get("material", "dirt") not in codes:
			errors.append("Box uses unknown material")
		var health: Variant = box.get("health", 100)
		if not health is int or health < 0 or health > 10000 or (box.has("health") and ((box.get("material", "dirt") == "air" and health != 0) or (box.get("material", "dirt") != "air" and health == 0))):
			errors.append("Box health must be a nonnegative integer")
		work += _volume(pos, pos + extent, size)
	for carve: Dictionary in definition.carves:
		_check_keys(carve, ["position","shape","radius"], errors)
		if carve.get("shape", "sphere") != "sphere" or not Loader._is_vector(carve.get("position")):
			errors.append("Carve requires a sphere and integer position")
		var radius: Variant = carve.get("radius", 1)
		if not radius is int or radius <= 0 or radius > 256:
			errors.append("Carve radius must be between 1 and 256")
		if Loader._is_vector(carve.get("position")) and radius is int and radius > 0 and radius <= 256:
			var center := Vector3i(carve.position[0],carve.position[1],carve.position[2])
			var extent: Vector3i = Vector3i.ONE * int(radius)
			var visits := _volume(center - extent, center + extent + Vector3i.ONE, size)
			if visits == 0: errors.append("Carve must intersect map bounds")
			work += visits
	if work > MAX_WORK: errors.append("Map construction exceeds voxel work budget")
	return errors

static func validate(definition: RefCounted, world: RefCounted, materials: Dictionary = {}) -> Array[String]:
	var errors := validate_definition(definition, materials)
	if not errors.is_empty():
		return errors
	for index in range(definition.spawns.size()):
		var spawn: Dictionary = definition.spawns[index]
		var position := Vector3i(spawn.position[0], spawn.position[1], spawn.position[2])
		if not world.is_in_bounds(position) or not world.is_in_bounds(position + Vector3i.UP):
			errors.append("Spawn %d is outside map bounds" % index)
			continue
		if Motion.blocked(world,Vector3(position) + Vector3(0.5,0,0.5),materials):
			errors.append("Spawn %d is inside solid voxel" % index)
		if position.y <= 0 or not Ray.is_solid(world,position + Vector3i.DOWN,materials):
			errors.append("Spawn %d is not standing on solid ground" % index)
		for previous in range(index):
			var other: Array = definition.spawns[previous].position
			var difference := Vector3(position) - Vector3(other[0],other[1],other[2])
			if absf(difference.x) < Motion.RADIUS * 2 and absf(difference.z) < Motion.RADIUS * 2 and absf(difference.y) < Motion.HEIGHT:
				errors.append("Spawn %d overlaps another pawn body" % index)
	return errors

static func _check_keys(data: Dictionary, allowed: Array, errors: Array[String]) -> void:
	for key in data:
		if key not in allowed: errors.append("Unknown operation key: " + str(key))

static func _volume(low: Vector3i, high: Vector3i, size: Vector3i) -> int:
	var extent := high.min(size) - low.max(Vector3i.ZERO)
	return maxi(0,extent.x) * maxi(0,extent.y) * maxi(0,extent.z)

static func inspect_definition(definition: RefCounted) -> Dictionary:
	var errors := validate_definition(definition)
	return {"ok":errors.is_empty(),"errors":errors,"warnings":[]}
