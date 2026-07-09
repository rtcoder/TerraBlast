class_name DebugProjectile
extends Node3D

signal exploded(voxel_position: Vector3i)

@export var radius := 5
@export var damage := 150
@export var max_lifetime := 6.0

var voxel_world: Node3D
var velocity := Vector3.ZERO
var lifetime := 0.0
var previous_position := Vector3.ZERO
var is_finished := false

func _ready() -> void:
	previous_position = global_position
	_add_visual()

func launch(initial_velocity: Vector3, target_world: Node3D) -> void:
	velocity = initial_velocity
	voxel_world = target_world

func _physics_process(delta: float) -> void:
	if is_finished:
		return

	lifetime += delta
	previous_position = global_position
	velocity += Vector3.DOWN * 18.0 * delta
	global_position += velocity * delta

	var hit_voxel := _sweep_for_hit(previous_position, global_position)
	if hit_voxel.x >= 0:
		_finish(hit_voxel)
	elif lifetime >= max_lifetime or global_position.y < -8.0:
		_finish(Vector3i(floori(global_position.x), maxi(0, floori(global_position.y)), floori(global_position.z)))

func _sweep_for_hit(from_position: Vector3, to_position: Vector3) -> Vector3i:
	if voxel_world == null:
		return Vector3i(-1, -1, -1)

	var distance := from_position.distance_to(to_position)
	var steps: int = maxi(1, ceili(distance / 0.2))
	for step in range(steps + 1):
		var point := from_position.lerp(to_position, float(step) / float(steps))
		var voxel := Vector3i(floori(point.x), floori(point.y), floori(point.z))
		if voxel_world.world.is_in_bounds(voxel) and voxel_world.world.get_material_id(voxel) != 0:
			return voxel
	return Vector3i(-1, -1, -1)

func _finish(voxel_position: Vector3i) -> void:
	is_finished = true
	exploded.emit(voxel_position)
	queue_free()

func _add_visual() -> void:
	var mesh_instance := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.35
	sphere.height = 0.7
	mesh_instance.mesh = sphere

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.38, 0.16)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.22, 0.06)
	material.emission_energy_multiplier = 0.8
	mesh_instance.material_override = material
	add_child(mesh_instance)

