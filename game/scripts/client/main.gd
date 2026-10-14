extends Node
func _ready() -> void:
	var path := "res://scenes/server/ServerMain.tscn" if GameConfig.mode == "server" else "res://scenes/debug/VoxelDebug.tscn"
	get_tree().change_scene_to_file.call_deferred(path)
