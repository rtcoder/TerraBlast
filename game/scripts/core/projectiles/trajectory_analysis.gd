class_name TrajectoryAnalysis
extends RefCounted
const Ray = preload("res://scripts/core/voxels/voxel_raycast.gd")
static func classify(result: Dictionary) -> Dictionary:
	var errors := validate_result(result)
	var reason: String = result.get("reason", "invalid") if result.get("reason") is String else "invalid"
	return {"valid":errors.is_empty(),"complete":errors.is_empty() and reason in ["impact","fuse","miss"],"terminal_reason":reason}
static func validate_result(result: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not result.get("path") is PackedVector3Array or result.path.is_empty() or result.path.size() > 65537:
		errors.append("Invalid path")
	else:
		for point in result.path:
			if not point.is_finite():
				errors.append("Nonfinite path point")
				break
	if not result.get("position") is Vector3 or not result.position.is_finite(): errors.append("Invalid position")
	elif result.get("path") is PackedVector3Array and not result.path.is_empty() and result.path[-1] != result.position: errors.append("Terminal position differs from path")
	if not result.get("hit") is bool or result.get("reason") not in ["impact","fuse","miss","invalid","simulation_budget"]:
		errors.append("Invalid terminal classification")
	elif result.hit != (result.reason in ["impact","fuse"]): errors.append("Hit/reason mismatch")
	if not result.get("deltas") is Array or result.deltas.size() > 64:
		errors.append("Invalid drill deltas")
	else:
		var seen := {}
		for delta in result.deltas:
			if not delta is Dictionary or not delta.get("position") is Array or delta.position.size() != 3 or delta.get("material_id") != 0 or delta.get("health") != 0:
				errors.append("Invalid drill delta")
				continue
			var valid := true
			for value in delta.position:
				if not value is int or absi(value) > 1000000: valid = false
			var key := str(delta.position)
			if not valid or seen.has(key): errors.append("Invalid or repeated delta coordinate")
			seen[key] = true
	return errors
static func trace_intersections(world: RefCounted, path: PackedVector3Array, materials: Dictionary = {}, max_segments: int = 4096) -> Dictionary:
	var hits := []
	if path.is_empty() or max_segments < 1: return {"ok":false,"hits":hits,"truncated":false}
	var count := mini(path.size()-1,mini(max_segments,4096))
	for i in range(count):
		var hit := Ray.segment_hit(world,path[i],path[i+1],materials)
		if hit.reason == "invalid": return {"ok":false,"hits":hits,"truncated":false}
		if hit.hit:
			hit["segment"] = i
			hits.append(hit)
	return {"ok":true,"hits":hits,"truncated":count < path.size()-1}
static func summarize(result: Dictionary) -> Dictionary:
	var classification := classify(result)
	if not classification.valid: return {"ok":false,"reason":"invalid_trace"}
	var path: PackedVector3Array = result.path
	var apex := path[0]
	var low := path[0]
	var high := path[0]
	var length := 0.0
	for i in range(path.size()):
		if path[i].y > apex.y: apex = path[i]
		low = low.min(path[i])
		high = high.max(path[i])
		if i > 0: length += path[i-1].distance_to(path[i])
	return {"ok":true,"apex":apex,"bounds_min":low,"bounds_max":high,"length":length,"samples":path.size(),"terminal_position":result.position,"complete":classification.complete,"reason":classification.terminal_reason}
