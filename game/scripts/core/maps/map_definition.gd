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
