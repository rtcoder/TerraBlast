class_name VoxelChunkMeshBuilder
extends RefCounted

const FACE_DATA := [
	{
		"normal": Vector3i(1, 0, 0),
		"corners": [Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(1, 0, 1)],
	},
	{
		"normal": Vector3i(-1, 0, 0),
		"corners": [Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0), Vector3(0, 0, 0)],
	},
	{
		"normal": Vector3i(0, 1, 0),
		"corners": [Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0), Vector3(0, 1, 0)],
	},
	{
		"normal": Vector3i(0, -1, 0),
		"corners": [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)],
	},
	{
		"normal": Vector3i(0, 0, 1),
		"corners": [Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1), Vector3(0, 0, 1)],
	},
	{
		"normal": Vector3i(0, 0, -1),
		"corners": [Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 0, 0)],
	},
]

static func build_mesh(world: RefCounted, chunk_position: Vector3i, material_configs: Dictionary, chunk_size: int) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var chunk_origin := chunk_position * chunk_size
	var chunk_end := chunk_origin + Vector3i(chunk_size, chunk_size, chunk_size)

	for z in range(chunk_origin.z, mini(chunk_end.z, world.size.z)):
		for y in range(chunk_origin.y, mini(chunk_end.y, world.size.y)):
			for x in range(chunk_origin.x, mini(chunk_end.x, world.size.x)):
				var voxel_position := Vector3i(x, y, z)
				var material_id: int = int(world.get_material_id(voxel_position))
				if not _is_solid_material(material_id, material_configs):
					continue

				for face: Dictionary in FACE_DATA:
					var normal: Vector3i = face["normal"]
					var neighbor := voxel_position + normal
					if _is_solid_voxel(world, neighbor, material_configs):
						continue
					_append_face(vertices, normals, colors, indices, voxel_position, face, _color_for_face(material_id, normal, voxel_position))

	var mesh := ArrayMesh.new()
	if vertices.is_empty():
		return mesh

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

static func _append_face(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	voxel_position: Vector3i,
	face: Dictionary,
	color: Color
) -> void:
	var base_index := vertices.size()
	var normal_i: Vector3i = face["normal"]
	var normal := Vector3(float(normal_i.x), float(normal_i.y), float(normal_i.z))
	for corner: Vector3 in face["corners"]:
		vertices.append(Vector3(voxel_position) + corner)
		normals.append(normal)
		colors.append(color)

	indices.append_array(PackedInt32Array([
		base_index,
		base_index + 1,
		base_index + 2,
		base_index,
		base_index + 2,
		base_index + 3,
	]))

static func _is_solid_voxel(world: RefCounted, voxel_position: Vector3i, material_configs: Dictionary) -> bool:
	if not world.is_in_bounds(voxel_position):
		return false
	return _is_solid_material(int(world.get_material_id(voxel_position)), material_configs)

static func _is_solid_material(material_id: int, material_configs: Dictionary) -> bool:
	if not material_configs.has(material_id):
		return false
	return bool(material_configs[material_id].is_solid)

static func _color_for_face(material_id: int, normal: Vector3i, voxel_position: Vector3i) -> Color:
	var color := _base_color_for_face(material_id, normal, voxel_position)
	return color * _shade_for_normal(normal)

static func _base_color_for_face(material_id: int, normal: Vector3i, voxel_position: Vector3i) -> Color:
	match material_id:
		1:
			if normal == Vector3i(0, 1, 0):
				return _grass_color(voxel_position)
			if normal == Vector3i(0, -1, 0):
				return Color(0.30, 0.19, 0.10)
			return _dirt_side_color(voxel_position)
		2:
			return Color(0.48, 0.50, 0.54)
		3:
			return Color(0.67, 0.70, 0.73)
		_:
			return Color(0.86, 0.74, 0.45)

static func _shade_for_normal(normal: Vector3i) -> Color:
	if normal == Vector3i(0, 1, 0):
		return Color(1.08, 1.08, 1.08)
	if normal == Vector3i(0, -1, 0):
		return Color(0.45, 0.45, 0.45)
	if normal == Vector3i(1, 0, 0):
		return Color(0.78, 0.78, 0.78)
	if normal == Vector3i(-1, 0, 0):
		return Color(0.68, 0.68, 0.68)
	if normal == Vector3i(0, 0, 1):
		return Color(0.86, 0.86, 0.86)
	return Color(0.62, 0.62, 0.62)

static func _grass_color(voxel_position: Vector3i) -> Color:
	var checker: int = int(abs((voxel_position.x * 17 + voxel_position.z * 31) % 5))
	match checker:
		0:
			return Color(0.26, 0.62, 0.18)
		1:
			return Color(0.31, 0.72, 0.20)
		2:
			return Color(0.39, 0.78, 0.24)
		3:
			return Color(0.22, 0.54, 0.16)
		_:
			return Color(0.34, 0.68, 0.21)

static func _dirt_side_color(voxel_position: Vector3i) -> Color:
	var checker: int = int(abs((voxel_position.x * 13 + voxel_position.y * 7 + voxel_position.z * 19) % 4))
	match checker:
		0:
			return Color(0.39, 0.23, 0.11)
		1:
			return Color(0.48, 0.30, 0.15)
		2:
			return Color(0.34, 0.20, 0.10)
		_:
			return Color(0.43, 0.26, 0.12)
