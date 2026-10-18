class_name ReplayAnalyzer
extends RefCounted
const Replay = preload("res://scripts/core/replay/match_replay.gd")
var runner: RefCounted
var recorder: RefCounted
var index := 0
var finished := false
var cancelled := false
var error := ""
var duration := 0.0
var _initial_hash := ""
var _baseline := {}
var _players := {}
var _types := {"tick":0,"move":0,"shot":0,"surrender":0}
var _shots: Array = []
var _turns: Array = []
var _eliminations: Array = []
var _weapons := {}
var _terrain := {"changed":0,"destroyed":0,"materials":{}}
func begin(source: RefCounted) -> bool:
	if source == null or not source.recording_error.is_empty() or not source.valid_data():
		error = "invalid_recording"
		return false
	var candidate = Replay.new()
	candidate.data = source.data.duplicate(true)
	var initial: RefCounted = candidate.initial_runner()
	if initial == null:
		error = "invalid_initial_state"
		return false
	recorder = candidate
	runner = initial
	index = 0
	finished = recorder.data.actions.is_empty()
	cancelled = false
	error = ""
	duration = 0
	_initial_hash = Replay.state_hash(runner)
	_baseline = runner.statistics.duplicate(true)
	_players.clear()
	_types = {"tick":0,"move":0,"shot":0,"surrender":0}
	_shots.clear()
	_turns.clear()
	_eliminations.clear()
	_weapons.clear()
	_terrain = {"changed":0,"destroyed":0,"materials":{}}
	for player in runner.state.players:
		_players[player.player_id] = {"id":player.player_id,"name":player.display_name,"team":player.team_id,"shots":0,"hits":0,"damage":0,"kills":0,"distance":0.0,"active_time":0.0}
	_record_turn()
	return true
func cancel() -> void:
	cancelled = true
	finished = true
	error = "cancelled"
func step(max_actions: int = 256) -> Dictionary:
	if recorder == null: return {"ok":false,"reason":"not_started"}
	if max_actions < 1: return {"ok":false,"reason":"invalid_budget"}
	if cancelled or not error.is_empty(): return {"ok":false,"reason":error,"index":index}
	for unused in mini(max_actions,4096):
		if index >= recorder.data.actions.size():
			finished = true
			break
		var action: Dictionary = recorder.data.actions[index]
		var active = runner.state.get_active_player()
		var active_id: String = active.player_id if active != null else ""
		var old_position: Vector3 = active.position if active != null else Vector3.ZERO
		var alive := {}
		for player in runner.state.players: alive[player.player_id] = player.is_alive
		var turn: int = runner.state.turn_id
		var generation: int = runner.state.generation
		var old_materials: PackedInt32Array = runner.world.material_ids.duplicate() if action.type == "shot" else PackedInt32Array()
		var result: Dictionary = Replay.execute_action(runner,action)
		if not result.ok:
			error = str(result.get("reason",result.get("result",{}).get("reason","invalid_action")))
			finished = true
			return {"ok":false,"reason":error,"index":index,"type":action.type}
		index += 1
		_types[action.type] += 1
		if action.type == "tick":
			duration += action.delta
			if _players.has(active_id): _players[active_id].active_time += action.delta
		elif action.type == "move" and active != null:
			_players[active_id].distance += old_position.distance_to(active.position)
		elif action.type == "shot":
			var shot: Dictionary = runner.history.back().duplicate(true)
			shot.index = index
			shot.time = duration
			_shots.append(shot)
			var weapon_id := str(int(action.weapon_id))
			if not _weapons.has(weapon_id): _weapons[weapon_id] = {"weapon_id":int(action.weapon_id),"shots":0,"damage":0,"kills":0}
			_weapons[weapon_id].shots += 1
			_weapons[weapon_id].damage += shot.damage
			_weapons[weapon_id].kills += shot.kills
			var visited := {}
			for delta in result.result.get("deltas",[]):
				var position := Vector3i(delta.position[0],delta.position[1],delta.position[2])
				var voxel: int = runner.world.get_index(position)
				if visited.has(voxel): continue
				visited[voxel] = true
				var material := str(old_materials[voxel])
				var destroyed: bool = old_materials[voxel] != 0 and runner.world.get_material_id(position) == 0
				_terrain.changed += 1
				_terrain.destroyed += int(destroyed)
				if not _terrain.materials.has(material): _terrain.materials[material] = {"changed":0,"destroyed":0}
				_terrain.materials[material].changed += 1
				_terrain.materials[material].destroyed += int(destroyed)
		for player in runner.state.players:
			if alive[player.player_id] and not player.is_alive: _eliminations.append({"id":player.player_id,"index":index,"time":duration,"type":action.type})
		if turn != runner.state.turn_id or generation != runner.state.generation: _record_turn()
	finished = index >= recorder.data.actions.size()
	return {"ok":true,"index":index,"total":recorder.data.actions.size(),"finished":finished}
func _record_turn() -> void:
	var active = runner.state.get_active_player()
	_turns.append({"index":index,"time":duration,"turn":runner.state.turn_id,"generation":runner.state.generation,"player_id":active.player_id if active != null else ""})
func summary() -> Dictionary:
	if recorder == null: return {"ok":false,"reason":"not_started"}
	var players: Array = []
	for id in _players:
		var row: Dictionary = _players[id].duplicate(true)
		for metric in ["shots","hits","damage","kills"]: row[metric] = runner.statistics[id][metric] - _baseline[id][metric]
		players.append(row)
	return {"schema_version":1,"ok":finished and error.is_empty(),"reason":error if not error.is_empty() else ("complete" if finished else "in_progress"),"index":index,"action_count":recorder.data.actions.size(),"duration":duration,"action_types":_types.duplicate(),"players":players,"shots":_shots.duplicate(true),"turns":_turns.duplicate(true),"weapons":_weapons.values().duplicate(true),"eliminations":_eliminations.duplicate(true),"terrain":_terrain.duplicate(true),"initial_hash":_initial_hash,"final_hash":Replay.state_hash(runner) if finished and error.is_empty() else "","status":runner.state.status,"winner_team":runner.state.winner_team}
static func analyze(source: RefCounted) -> Dictionary:
	var analyzer: RefCounted = load("res://scripts/core/replay/replay_analyzer.gd").new()
	if not analyzer.begin(source): return {"ok":false,"reason":analyzer.error}
	while not analyzer.finished:
		var result: Dictionary = analyzer.step(4096)
		if not result.ok: return result
	return analyzer.summary()
static func compare(first: Dictionary, second: Dictionary) -> Dictionary:
	if not first.get("ok",false) or not second.get("ok",false): return {"ok":false,"reason":"invalid_analysis"}
	return {"ok":true,"schema_version":1,"same_initial":first.initial_hash==second.initial_hash,"same_final":first.final_hash==second.final_hash,"same_outcome":first.status==second.status and first.winner_team==second.winner_team,"duration_delta":second.duration-first.duration,"actions_delta":second.action_count-first.action_count,"shots_delta":second.shots.size()-first.shots.size()}
static func csv_cell(value: Variant) -> String:
	var text := str(value)
	if text.begins_with("=") or text.begins_with("+") or text.begins_with("-") or text.begins_with("@") or text.begins_with("\t") or text.begins_with("\r"): text = "'" + text
	return '"' + text.replace('"','""') + '"'
static func to_csv(report: Dictionary, table: String = "players") -> String:
	if not report.get("ok",false) or table not in ["players","shots"]: return ""
	var columns: Array = ["id","name","team","shots","hits","damage","kills","distance","active_time"] if table == "players" else ["index","time","player_id","weapon_id","turn_id","damage","kills","terrain_changes","terrain_destroyed"]
	var lines := PackedStringArray([",".join(columns)])
	for row in report[table]:
		var values := PackedStringArray()
		for key in columns: values.append(csv_cell(row.get(key,"")))
		lines.append(",".join(values))
	return "\r\n".join(lines) + "\r\n"

static func export_report(path: String, report: Dictionary, format: String = "json", replace: bool = false) -> Dictionary:
	if not report.get("ok",false) or format not in ["json","players","shots"]: return {"ok":false,"reason":"invalid_report"}
	var absolute := ProjectSettings.globalize_path(path)
	if not absolute.is_absolute_path(): absolute = DirAccess.open(".").get_current_dir().path_join(absolute)
	if not preload("res://scripts/core/storage/local_archive_library.gd").new()._safe_path(absolute): return {"ok":false,"reason":"unsafe_path"}
	if FileAccess.file_exists(path) and not replace: return {"ok":false,"reason":"output_exists"}
	var extension := "json" if format=="json" else "csv"
	if path.get_extension().to_lower()!=extension: return {"ok":false,"reason":"invalid_extension"}
	var content := JSON.stringify(report,"",true,true) if format=="json" else to_csv(report,format)
	var error_code: Error = preload("res://scripts/core/storage/local_archive_library.gd")._export_atomic(path,content)
	return {"ok":error_code==OK,"reason":"exported" if error_code==OK else error_string(error_code)}
