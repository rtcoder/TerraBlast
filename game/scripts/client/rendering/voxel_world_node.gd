class_name VoxelWorldNode
extends Node3D

const VoxelDestruction := preload("res://scripts/core/terrain/voxel_destruction.gd")
const VoxelWorldData := preload("res://scripts/core/voxels/voxel_world_data.gd")
const VoxelChunkMeshBuilder := preload("res://scripts/client/rendering/voxel_chunk_mesh_builder.gd")

@export var world_size := Vector3i(96, 24, 96)
@export var chunk_size := 16
@export var flat_floor_height := 3
@export_file("*.toml") var map_path := "res://maps/twin_forts.toml"

var world: RefCounted
var material_configs: Dictionary = {}
var dirty_chunks: Dictionary = {}
var chunk_nodes: Dictionary = {}
var terrain_material: StandardMaterial3D
var last_dirty_chunk_count := 0
var last_rebuilt_chunk_count := 0
var total_mesh_count := 0

func _ready() -> void:
	_setup_material()
	if world == null:
		_setup_world()
	rebuild_dirty_chunks()

func apply_debug_explosion(center: Vector3i, radius: int = 5, damage: int = 140) -> Array:
	var destruction := VoxelDestruction.new(world, material_configs)
	var deltas: Array = destruction.apply_explosion(center, radius, damage)
	for delta: Variant in deltas:
		mark_voxel_dirty(delta.position)
	rebuild_dirty_chunks()
	return deltas

func get_first_solid_on_ray(origin: Vector3, direction: Vector3, max_distance: float = 120.0, step: float = 0.25) -> Vector3i:
	var distance := 0.0
	while distance <= max_distance:
		var point := origin + direction * distance
		var voxel := Vector3i(floori(point.x), floori(point.y), floori(point.z))
		if world.is_in_bounds(voxel) and world.get_material_id(voxel) != 0:
			return voxel
		distance += step
	return Vector3i(-1, -1, -1)

func get_surface_world_position(x: int, z: int) -> Vector3:
	return Vector3(float(x) + 0.5, get_surface_y(x, z), float(z) + 0.5)

func get_surface_y(x: int, z: int) -> float:
	for y in range(world_size.y - 1, -1, -1):
		var voxel := Vector3i(x, y, z)
		if world.is_in_bounds(voxel) and world.get_material_id(voxel) != 0:
			return float(y) + 1.0
	return 1.0

func mark_chunk_dirty(chunk_position: Vector3i) -> void:
	dirty_chunks[chunk_position] = true

func mark_voxel_dirty(position: Vector3i) -> void:
	if world == null or not world.is_in_bounds(position):
		return
	mark_chunk_dirty(world.get_chunk_position(position))
	for direction in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]:
		var neighbor: Vector3i = position + direction
		if world.is_in_bounds(neighbor) and world.get_chunk_position(neighbor) != world.get_chunk_position(position):
			mark_chunk_dirty(world.get_chunk_position(neighbor))

func rebuild_dirty_chunks() -> void:
	last_dirty_chunk_count = dirty_chunks.size()
	last_rebuilt_chunk_count = 0
	for chunk_position: Vector3i in dirty_chunks.keys():
		_rebuild_chunk(chunk_position)
		last_rebuilt_chunk_count += 1
	dirty_chunks.clear()
	total_mesh_count = 0
	for mesh_instance: MeshInstance3D in chunk_nodes.values():
		if mesh_instance.mesh != null and mesh_instance.mesh.get_surface_count() > 0:
			total_mesh_count += 1

func set_world(new_world: RefCounted, materials: Dictionary) -> void:
	for mesh_instance: MeshInstance3D in chunk_nodes.values():
		remove_child(mesh_instance)
		mesh_instance.queue_free()
	chunk_nodes.clear()
	dirty_chunks.clear()
	world = new_world
	material_configs = materials
	world_size = world.size
	chunk_size = world.chunk_size
	if terrain_material == null:
		_setup_material()
	_mark_all_chunks_dirty()
	rebuild_dirty_chunks()

func _setup_material() -> void:
	terrain_material = StandardMaterial3D.new()
	terrain_material.albedo_color = Color.WHITE
	terrain_material.vertex_color_use_as_albedo = true
	terrain_material.roughness = 0.85
	terrain_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	terrain_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED

func _setup_world() -> void:
	var generator = load("res://scripts/core/maps/arena_generator.gd")
	if not map_path.is_empty():
		var arena: Dictionary = generator.generate(map_path, chunk_size)
		if arena.errors.is_empty():
			world = arena.world
			material_configs = arena.materials
			world_size = world.size
			_mark_all_chunks_dirty()
			return
		for error: String in arena.errors:
			push_error("Map validation failed: %s" % error)
	world = VoxelWorldData.new(world_size, chunk_size)
	material_configs = generator.materials()
	_generate_debug_arena()
	_mark_all_chunks_dirty()

func _generate_debug_arena() -> void:
	for z in range(world_size.z):
		for x in range(world_size.x):
			for y in range(flat_floor_height):
				var material_id := 1
				var health := 100
				if y < 2:
					material_id = 2
					health = 180
				world.set_voxel(Vector3i(x, y, z), material_id, health)

func _mark_all_chunks_dirty() -> void:
	var chunk_counts := Vector3i(
		ceili(float(world_size.x) / float(chunk_size)),
		ceili(float(world_size.y) / float(chunk_size)),
		ceili(float(world_size.z) / float(chunk_size))
	)
	for z in range(chunk_counts.z):
		for y in range(chunk_counts.y):
			for x in range(chunk_counts.x):
				mark_chunk_dirty(Vector3i(x, y, z))

func _rebuild_chunk(chunk_position: Vector3i) -> void:
	var mesh := VoxelChunkMeshBuilder.build_mesh(world, chunk_position, material_configs, chunk_size)
	var mesh_instance: MeshInstance3D = chunk_nodes.get(chunk_position)
	if mesh_instance == null:
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "Chunk_%d_%d_%d" % [chunk_position.x, chunk_position.y, chunk_position.z]
		mesh_instance.material_override = terrain_material
		add_child(mesh_instance)
		chunk_nodes[chunk_position] = mesh_instance
	mesh_instance.mesh = mesh

func refresh_deltas(deltas: Array) -> void:
	for delta in deltas:
		var position: Variant = delta.position
		var pos: Vector3i = position if position is Vector3i else Vector3i(position[0], position[1], position[2])
		mark_voxel_dirty(pos)
	rebuild_dirty_chunks()
