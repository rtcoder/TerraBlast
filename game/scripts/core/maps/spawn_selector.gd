class_name SpawnSelector
extends RefCounted
static func select(spawns: Array, count: int) -> Dictionary:
	if count < 2 or count > 10 or count > spawns.size(): return {"ok":false,"spawns":[],"reason":"invalid_count"}
	var teams := {1:[],2:[]}
	var seen := {}
	for spawn in spawns:
		if spawn == null or spawn.team not in [1,2] or spawn.slot < 0: return {"ok":false,"spawns":[],"reason":"invalid_spawn"}
		var key := "%d:%d" % [spawn.team,spawn.slot]
		if seen.has(key): return {"ok":false,"spawns":[],"reason":"duplicate_slot"}
		seen[key] = true
		teams[spawn.team].append(spawn)
	if teams[1].is_empty() or teams[2].is_empty(): return {"ok":false,"spawns":[],"reason":"missing_team"}
	for team in teams: teams[team].sort_custom(func(a,b): return a.slot < b.slot)
	var selected := []
	var indices := {1:0,2:0}
	while selected.size() < count:
		for team in [1,2]:
			if selected.size() < count and indices[team] < teams[team].size():
				selected.append(teams[team][indices[team]])
				indices[team] += 1
	return {"ok":true,"spawns":selected}
