class_name VoxelChunkData
extends RefCounted

const DEFAULT_CHUNK_SIZE := 16

var chunk_position: Vector3i
var chunk_size: int
var material_ids: PackedInt32Array
var health_values: PackedInt32Array

func _init(initial_chunk_position: Vector3i = Vector3i.ZERO, initial_chunk_size: int = DEFAULT_CHUNK_SIZE) -> void:
	chunk_position = initial_chunk_position
	chunk_size = initial_chunk_size
	var count := chunk_size * chunk_size * chunk_size
	material_ids.resize(count)
	health_values.resize(count)
	material_ids.fill(0)
	health_values.fill(0)

func is_in_bounds(local_position: Vector3i) -> bool:
	return local_position.x >= 0 and local_position.y >= 0 and local_position.z >= 0 \
		and local_position.x < chunk_size and local_position.y < chunk_size and local_position.z < chunk_size

func get_index(local_position: Vector3i) -> int:
	return local_position.x + chunk_size * (local_position.y + chunk_size * local_position.z)

func get_material_id(local_position: Vector3i) -> int:
	if not is_in_bounds(local_position):
		return 0
	return material_ids[get_index(local_position)]

func get_health(local_position: Vector3i) -> int:
	if not is_in_bounds(local_position):
		return 0
	return health_values[get_index(local_position)]

func set_voxel(local_position: Vector3i, material_id: int, health: int) -> void:
	if not is_in_bounds(local_position):
		return
	var index := get_index(local_position)
	material_ids[index] = material_id
	health_values[index] = max(0, health)

func set_health(local_position: Vector3i, health: int) -> void:
	if not is_in_bounds(local_position):
		return
	health_values[get_index(local_position)] = max(0, health)
