extends Node

const GAME_NAME := "TerraBlast"
const VERSION := "0.0.1"
const DEFAULT_CHUNK_SIZE := 16
const DEFAULT_ARENA_SIZE := Vector3i(128, 64, 128)
const SIMULATION_TICK_RATE := 30

var mode: String = "local-dev"

func _ready() -> void:
	mode = _read_mode_from_args()

func _read_mode_from_args() -> String:
	var args := OS.get_cmdline_user_args()
	for index in args.size():
		if args[index] == "--mode" and index + 1 < args.size():
			return args[index + 1]
	return mode

