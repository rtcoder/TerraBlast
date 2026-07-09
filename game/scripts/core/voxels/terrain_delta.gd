class_name TerrainDelta
extends RefCounted

var position: Vector3i
var material_id: int
var health: int

func _init(delta_position: Vector3i = Vector3i.ZERO, delta_material_id: int = 0, delta_health: int = 0) -> void:
	position = delta_position
	material_id = delta_material_id
	health = delta_health

