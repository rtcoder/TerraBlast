class_name SpawnPoint
extends RefCounted

var position: Vector3i
var team: int
var slot: int
var yaw: float

func _init(spawn_position: Vector3i = Vector3i.ZERO, spawn_team: int = 1, spawn_slot: int = 0, spawn_yaw: float = 0.0) -> void:
	position = spawn_position
	team = spawn_team
	slot = spawn_slot
	yaw = spawn_yaw
