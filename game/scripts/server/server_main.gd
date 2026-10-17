extends Node
var transport: Node
func _ready() -> void:
	transport = load("res://scripts/networking/transport/match_server.gd").new()
	add_child(transport)
	var capacity := int(GameConfig.argument("--players", "2"))
	var require_ready := OS.get_cmdline_user_args().has("--lobby")
	var preset: String = GameConfig.argument("--preset", "classic")
	var error: Error = transport.start(int(GameConfig.argument("--port", "19170")), GameConfig.map_path(), preset, capacity, require_ready)
	if error != OK:
		push_error("Cannot start match server: %s" % error_string(error))
		get_tree().quit(1)
		return
	print("TerraBlast server ready; core players=%d map=%s preset=%s capacity=%d mode=%s" % [transport.runner.state.players.size(), GameConfig.argument("--map", "twin_forts"), preset, capacity, "lobby" if require_ready else "auto"])
	if OS.get_cmdline_user_args().has("--smoke"):
		for child in get_children():
			if child is Node3D or child is Control:
				get_tree().quit(1)
		get_tree().quit(0)
