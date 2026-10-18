class_name VoxelWorldData
extends RefCounted

const ChunkPositionScript := preload("res://scripts/core/chunks/chunk_position.gd")
const DEFAULT_CHUNK_SIZE := 16

var size: Vector3i
var chunk_size: int
var material_ids: PackedInt32Array
var health_values: PackedInt32Array

func _init(world_size: Vector3i = Vector3i(128, 64, 128), initial_chunk_size: int = DEFAULT_CHUNK_SIZE) -> void:
	size = world_size
	chunk_size = initial_chunk_size
	var count := size.x * size.y * size.z
	material_ids.resize(count)
	health_values.resize(count)
	material_ids.fill(0)
	health_values.fill(0)

func is_in_bounds(position: Vector3i) -> bool:
	return position.x >= 0 and position.y >= 0 and position.z >= 0 \
		and position.x < size.x and position.y < size.y and position.z < size.z

func get_index(position: Vector3i) -> int:
	return position.x + size.x * (position.y + size.y * position.z)

func get_material_id(position: Vector3i) -> int:
	if not is_in_bounds(position):
		return 0
	return material_ids[get_index(position)]

func get_health(position: Vector3i) -> int:
	if not is_in_bounds(position):
		return 0
	return health_values[get_index(position)]

func set_voxel(position: Vector3i, material_id: int, health: int) -> void:
	if not is_in_bounds(position):
		return
	var index := get_index(position)
	material_ids[index] = material_id
	health_values[index] = max(0, health)

func set_health(position: Vector3i, health: int) -> void:
	if not is_in_bounds(position):
		return
	health_values[get_index(position)] = max(0, health)

func get_chunk_position(position: Vector3i) -> Vector3i:
	return ChunkPositionScript.from_voxel(position, chunk_size)

func get_local_position(position: Vector3i) -> Vector3i:
	return ChunkPositionScript.local_from_voxel(position, chunk_size)

func fill_box(from_position: Vector3i, to_position: Vector3i, material_id: int, health: int) -> void:
	for z in range(maxi(0,from_position.z), mini(size.z,to_position.z)):
		for y in range(maxi(0,from_position.y), mini(size.y,to_position.y)):
			for x in range(maxi(0,from_position.x), mini(size.x,to_position.x)):
				set_voxel(Vector3i(x, y, z), material_id, health)
