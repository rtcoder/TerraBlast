extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2: quit(2); return
	if args[0] == "--studio-fixture":
		var base: String = args[1]
		var runner = load("res://scripts/core/rules/match_factory.gd").from_definition(load("res://scripts/core/workshop/workshop_document.gd").new().snapshot(),2)
		var recorder = load("res://scripts/core/replay/match_replay.gd").new()
		recorder.capture(runner)
		for index in 4: recorder.tick(runner,0.1)
		var result: Error = load("res://scripts/core/replay/replay_archive.gd").save(base.path_join("source.json"),recorder,runner)
		var library = load("res://scripts/core/storage/local_archive_library.gd").new(base.path_join("library"))
		var saved: Dictionary = library.save_replay("CLI fixture",recorder,runner)
		var bundle: Dictionary = load("res://scripts/core/storage/archive_bundle.gd").export_bundle(library,[saved.id],base.path_join("portable.zip"))
		quit(0 if result == OK and bundle.ok else 2)
		return
	if not FileAccess.file_exists("res://scripts/server/replay_studio_cli.gd"):
		print(JSON.stringify({"ok":false,"reason":"Replay Studio CLI executor missing"}))
		quit(2)
		return
	var result: Dictionary = load("res://scripts/server/replay_studio_cli.gd").run(args[0],JSON.parse_string(args[1]))
	print(JSON.stringify(result,"",true,true))
	quit(0 if result.ok else 2)
