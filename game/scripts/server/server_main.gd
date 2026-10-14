extends Node
var transport: Node
func _ready() -> void:
	transport = load("res://scripts/networking/transport/match_server.gd").new()
	add_child(transport)
	var error: Error = transport.start(int(GameConfig.argument("--port", "19170")), GameConfig.map_path())
	if error != OK:
		push_error("Cannot bind match server: %s" % error_string(error))
		get_tree().quit(1)
		return
	print("TerraBlast server ready; core players=%d" % transport.runner.state.players.size())
	if OS.get_cmdline_user_args().has("--smoke"):
		for child in get_children():
			if child is Node3D or child is Control:
				get_tree().quit(1)
		get_tree().quit(0)
