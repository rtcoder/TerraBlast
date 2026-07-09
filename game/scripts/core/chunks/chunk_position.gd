class_name ChunkPosition
extends RefCounted

const CHUNK_SIZE := 16

static func from_voxel(voxel_position: Vector3i, chunk_size: int = CHUNK_SIZE) -> Vector3i:
	return Vector3i(
		_floor_div(voxel_position.x, chunk_size),
		_floor_div(voxel_position.y, chunk_size),
		_floor_div(voxel_position.z, chunk_size)
	)

static func local_from_voxel(voxel_position: Vector3i, chunk_size: int = CHUNK_SIZE) -> Vector3i:
	return Vector3i(
		_positive_mod(voxel_position.x, chunk_size),
		_positive_mod(voxel_position.y, chunk_size),
		_positive_mod(voxel_position.z, chunk_size)
	)

static func _floor_div(value: int, divisor: int) -> int:
	return int(floor(float(value) / float(divisor)))

static func _positive_mod(value: int, divisor: int) -> int:
	return ((value % divisor) + divisor) % divisor

