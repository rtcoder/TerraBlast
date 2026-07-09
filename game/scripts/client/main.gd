extends Node3D

func _ready() -> void:
	print("%s booted in %s mode" % [GameConfig.GAME_NAME, GameConfig.mode])

