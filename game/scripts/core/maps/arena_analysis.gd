class_name ArenaAnalysis
extends RefCounted
const Ray = preload("res://scripts/core/voxels/voxel_raycast.gd")
const Motion = preload("res://scripts/core/rules/player_motion.gd")
static func summarize(world: RefCounted, materials: Dictionary) -> Dictionary:
	var result := {"material_counts":{},"solid_count":0,"destructible_count":0,"occupied_min":world.size,"occupied_max":Vector3i(-1,-1,-1),"heightmap":[]}
	for z in range(world.size.z):
		var row := []
		for x in range(world.size.x):
			var height := -1
			for y in range(world.size.y):
				var p := Vector3i(x,y,z)
				var id: int = world.get_material_id(p)
				result.material_counts[id] = result.material_counts.get(id,0) + 1
				if id == 0: continue
				result.occupied_min = result.occupied_min.min(p)
				result.occupied_max = result.occupied_max.max(p)
				if Ray.is_solid(world,p,materials):
					result.solid_count += 1
					height = y + 1
				if materials.has(id) and materials[id].is_destructible: result.destructible_count += 1
			row.append(height)
		result.heightmap.append(row)
	return result
static func _standing(world: RefCounted, p: Vector3i, materials: Dictionary) -> bool:
	return p.y > 0 and world.is_in_bounds(p + Vector3i.UP) and Ray.is_solid(world,p + Vector3i.DOWN,materials) and not Motion.blocked(world,Vector3(p)+Vector3(0.5,0,0.5),materials)
static func spawn_clearance(world: RefCounted, spawns: Array, materials: Dictionary, radius: int = 3) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	radius = clampi(radius,1,8)
	for spawn in spawns:
		var p: Vector3i = spawn.position
		var free := 0
		var cover := 0
		for z in range(p.z-radius,p.z+radius+1):
			for x in range(p.x-radius,p.x+radius+1):
				var q := Vector3i(x,p.y,z)
				if q == p or not world.is_in_bounds(q): continue
				if _standing(world,q,materials): free += 1
				if Ray.is_solid(world,q,materials) or Ray.is_solid(world,q+Vector3i.UP,materials): cover += 1
		results.append({"team":spawn.team,"slot":spawn.slot,"height":p.y,"free_supported_neighbors":free,"cover_neighbors":cover,"edge_distance":mini(mini(p.x,p.z),mini(world.size.x-1-p.x,world.size.z-1-p.z))})
	return results
static func walk_components(world: RefCounted, materials: Dictionary, max_nodes: int = 100000) -> Dictionary:
	max_nodes = clampi(max_nodes,1,100000)
	var positions := {}
	var scanned := 0
	var truncated := false
	# Bound candidate scanning too, so a sparse huge world cannot bypass the budget.
	for index in range(world.material_ids.size()):
		if scanned >= max_nodes:
			truncated = true
			break
		scanned += 1
		var x: int = index % world.size.x
		var y: int = (index / world.size.x) % world.size.y
		var z: int = index / (world.size.x * world.size.y)
		var p := Vector3i(x,y,z)
		if _standing(world,p,materials): positions[p] = true
	var components := []
	var seen := {}
	for start in positions:
		if seen.has(start): continue
		var queue: Array = [start]
		seen[start] = true
		var cursor := 0
		while cursor < queue.size():
			var p: Vector3i = queue[cursor]
			cursor += 1
			for offset in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]:
				var next: Vector3i = p + offset
				if positions.has(next) and not seen.has(next):
					seen[next] = true
					queue.append(next)
		components.append({"size":queue.size(),"positions":queue})
	return {"ok":true,"components":components,"truncated":truncated,"visited":scanned}
static func compare_teams(world: RefCounted, spawns: Array, materials: Dictionary) -> Dictionary:
	var teams := {1:{"count":0,"height":0.0,"free_supported_neighbors":0.0,"cover_neighbors":0.0},2:{"count":0,"height":0.0,"free_supported_neighbors":0.0,"cover_neighbors":0.0}}
	for row in spawn_clearance(world,spawns,materials):
		if not teams.has(row.team): continue
		teams[row.team].count += 1
		for key in ["height","free_supported_neighbors","cover_neighbors"]: teams[row.team][key] += row[key]
	for team in teams:
		for key in ["height","free_supported_neighbors","cover_neighbors"]:
			if teams[team].count > 0: teams[team][key] /= teams[team].count
	var differences := {}
	var warnings: Array[String] = []
	for key in ["height","free_supported_neighbors","cover_neighbors"]:
		differences[key] = teams[1][key] - teams[2][key]
		if differences[key] != 0: warnings.append("Team difference: " + key)
	if teams[1].count == 0 or teams[2].count == 0: warnings.append("Missing team")
	return {"teams":teams,"differences":differences,"warnings":warnings}
