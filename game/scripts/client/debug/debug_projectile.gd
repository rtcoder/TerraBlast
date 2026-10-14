class_name DebugProjectile
extends Node3D

signal finished
var points := PackedVector3Array()
var elapsed := 0.0
var step := 1.0 / 30.0
var is_finished := false

func _ready() -> void:
	var visual := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.25
	sphere.height = 0.5
	visual.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.ORANGE
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visual.material_override = material
	add_child(visual)

func play_path(path: PackedVector3Array, tick_step: float) -> void:
	points = path
	step = tick_step
	if not points.is_empty():
		global_position = points[0]

func _physics_process(delta: float) -> void:
	if is_finished or points.is_empty():
		return
	elapsed += delta
	var sample := elapsed / step
	var index := mini(int(sample), points.size() - 1)
	global_position = points[index].lerp(points[mini(index + 1, points.size() - 1)], fmod(sample, 1.0))
	if index >= points.size() - 1:
		is_finished = true
		finished.emit()
		queue_free()
