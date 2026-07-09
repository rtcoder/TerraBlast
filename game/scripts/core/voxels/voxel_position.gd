class_name VoxelPosition
extends RefCounted

static func from_world(world_position: Vector3) -> Vector3i:
	return Vector3i(
		int(floor(world_position.x)),
		int(floor(world_position.y)),
		int(floor(world_position.z))
	)

static func to_world_center(voxel_position: Vector3i) -> Vector3:
	return Vector3(voxel_position) + Vector3(0.5, 0.5, 0.5)

