extends Node
func _ready() -> void:
	if not GameConfig.errors.is_empty():
		printerr("Invalid arguments: " + "; ".join(GameConfig.errors))
		get_tree().quit(2)
		return
	if OS.get_cmdline_user_args().has("--help") or OS.get_cmdline_user_args().has("--version") or OS.get_cmdline_user_args().has("--list-maps") or GameConfig.mode in ["replay", "audit-maps", "library"]:
		add_child(load("res://scripts/server/utility_cli.gd").new())
		return
	if GameConfig.mode == "simulate":
		var simulation = load("res://scripts/server/simulation_cli.gd").new()
		add_child(simulation)
		return
	var path := "res://scenes/server/ServerMain.tscn" if GameConfig.mode == "server" else "res://scenes/debug/VoxelDebug.tscn"
	get_tree().change_scene_to_file.call_deferred(path)
