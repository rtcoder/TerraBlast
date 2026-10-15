extends Node
const GAME_NAME := "TerraBlast"
const VERSION := "0.0.1"
const DEFAULT_CHUNK_SIZE := 16
const DEFAULT_ARENA_SIZE := Vector3i(128, 64, 128)
const SIMULATION_TICK_RATE := 30
const MAPS := {"twin_forts": "res://maps/twin_forts.toml", "two_islands": "res://maps/two_islands.toml"}
var mode := "local-dev"
var errors: Array[String] = []
func _ready() -> void:
	mode = _read_mode_from_args()
	errors = validate_args(OS.get_cmdline_user_args())
func _read_mode_from_args() -> String:
	return argument("--mode", "server" if OS.has_feature("dedicated_server") else "local-dev")
func argument(flag: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	var index := args.find(flag)
	return args[index + 1] if index >= 0 and index + 1 < args.size() else fallback
func map_path() -> String:
	return MAPS.get(argument("--map", "twin_forts"), MAPS.twin_forts)
static func validate_args(args: PackedStringArray) -> Array[String]:
	var result: Array[String] = []
	var seen := {}
	var index := 0
	while index < args.size():
		var flag := args[index]
		if flag in ["--smoke", "--help", "--version", "--list-maps"]:
			index += 1
			continue
		if flag not in ["--mode", "--port", "--map", "--players", "--host", "--guest-id", "--shots", "--seed", "--output", "--replay", "--preset", "--maps-dir"]:
			result.append("Unknown argument: " + flag)
			index += 1
			continue
		if seen.has(flag):
			result.append("Duplicate argument: " + flag)
		seen[flag] = true
		if index + 1 >= args.size() or args[index + 1].begins_with("--"):
			result.append("Missing value for " + flag)
			index += 1
			continue
		var value := args[index + 1]
		match flag:
			"--mode":
				if value not in ["local-dev", "client", "server", "simulate", "replay", "audit-maps"]:
					result.append("Invalid mode: " + value)
			"--map":
				if not MAPS.has(value):
					result.append("Unknown map: " + value)
			"--port", "--players", "--shots", "--seed":
				var limits: Array = {"--port": [1, 65535], "--players": [2, 10], "--shots": [1, 1000], "--seed": [0, 2147483647]}[flag]
				if not value.is_valid_int() or value.to_int() < limits[0] or value.to_int() > limits[1]:
					result.append("Invalid numeric value for " + flag)
			"--preset":
				if value not in ["classic", "quick", "training"]:
					result.append("Unknown preset: " + value)
			"--host", "--guest-id", "--output", "--replay", "--maps-dir":
				if value.strip_edges().is_empty() or value.length() > 255:
					result.append("Invalid value for " + flag)
		index += 2
	return result
