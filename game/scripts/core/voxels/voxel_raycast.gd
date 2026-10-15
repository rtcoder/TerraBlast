class_name VoxelRaycast
extends RefCounted

const MISS := Vector3i(-1,-1,-1)

static func is_solid(world: RefCounted, voxel: Vector3i, materials: Dictionary = {}) -> bool:
	var id: int = world.get_material_id(voxel)
	return id != 0 and (not materials.has(id) or materials[id].is_solid)

# Grid DDA visits every crossed cell, including thin diagonal intersections.
static func first_solid(world: RefCounted, origin: Vector3, direction: Vector3, materials: Dictionary, max_distance: float = 120.0) -> Vector3i:
	if not origin.is_finite() or not direction.is_finite() or direction.length_squared() < 0.000001 or not is_finite(max_distance) or max_distance < 0:
		return MISS
	max_distance = minf(max_distance, 4096.0)
	var ray := direction.normalized()
	var cell := Vector3i(floori(origin.x), floori(origin.y), floori(origin.z))
	var step := Vector3i(signi(int(signf(ray.x))),signi(int(signf(ray.y))),signi(int(signf(ray.z))))
	var distances := Vector3(INF,INF,INF)
	var increments := Vector3(INF,INF,INF)
	for axis in range(3):
		if ray[axis] != 0:
			increments[axis] = absf(1.0 / ray[axis])
			distances[axis] = (float(cell[axis] + (1 if step[axis] > 0 else 0)) - origin[axis]) / ray[axis]
	var traveled := 0.0
	for iteration in range(16384):
		if traveled > max_distance:
			break
		if is_solid(world, cell, materials):
			return cell
		var axis := 0 if distances.x <= distances.y and distances.x <= distances.z else (1 if distances.y <= distances.z else 2)
		traveled = distances[axis]
		cell[axis] += step[axis]
		distances[axis] += increments[axis]
	return MISS
