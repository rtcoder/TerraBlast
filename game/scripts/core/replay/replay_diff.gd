extends RefCounted
const Replay = preload("res://scripts/core/replay/match_replay.gd")
const Notes = preload("res://scripts/core/replay/replay_notebook.gd")
static func compare(first: RefCounted, second: RefCounted, limit := 256) -> Dictionary:
	if first == null or second == null or limit < 1 or limit > 4096: return Notes.failure("invalid_comparison")
	var left = first.replay()
	var right = second.replay()
	if left == null or right == null: return Notes.failure("invalid_recording")
	var a: Dictionary = left.state_snapshot()
	var b: Dictionary = right.state_snapshot()
	var report := {"version":1,"ok":true,"players":[],"inventory":[],"statistics":[],"state":{},"configuration":{},"terrain":{"same_size":left.world.size == right.world.size,"count":0,"material_changes":0,"health_changes":0,"details":[],"truncated":false},"actions":{"first_difference":-1,"left_count":first.data.actions.size(),"right_count":second.data.actions.size()},"hashes":{"left":Replay.state_hash(left),"right":Replay.state_hash(right)}}
	for key in ["state","terrain","health","size","rules","weapons","materials"]: report.configuration[key+"_equal"] = JSON.stringify(first.data[key],"",true,true) == JSON.stringify(second.data[key],"",true,true)
	report.configuration.initial_equal = true
	for value in report.configuration.values():
		if value == false: report.configuration.initial_equal = false; break
	var players_a := {}
	var players_b := {}
	for player in a.players: players_a[player.id] = player
	for player in b.players: players_b[player.id] = player
	var ids := players_a.keys()
	for id in players_b:
		if id not in ids: ids.append(id)
	ids.sort()
	for id in ids:
		if players_a.get(id) != players_b.get(id): report.players.append({"id":id,"left":players_a.get(id),"right":players_b.get(id)})
		var inv_a: Dictionary = a.inventory.get(id,{})
		var inv_b: Dictionary = b.inventory.get(id,{})
		var weapons := inv_a.keys()
		for weapon in inv_b:
			if weapon not in weapons: weapons.append(weapon)
		weapons.sort()
		for weapon in weapons:
			var first_ammo: Variant = inv_a.get(weapon)
			var second_ammo: Variant = inv_b.get(weapon)
			if first_ammo != second_ammo: report.inventory.append({"player":id,"weapon":weapon,"left":first_ammo,"right":second_ammo,"delta":second_ammo-first_ammo if first_ammo != null and second_ammo != null and first_ammo != -1 and second_ammo != -1 else null})
		var stats_a: Dictionary = a.statistics.get(id,{})
		var stats_b: Dictionary = b.statistics.get(id,{})
		var keys := stats_a.keys()
		for key in stats_b:
			if key not in keys: keys.append(key)
		keys.sort()
		for key in keys:
			if stats_a.get(key) != stats_b.get(key): report.statistics.append({"player":id,"metric":key,"left":stats_a.get(key),"right":stats_b.get(key),"delta":stats_b.get(key,0)-stats_a.get(key,0)})
	for key in a:
		if key not in ["players","inventory","statistics"] and a[key] != b.get(key): report.state[key] = {"left":a[key],"right":b.get(key)}
	if report.terrain.same_size:
		for index in left.world.material_ids.size():
			var material_changed: bool = left.world.material_ids[index] != right.world.material_ids[index]
			var health_changed: bool = left.world.health_values[index] != right.world.health_values[index]
			if not material_changed and not health_changed: continue
			report.terrain.count += 1
			if material_changed: report.terrain.material_changes += 1
			if health_changed and not material_changed: report.terrain.health_changes += 1
			if report.terrain.details.size() < limit:
				var dimensions: Vector3i = left.world.size
				var position := [index % dimensions.x,(index / dimensions.x) % dimensions.y,index / (dimensions.x*dimensions.y)]
				report.terrain.details.append({"position":position,"left_material":left.world.material_ids[index],"right_material":right.world.material_ids[index],"left_health":left.world.health_values[index],"right_health":right.world.health_values[index]})
		report.terrain.truncated = report.terrain.count > limit
	else: report.terrain.count = -1
	for index in maxi(first.data.actions.size(),second.data.actions.size()):
		if index >= first.data.actions.size() or index >= second.data.actions.size() or JSON.stringify(first.data.actions[index],"",true,true) != JSON.stringify(second.data.actions[index],"",true,true): report.actions.first_difference = index; break
	return report
static func export(path: String, report: Dictionary, replace := false, protected_paths: Array = []) -> Dictionary:
	if not report.get("ok",false) or report.get("version") != 1: return Notes.failure("invalid_report")
	return Notes.atomic_write(path,JSON.stringify(report,"",true,true),replace,protected_paths)
