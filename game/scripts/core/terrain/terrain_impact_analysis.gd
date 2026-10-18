class_name TerrainImpactAnalysis
extends RefCounted
const Delta = preload("res://scripts/core/voxels/terrain_delta.gd")
static func summarize(world: RefCounted, deltas: Array, materials: Dictionary) -> Dictionary:
	var result := {"ok":true,"changed":0,"destroyed":0,"health_lost":0,"by_material":{},"bounds_min":world.size,"bounds_max":Vector3i(-1,-1,-1),"affected_chunks":[]}
	if deltas.size() > 65536:
		result.ok = false
		return result
	var final := {}
	for delta in deltas:
		if not delta is Dictionary and not delta is Delta:
			result.ok = false
			return result
		var p: Variant = delta.get("position")
		if p is Array and p.size() == 3:
			for value in p:
				if not value is int or absi(value) > 1000000:
					result.ok = false
					return result
			p = Vector3i(p[0],p[1],p[2])
		var id: Variant = delta.get("material_id")
		var health: Variant = delta.get("health")
		if not p is Vector3i or not world.is_in_bounds(p) or not id is int or not materials.has(id) or not health is int or health < 0 or health > 10000:
			result.ok = false
			return result
		final[p] = {"material_id":id,"health":health}
	var chunks := {}
	for p in final:
		var before: int = world.get_material_id(p)
		var hp: int = world.get_health(p)
		var after: Dictionary = final[p]
		if before == after.material_id and hp == after.health: continue
		var destroyed := 1 if before != 0 and after.material_id == 0 else 0
		var lost := maxi(0,hp-after.health)
		result.changed += 1
		result.destroyed += destroyed
		result.health_lost += lost
		if not result.by_material.has(before): result.by_material[before] = {"changed":0,"destroyed":0,"health_lost":0}
		result.by_material[before].changed += 1
		result.by_material[before].destroyed += destroyed
		result.by_material[before].health_lost += lost
		result.bounds_min = result.bounds_min.min(p)
		result.bounds_max = result.bounds_max.max(p)
		chunks[world.get_chunk_position(p)] = true
	result.affected_chunks = chunks.keys()
	result.affected_chunks.sort_custom(func(a,b): return a.x < b.x if a.x != b.x else (a.y < b.y if a.y != b.y else a.z < b.z))
	return result
