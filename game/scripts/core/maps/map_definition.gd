class_name MapDefinition
extends RefCounted

var id: String = ""
var display_name: String = ""
var size: Vector3i = Vector3i(96, 24, 96)
var theme: String = ""
var spawns: Array[Dictionary] = []
var boxes: Array[Dictionary] = []
var carves: Array[Dictionary] = []


var errors: Array[String] = []

func copy() -> RefCounted:
	var result = get_script().new()
	result.id = id
	result.display_name = display_name
	result.size = size
	result.theme = theme
	result.spawns = spawns.duplicate(true)
	result.boxes = boxes.duplicate(true)
	result.carves = carves.duplicate(true)
	result.errors = errors.duplicate()
	return result
