extends SceneTree

const ChunkPosition := preload("res://scripts/core/chunks/chunk_position.gd")
const VoxelDestruction := preload("res://scripts/core/terrain/voxel_destruction.gd")
const VoxelMaterialConfig := preload("res://scripts/core/voxels/voxel_material_config.gd")
const VoxelPosition := preload("res://scripts/core/voxels/voxel_position.gd")
const VoxelWorldData := preload("res://scripts/core/voxels/voxel_world_data.gd")
const VoxelChunkMeshBuilder := preload("res://scripts/client/rendering/voxel_chunk_mesh_builder.gd")
const MapBuilder := preload("res://scripts/core/maps/map_builder.gd")
const MapLoader := preload("res://scripts/core/maps/map_loader.gd")
const MapValidator := preload("res://scripts/core/maps/map_validator.gd")
const PlayerActionCommand := preload("res://scripts/core/turns/player_action_command.gd")
const PlayerState := preload("res://scripts/core/rules/player_state.gd")
const TurnController := preload("res://scripts/core/turns/turn_controller.gd")

var failures: Array[String] = []

func _initialize() -> void:
	_test_world_to_voxel_position()
	_test_voxel_to_chunk_position()
	_test_local_position_in_chunk()
	_test_bounds_checking()
	_test_explosion_radius_zero_affects_center()
	_test_explosion_outside_world_does_not_crash()
	_test_explosion_ignores_indestructible_material()
	_test_terrain_delta_contains_final_values()
	_test_single_voxel_mesh_has_six_faces()
	_test_adjacent_voxels_do_not_mesh_internal_face()
	_test_dirt_top_and_side_faces_have_minecraft_colors()
	_test_grass_top_has_visible_color_variation()
	_test_toml_map_loads_into_definition()
	_test_map_builder_applies_boxes_and_carves()
	_test_map_validator_accepts_twin_forts_spawns()
	_test_turn_controller_rejects_inactive_player()
	_test_turn_controller_clamps_shot_power()
	_test_turn_controller_skips_dead_player()

	if failures.is_empty():
		print("Core tests passed")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])

func _expect_true(value: bool, label: String) -> void:
	if not value:
		failures.append("%s: expected true" % label)

func _default_materials() -> Dictionary:
	return {
		0: _material(0, "air", "Air", 0, 1.0, false, false),
		1: _material(1, "dirt", "Dirt", 100, 1.0, true, true),
		2: _material(2, "stone", "Stone", 180, 2.0, true, true),
		3: _material(3, "metal", "Metal", 255, 4.0, true, false),
	}

func _material(id: int, code: String, display_name: String, max_health: int, blast_resistance: float, is_solid: bool, is_destructible: bool) -> Resource:
	var material: Resource = VoxelMaterialConfig.new()
	material.id = id
	material.code = code
	material.display_name = display_name
	material.max_health = max_health
	material.blast_resistance = blast_resistance
	material.is_solid = is_solid
	material.is_destructible = is_destructible
	return material

func _test_world_to_voxel_position() -> void:
	_expect_equal(VoxelPosition.from_world(Vector3(1.2, 3.9, 4.0)), Vector3i(1, 3, 4), "world to voxel floors positive coordinates")
	_expect_equal(VoxelPosition.from_world(Vector3(-0.1, 0.0, 2.0)), Vector3i(-1, 0, 2), "world to voxel floors negative coordinates")

func _test_voxel_to_chunk_position() -> void:
	_expect_equal(ChunkPosition.from_voxel(Vector3i(0, 0, 0)), Vector3i(0, 0, 0), "origin chunk")
	_expect_equal(ChunkPosition.from_voxel(Vector3i(16, 31, 32)), Vector3i(1, 1, 2), "positive chunk")
	_expect_equal(ChunkPosition.from_voxel(Vector3i(-1, 0, -16)), Vector3i(-1, 0, -1), "negative chunk")

func _test_local_position_in_chunk() -> void:
	_expect_equal(ChunkPosition.local_from_voxel(Vector3i(16, 31, 32)), Vector3i(0, 15, 0), "positive local chunk position")
	_expect_equal(ChunkPosition.local_from_voxel(Vector3i(-1, 0, -17)), Vector3i(15, 0, 15), "negative local chunk position")

func _test_bounds_checking() -> void:
	var world := VoxelWorldData.new(Vector3i(4, 4, 4))
	_expect_true(world.is_in_bounds(Vector3i(0, 0, 0)), "origin is in bounds")
	_expect_true(world.is_in_bounds(Vector3i(3, 3, 3)), "max inclusive coordinate is in bounds")
	_expect_equal(world.is_in_bounds(Vector3i(4, 0, 0)), false, "x size is outside")
	_expect_equal(world.is_in_bounds(Vector3i(-1, 0, 0)), false, "negative x is outside")

func _test_explosion_radius_zero_affects_center() -> void:
	var world := VoxelWorldData.new(Vector3i(4, 4, 4))
	world.set_voxel(Vector3i(2, 2, 2), 1, 100)
	world.set_voxel(Vector3i(2, 2, 3), 1, 100)
	var destruction := VoxelDestruction.new(world, _default_materials())
	var deltas := destruction.apply_explosion(Vector3i(2, 2, 2), 0, 100)
	_expect_equal(deltas.size(), 1, "radius zero delta count")
	_expect_equal(world.get_material_id(Vector3i(2, 2, 2)), 0, "radius zero removes center")
	_expect_equal(world.get_material_id(Vector3i(2, 2, 3)), 1, "radius zero leaves neighbor")

func _test_explosion_outside_world_does_not_crash() -> void:
	var world := VoxelWorldData.new(Vector3i(2, 2, 2))
	var destruction := VoxelDestruction.new(world, _default_materials())
	var deltas := destruction.apply_explosion(Vector3i(20, 20, 20), 4, 100)
	_expect_equal(deltas.size(), 0, "outside explosion has no deltas")

func _test_explosion_ignores_indestructible_material() -> void:
	var world := VoxelWorldData.new(Vector3i(4, 4, 4))
	world.set_voxel(Vector3i(1, 1, 1), 3, 255)
	var destruction := VoxelDestruction.new(world, _default_materials())
	var deltas := destruction.apply_explosion(Vector3i(1, 1, 1), 1, 999)
	_expect_equal(deltas.size(), 0, "indestructible material has no deltas")
	_expect_equal(world.get_material_id(Vector3i(1, 1, 1)), 3, "indestructible material remains")
	_expect_equal(world.get_health(Vector3i(1, 1, 1)), 255, "indestructible health remains")

func _test_terrain_delta_contains_final_values() -> void:
	var world := VoxelWorldData.new(Vector3i(4, 4, 4))
	world.set_voxel(Vector3i(1, 1, 1), 1, 100)
	var destruction := VoxelDestruction.new(world, _default_materials())
	var deltas := destruction.apply_explosion(Vector3i(1, 1, 1), 1, 40)
	_expect_equal(deltas.size(), 1, "partial damage delta count")
	_expect_equal(deltas[0].position, Vector3i(1, 1, 1), "delta position")
	_expect_equal(deltas[0].material_id, 1, "delta material after partial damage")
	_expect_equal(deltas[0].health, 60, "delta health after partial damage")

func _test_single_voxel_mesh_has_six_faces() -> void:
	var world := VoxelWorldData.new(Vector3i(4, 4, 4))
	world.set_voxel(Vector3i(1, 1, 1), 1, 100)
	var mesh: ArrayMesh = VoxelChunkMeshBuilder.build_mesh(world, Vector3i.ZERO, _default_materials(), 16)
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	_expect_equal(vertices.size(), 24, "single voxel visible vertices")
	_expect_equal(indices.size(), 36, "single voxel visible indices")

func _test_adjacent_voxels_do_not_mesh_internal_face() -> void:
	var world := VoxelWorldData.new(Vector3i(4, 4, 4))
	world.set_voxel(Vector3i(1, 1, 1), 1, 100)
	world.set_voxel(Vector3i(2, 1, 1), 1, 100)
	var mesh: ArrayMesh = VoxelChunkMeshBuilder.build_mesh(world, Vector3i.ZERO, _default_materials(), 16)
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	_expect_equal(vertices.size(), 40, "two adjacent voxels visible vertices")
	_expect_equal(indices.size(), 60, "two adjacent voxels visible indices")

func _test_dirt_top_and_side_faces_have_minecraft_colors() -> void:
	var world := VoxelWorldData.new(Vector3i(4, 4, 4))
	world.set_voxel(Vector3i(1, 1, 1), 1, 100)
	var mesh: ArrayMesh = VoxelChunkMeshBuilder.build_mesh(world, Vector3i.ZERO, _default_materials(), 16)
	var arrays := mesh.surface_get_arrays(0)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var top_color := Color.BLACK
	var side_color := Color.BLACK

	for index in range(normals.size()):
		if normals[index].distance_to(Vector3.UP) < 0.01:
			top_color = colors[index]
		elif normals[index].distance_to(Vector3.RIGHT) < 0.01:
			side_color = colors[index]

	_expect_true(top_color.g > top_color.r, "dirt top face is grass green")
	_expect_true(side_color.r > side_color.g, "dirt side face is brown")
	_expect_true(top_color != side_color, "dirt top and side colors differ")

func _test_grass_top_has_visible_color_variation() -> void:
	var world := VoxelWorldData.new(Vector3i(4, 4, 4))
	world.set_voxel(Vector3i(1, 1, 1), 1, 100)
	world.set_voxel(Vector3i(2, 1, 1), 1, 100)
	var mesh: ArrayMesh = VoxelChunkMeshBuilder.build_mesh(world, Vector3i.ZERO, _default_materials(), 16)
	var arrays := mesh.surface_get_arrays(0)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var top_colors: Dictionary = {}

	for index in range(normals.size()):
		if normals[index].distance_to(Vector3.UP) < 0.01:
			top_colors[colors[index]] = true

	_expect_true(top_colors.size() >= 2, "grass top has minecraft-style color variation")

func _test_toml_map_loads_into_definition() -> void:
	var definition: RefCounted = MapLoader.load_from_file("res://maps/twin_forts.toml")
	_expect_equal(definition.id, "twin_forts", "map loader reads id")
	_expect_equal(definition.size, Vector3i(96, 24, 96), "map loader reads world size")
	_expect_equal(definition.spawns.size(), 10, "map loader reads spawn list")
	_expect_equal(definition.boxes.size() > 0, true, "map loader reads box primitives")
	_expect_equal(definition.carves.size() > 0, true, "map loader reads carve primitives")

func _test_map_builder_applies_boxes_and_carves() -> void:
	var definition: RefCounted = MapLoader.load_from_file("res://maps/twin_forts.toml")
	var world := VoxelWorldData.new(definition.size)
	MapBuilder.apply_to_world(world, _default_materials(), definition)
	_expect_equal(world.get_material_id(Vector3i(12, 0, 36)), 2, "map builder applies stone floor base")
	_expect_equal(world.get_material_id(Vector3i(12, 2, 36)), 1, "map builder applies dirt floor top")
	_expect_equal(world.get_material_id(Vector3i(48, 4, 48)), 0, "map builder carves center crater")
	_expect_equal(world.get_material_id(Vector3i(10, 4, 30)), 2, "map builder applies fort wall")

func _test_map_validator_accepts_twin_forts_spawns() -> void:
	var definition: RefCounted = MapLoader.load_from_file("res://maps/twin_forts.toml")
	var world := VoxelWorldData.new(definition.size)
	MapBuilder.apply_to_world(world, _default_materials(), definition)
	var errors: Array[String] = MapValidator.validate(definition, world)
	_expect_equal(errors.size(), 0, "map validator accepts twin forts")

func _test_turn_controller_rejects_inactive_player() -> void:
	var controller := TurnController.new([_player("p1"), _player("p2")])
	var command: RefCounted = PlayerActionCommand.new()
	command.player_id = "p2"
	command.turn_id = controller.turn_id
	command.shot_power = 0.5
	var result := controller.validate_action(command)
	_expect_equal(result.ok, false, "inactive player action rejected")
	_expect_equal(result.reason, "inactive_player", "inactive player rejection reason")

func _test_turn_controller_clamps_shot_power() -> void:
	var controller := TurnController.new([_player("p1"), _player("p2")])
	var command: RefCounted = PlayerActionCommand.new()
	command.player_id = "p1"
	command.turn_id = controller.turn_id
	command.shot_power = 8.0
	var result := controller.validate_action(command)
	_expect_equal(result.ok, true, "active player action accepted")
	_expect_equal(command.shot_power, 4.0, "shot power clamped")

func _test_turn_controller_skips_dead_player() -> void:
	var player_one := _player("p1")
	var player_two := _player("p2")
	player_two.is_alive = false
	var controller := TurnController.new([player_one, player_two])
	controller.complete_turn()
	_expect_equal(controller.get_active_player().player_id, "p1", "dead player skipped")

func _player(player_id: String) -> RefCounted:
	var player: RefCounted = PlayerState.new()
	player.player_id = player_id
	player.display_name = player_id
	player.is_alive = true
	player.health = 100
	return player
