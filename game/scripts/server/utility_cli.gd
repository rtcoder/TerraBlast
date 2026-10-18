extends Node
## Non-gameplay CLI modes. No renderer or transport is instantiated.
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--help"):
		print("TerraBlast CLI\n--help | --version | --list-maps\n--mode local-dev|client|server|simulate|replay|audit-maps|library|analyze-replay|compare-replays\n--map REGISTERED_ID (e.g. canyon_bridge; see --list-maps) --preset classic|quick|training\n--players 2..10 --lobby (server only; server defaults to 2 players)\n--host HOST --port 1..65535 --guest-id ID\n--shots 1..1000 --seed 0..2147483647 --output PATH\n--bots easy|normal --record PATH (simulate only)\n--replay PATH --maps-dir DIRECTORY --smoke\n--mode library --library-dir DIRECTORY [--verify-library] [--query TEXT --sort newest|oldest|title|kind]\n--entry ID --library-health\n--mode analyze-replay --replay PATH [--output PATH --analysis-format json|players|shots]\n--mode compare-replays --replay PATH --replay-other PATH\nServer: --reservation-seconds 1..300 --hello-seconds 1..30\n--packet-rate 60..1000 --byte-rate 8192..1048576\n--snapshot-chunks 1..64 --snapshot-bytes 65536..8388608 --receive-bytes 8192..4194304\n--shutdown-after 0.1..3600 --server-report /absolute/report.json")
		get_tree().quit(0)
	elif args.has("--version"):
		print("%s %s / Godot %s" % [GameConfig.GAME_NAME, GameConfig.VERSION, Engine.get_version_info().string])
		get_tree().quit(0)
	elif args.has("--list-maps") or GameConfig.mode == "audit-maps":
		_list_maps()
	elif GameConfig.mode in ["analyze-replay","compare-replays"]:
		_analyze_replay()
	elif GameConfig.mode == "library":
		_list_library(args.has("--verify-library"))
	else:
		var path: String = GameConfig.argument("--replay", "")
		if path.is_empty():
			print(JSON.stringify({"ok": false, "reason": "Missing --replay path"}))
			get_tree().quit(2)
			return
		var result: Dictionary = load("res://scripts/core/replay/replay_archive.gd").load_verified(path)
		var summary := {"ok": result.ok, "reason": result.get("reason", "")}
		if result.ok:
			summary.state = result.runner.state_snapshot()
		print(JSON.stringify(summary))
		get_tree().quit(0 if result.ok else 2)

func _list_maps() -> void:
	var path: String = GameConfig.argument("--maps-dir", "res://maps")
	var directory := DirAccess.open(path)
	var maps := []
	var ok := directory != null
	if directory != null:
		for filename in directory.get_files():
			if filename.get_extension() != "toml":
				continue
			var definition = load("res://scripts/core/maps/map_loader.gd").load_from_file(path.path_join(filename))
			var errors: Array[String] = load("res://scripts/core/maps/map_validator.gd").validate_definition(definition)
			if errors.is_empty():
				var world = load("res://scripts/core/voxels/voxel_world_data.gd").new(definition.size)
				var materials: Dictionary = load("res://scripts/core/maps/arena_generator.gd").materials()
				load("res://scripts/core/maps/map_builder.gd").apply_to_world(world, materials, definition)
				errors = load("res://scripts/core/maps/map_validator.gd").validate(definition, world)
			var teams: Array[int] = []
			for spawn in definition.spawns:
				var team := int(spawn.get("team", 0))
				if not teams.has(team):
					teams.append(team)
			teams.sort()
			maps.append({"file": filename, "id": definition.id, "name": definition.display_name, "size": [definition.size.x, definition.size.y, definition.size.z], "theme": definition.theme, "teams": teams, "capacity": mini(definition.spawns.size(), 10), "spawn_count": definition.spawns.size(), "errors": errors})
			ok = ok and errors.is_empty()
	ok = ok and not maps.is_empty()
	print(JSON.stringify({"ok": ok, "maps": maps, "reason": "" if ok else "Missing directory, no maps, or invalid maps"}))
	get_tree().quit(0 if ok else 2)

static func write_atomic(path: String, content: String) -> Error:
	var temporary := path + ".tmp-%d" % OS.get_process_id()
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(content + "\n")
	file.flush()
	var error := file.get_error()
	file.close()
	if error == OK:
		error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		DirAccess.remove_absolute(temporary)
	return error

func _list_library(verify: bool) -> void:
	var path: String = GameConfig.argument("--library-dir", "user://archive_library")
	var library = load("res://scripts/core/storage/local_archive_library.gd").new(path)
	if OS.get_cmdline_user_args().has("--library-health"):
		var health: Dictionary = library.health_report()
		print(JSON.stringify(health))
		get_tree().quit(0 if health.ok else 2)
		return
	var selected_entry: String = GameConfig.argument("--entry","")
	if not selected_entry.is_empty():
		var preview: Dictionary = library.preview(selected_entry)
		print(JSON.stringify(preview))
		get_tree().quit(0 if preview.ok else 2)
		return
	var listing: Dictionary = library.query({"query":GameConfig.argument("--query",""),"sort":GameConfig.argument("--sort","newest")})
	var summary := {"ok":listing.ok, "entries":listing.get("entries",[]), "errors":listing.get("errors",[]), "reason":listing.get("reason", ""), "verified":verify}
	if not summary.errors.is_empty(): summary.ok = false
	if verify and listing.ok:
		for entry in summary.entries:
			var loaded: Dictionary = library.load_entry(entry.id)
			entry["verified"] = loaded.ok
			if not loaded.ok:
				summary.ok = false
				summary.errors.append({"id":entry.id,"reason":loaded.get("reason","Invalid entry")})
	print(JSON.stringify(summary))
	get_tree().quit(0 if summary.ok else 2)

func _analyze_replay() -> void:
	var path: String = GameConfig.argument("--replay","")
	var archive = load("res://scripts/core/replay/replay_archive.gd")
	var analyzer = load("res://scripts/core/replay/replay_analyzer.gd")
	var loaded: Dictionary = archive.load_verified(path)
	var result: Dictionary = {"ok":false,"reason":loaded.get("reason","invalid_archive")}
	if loaded.ok: result = analyzer.analyze(loaded.recorder)
	if GameConfig.mode=="compare-replays" and result.ok:
		var second: Dictionary = archive.load_verified(GameConfig.argument("--replay-other",""))
		result = analyzer.compare(result,analyzer.analyze(second.recorder)) if second.ok else {"ok":false,"reason":second.get("reason","invalid_archive")}
	var output: String = GameConfig.argument("--output","")
	if result.ok and not output.is_empty():
		var first_path: String = GameConfig._absolute_output_path(path)
		var second_path: String = GameConfig._absolute_output_path(GameConfig.argument("--replay-other",""))
		var output_path: String = GameConfig._absolute_output_path(output)
		if not load("res://scripts/core/storage/local_archive_library.gd").new()._safe_path(output_path):
			result = {"ok":false,"reason":"unsafe_output_path"}
		elif output_path==first_path or output_path==second_path:
			result = {"ok":false,"reason":"output_overlaps_input"}
		else:
			var content: String = JSON.stringify(result,"",true,true)
			var format: String = GameConfig.argument("--analysis-format","json")
			if format!="json": content = analyzer.to_csv(result,format)
			var error: Error = write_atomic(output,content)
			if error!=OK: result = {"ok":false,"reason":error_string(error)}
	print(JSON.stringify(result,"",true,true))
	get_tree().quit(0 if result.ok else 2)
