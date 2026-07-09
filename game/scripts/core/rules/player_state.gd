class_name PlayerState
extends RefCounted

var player_id: String = ""
var display_name: String = ""
var position: Vector3 = Vector3.ZERO
var rotation: Basis = Basis.IDENTITY
var health: int = 100
var is_alive: bool = true
var team_id: int = 0

func apply_damage(amount: int) -> void:
	health = max(0, health - amount)
	is_alive = health > 0

