extends SceneTree
const Config = preload("res://scripts/shared/config/game_config.gd")
var failures := 0
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	check(Config.validate_args(["--mode", "server", "--map", "two_islands", "--port", "19170", "--players", "10"]).is_empty(), "Valid CLI")
	for args in [["--mode", "typo"], ["--mode"], ["--port", "0"], ["--port", "65536"], ["--port", "text"], ["--map", "missing"], ["--players", "11"], ["--players", "1"], ["--mode", "server", "--mode", "client"], ["--unknown"], ["--shots", "1001"], ["--seed", "-1"]]:
		check(not Config.validate_args(PackedStringArray(args)).is_empty(), "Reject invalid arguments: " + str(args))
	print("Config50 tests: %d failures" % failures)
	quit(1 if failures else 0)
