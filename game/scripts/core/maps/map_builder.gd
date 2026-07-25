class_name MapBuilder
extends RefCounted

static func apply_to_world(world: RefCounted, material_configs: Dictionary, definition: RefCounted) -> void:
	for box: Dictionary in definition.boxes:
		_apply_box(world, material_configs, box)
	for carve: Dictionary in definition.carves:
		_apply_carve(world, carve)

static func _apply_box(world: RefCounted, material_configs: Dictionary, box: Dictionary) -> void:
	var position := _vector3i_from_array(box.get("position", [0, 0, 0]))
	var size := _vector3i_from_array(box.get("size", [1, 1, 1]))
	var material_id := _material_id(material_configs, str(box.get("material", "dirt")))
	var health := _material_health(material_configs, material_id)
	world.fill_box(position, position + size, material_id, health)

static func _apply_carve(world: RefCounted, carve: Dictionary) -> void:
	var shape := str(carve.get("shape", "sphere"))
	if shape == "sphere":
		_carve_sphere(world, _vector3i_from_array(carve.get("position", [0, 0, 0])), int(carve.get("radius", 1)))

static func _carve_sphere(world: RefCounted, center: Vector3i, radius: int) -> void:
	var radius_squared := radius * radius
	for z in range(center.z - radius, center.z + radius + 1):
		for y in range(center.y - radius, center.y + radius + 1):
			for x in range(center.x - radius, center.x + radius + 1):
				var position := Vector3i(x, y, z)
				if position.distance_squared_to(center) <= radius_squared:
					world.set_voxel(position, 0, 0)

static func _material_id(material_configs: Dictionary, code: String) -> int:
	for material_id: int in material_configs.keys():
		var material: Resource = material_configs[material_id]
		if material.code == code:
			return material_id
	return 1

static func _material_health(material_configs: Dictionary, material_id: int) -> int:
	var material: Resource = material_configs.get(material_id)
	if material == null:
		return 100
	return material.max_health

static func _vector3i_from_array(value: Variant) -> Vector3i:
	if not value is Array or value.size() != 3:
		return Vector3i.ZERO
	return Vector3i(int(value[0]), int(value[1]), int(value[2]))

