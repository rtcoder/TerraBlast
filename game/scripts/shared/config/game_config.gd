extends Node
const GAME_NAME := "TerraBlast"
const VERSION := "0.0.1"
const DEFAULT_CHUNK_SIZE := 16
const DEFAULT_ARENA_SIZE := Vector3i(128, 64, 128)
const SIMULATION_TICK_RATE := 30
const MapRegistry = preload("res://scripts/core/maps/map_registry.gd")
const MAPS = MapRegistry.PATHS
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
		if flag in ["--smoke", "--help", "--version", "--list-maps", "--lobby", "--verify-library", "--library-health", "--lobby-chat", "--print-roster"]:
			if seen.has(flag):
				result.append("Duplicate argument: " + flag)
			seen[flag] = true
			index += 1
			continue
		if flag not in ["--mode", "--port", "--map", "--players", "--host", "--guest-id", "--shots", "--seed", "--output", "--replay", "--preset", "--maps-dir", "--bots", "--record", "--library-dir", "--query", "--sort", "--entry", "--replay-other", "--analysis-format", "--reservation-seconds", "--hello-seconds", "--packet-rate", "--byte-rate", "--snapshot-chunks", "--snapshot-bytes", "--receive-bytes", "--server-report", "--shutdown-after", "--role", "--spectators", "--clip-start", "--clip-end", "--bundle"]:
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
				if value not in ["local-dev", "client", "server", "simulate", "replay", "audit-maps", "library", "analyze-replay", "compare-replays", "clip-replay", "diff-replays", "verify-bundle"]:
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
			"--reservation-seconds", "--hello-seconds", "--shutdown-after":
				var limits: Array = {"--reservation-seconds":[1.0,300.0],"--hello-seconds":[1.0,30.0],"--shutdown-after":[0.1,3600.0]}[flag]
				if not value.is_valid_float() or not is_finite(value.to_float()) or value.to_float()<limits[0] or value.to_float()>limits[1]: result.append("Invalid value for " + flag)
			"--packet-rate", "--byte-rate", "--snapshot-chunks", "--snapshot-bytes", "--receive-bytes":
				var limits: Array = {"--packet-rate":[60,1000],"--byte-rate":[8192,1048576],"--snapshot-chunks":[1,64],"--snapshot-bytes":[65536,8388608],"--receive-bytes":[8192,4194304]}[flag]
				if not value.is_valid_int() or value.to_int()<limits[0] or value.to_int()>limits[1]: result.append("Invalid value for " + flag)
			"--clip-start", "--clip-end":
				if not value.is_valid_int() or value.to_int()<0 or value.to_int()>100000: result.append("Invalid clip action index")
			"--role":
				if value not in ["player","spectator"]: result.append("Invalid role")
			"--spectators":
				if not value.is_valid_int() or value.to_int()<0 or value.to_int()>6: result.append("Invalid spectator capacity")
			"--sort":
				if value not in ["newest","oldest","title","kind"]: result.append("Invalid sort")
			"--analysis-format":
				if value not in ["json","players","shots"]: result.append("Invalid analysis format")
			"--bots":
				if value not in ["easy", "normal"]:
					result.append("Unknown bot difficulty: " + value)
			"--host", "--guest-id", "--output", "--replay", "--maps-dir", "--record", "--library-dir", "--query", "--entry", "--replay-other", "--server-report", "--bundle":
				if value.strip_edges().is_empty() or value.length() > 255:
					result.append("Invalid value for " + flag)
		index += 2
	var mode_index := args.find("--mode")
	var selected_mode := args[mode_index + 1] if mode_index >= 0 and mode_index + 1 < args.size() else ("server" if OS.has_feature("dedicated_server") else "local-dev")
	if seen.has("--role") and selected_mode != "client": result.append("--role requires client mode")
	for flag in ["--spectators","--lobby-chat","--print-roster"]:
		if seen.has(flag) and selected_mode != "server": result.append(flag + " requires server mode")
	if seen.has("--lobby") and selected_mode != "server":
		result.append("--lobby requires --mode server")
	for flag in ["--bots", "--record"]:
		if seen.has(flag) and selected_mode != "simulate":
			result.append(flag + " requires --mode simulate")
	for flag in ["--library-dir", "--verify-library", "--library-health"]:
		if seen.has(flag) and selected_mode != "library": result.append(flag + " requires --mode library")
	if seen.has("--replay-other") and selected_mode not in ["compare-replays","diff-replays"]: result.append("--replay-other requires compare-replays or diff-replays")
	if seen.has("--analysis-format") and selected_mode != "analyze-replay": result.append("--analysis-format requires analyze-replay")
	for flag in ["--reservation-seconds","--hello-seconds","--packet-rate","--byte-rate","--snapshot-chunks","--snapshot-bytes","--receive-bytes","--server-report","--shutdown-after"]:
		if seen.has(flag) and selected_mode != "server": result.append(flag + " requires server mode")
	for flag in ["--clip-start","--clip-end"]:
		if seen.has(flag) and selected_mode != "clip-replay": result.append(flag + " requires clip-replay")
	if seen.has("--bundle") and selected_mode != "verify-bundle": result.append("--bundle requires verify-bundle")
	var record_index := args.find("--record")
	var output_index := args.find("--output")
	if record_index >= 0 and output_index >= 0 and record_index + 1 < args.size() and output_index + 1 < args.size():
		var record_path := _absolute_output_path(args[record_index + 1])
		var output_path := _absolute_output_path(args[output_index + 1])
		if record_path == output_path:
			result.append("--record and --output must use different paths")
	return result

static func _absolute_output_path(path: String) -> String:
	var expanded := ProjectSettings.globalize_path(path)
	if not expanded.is_absolute_path():
		expanded = DirAccess.open(".").get_current_dir().path_join(expanded)
	return expanded.simplify_path()
