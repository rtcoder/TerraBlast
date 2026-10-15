extends SceneTree
var failures := 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var config = load("res://scripts/shared/config/game_config.gd")
	for args in [["--help"], ["--version"], ["--list-maps"], ["--mode", "replay", "--replay", "file.json"], ["--preset", "training"]]:
		check(config.validate_args(PackedStringArray(args)).is_empty(), "Valid CLI arguments rejected")
	for args in [["--output"], ["--preset", "bad"], ["--mode", "replay", "--mode", "server"], ["--players", "nan"]]:
		check(not config.validate_args(PackedStringArray(args)).is_empty(), "Invalid CLI arguments accepted")
	var exports := ConfigFile.new()
	check(exports.load("res://export_presets.cfg") == OK, "Export presets missing or invalid")
	for index in 4:
		check(exports.has_section("preset.%d" % index), "Export platform missing")
		check(exports.get_value("preset.%d" % index, "include_filter", "").contains("toml"), "Export must include TOML arenas")
	check(exports.get_value("preset.3", "dedicated_server", false), "Server export must be dedicated")
	var runner = load("res://scripts/core/rules/match_factory.gd").create_match(2)
	var replay = load("res://scripts/core/replay/match_replay.gd").new()
	replay.capture(runner)
	var output := ""
	var args := OS.get_cmdline_user_args()
	var index := args.find("--output")
	if index >= 0 and index + 1 < args.size():
		output = args[index + 1]
	if not output.is_empty():
		check(load("res://scripts/core/replay/replay_archive.gd").save(output, replay, runner) == OK, "Replay fixture creation failed")
	print("Devtools unit checks: %d failures" % failures)
	quit(1 if failures else 0)
