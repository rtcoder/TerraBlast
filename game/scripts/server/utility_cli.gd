extends Node
## Non-gameplay CLI modes. No renderer or transport is instantiated.
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--help"):
		print("TerraBlast CLI\n--help | --version | --list-maps\n--mode local-dev|client|server|simulate|replay|audit-maps\n--map twin_forts|two_islands --preset classic|quick|training\n--players 2..10 --host HOST --port 1..65535 --guest-id ID\n--shots 1..1000 --seed 0..2147483647 --output PATH\n--bots easy|normal --record PATH (simulate only)\n--replay PATH --maps-dir DIRECTORY --smoke")
		get_tree().quit(0)
	elif args.has("--version"):
		print("%s %s / Godot %s" % [GameConfig.GAME_NAME, GameConfig.VERSION, Engine.get_version_info().string])
		get_tree().quit(0)
	elif args.has("--list-maps") or GameConfig.mode == "audit-maps":
		_list_maps()
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
			maps.append({"file": filename, "id": definition.id, "name": definition.display_name, "size": [definition.size.x, definition.size.y, definition.size.z], "spawn_count": definition.spawns.size(), "errors": errors})
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
