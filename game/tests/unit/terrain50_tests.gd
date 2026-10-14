extends SceneTree
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
func _initialize() -> void:
	var node = load("res://scripts/client/rendering/voxel_world_node.gd").new()
	var world = load("res://scripts/core/voxels/voxel_world_data.gd").new(Vector3i(32,32,32))
	node.world = world
	check(node.has_method("mark_voxel_dirty"), "Voxel dirty API supports boundary neighbors")
	if node.has_method("mark_voxel_dirty"):
		node.mark_voxel_dirty(Vector3i(8,8,8))
		check(node.dirty_chunks.size() == 1, "Interior dirties exactly own chunk")
		node.dirty_chunks.clear()
		node.mark_voxel_dirty(Vector3i(15,15,15))
		check(node.dirty_chunks.size() == 4, "Corner dirties own and three face neighbors only")
		node.dirty_chunks.clear()
		node.mark_voxel_dirty(Vector3i.ZERO)
		check(node.dirty_chunks.size() == 1, "World edge never dirties outside chunks")
		node.rebuild_dirty_chunks()
		check(node.last_dirty_chunk_count == 1 and node.last_rebuilt_chunk_count == 1, "Batch counters record rebuilt work")
	world.set_voxel(Vector3i(15,8,8), 1, 100)
	world.set_voxel(Vector3i(16,8,8), 1, 100)
	if node.has_method("set_world"):
		node.set_world(world, load("res://scripts/core/rules/match_factory.gd").materials())
		check(node.total_mesh_count == 2, "Only chunks containing geometry count as meshes")
		var before: int = node.chunk_nodes[Vector3i(1,0,0)].mesh.surface_get_array_len(0)
		world.set_voxel(Vector3i(15,8,8), 0, 0)
		node.refresh_deltas([{"position":[15,8,8]}])
		var after: int = node.chunk_nodes[Vector3i(1,0,0)].mesh.surface_get_array_len(0)
		check(after > before, "Boundary deletion exposes neighboring chunk face")
		check(node.last_rebuilt_chunk_count == 2 and node.total_mesh_count == 1, "Deletion rebuilds two adjacent chunks")
	node.free()
	var path := "res://scripts/core/maps/arena_generator.gd"
	check(ResourceLoader.exists(path), "Pure arena generator exists")
	if ResourceLoader.exists(path):
		var generator = load(path)
		for map_path in ["res://maps/twin_forts.toml", "res://maps/two_islands.toml"]:
			var arena: Dictionary = generator.generate(map_path)
			check(arena.errors.is_empty(), "Valid map " + map_path)
			check(arena.spawns.size() == 10, "Ten typed spawns")
			if arena.spawns.size() == 10:
				check(arena.spawns[0].position is Vector3i and arena.spawns[0].team == 1 and arena.spawns[0].slot == 0, "Typed spawn preserves team, position and slot")
			var again: Dictionary = generator.generate(map_path)
			check(arena.world.material_ids == again.world.material_ids, "Arena generation deterministic")
		var invalid: Dictionary = generator.generate("res://maps/missing.toml")
		check(invalid.world == null and not invalid.errors.is_empty(), "Invalid map fails without world")
	var factory = load("res://scripts/core/rules/match_factory.gd")
	var runner = factory.create_match(10, "res://maps/two_islands.toml")
	check(runner != null and runner.state.players.size() == 10, "Factory accepts alternate map with full roster")
	check(factory.create_match(10, "res://maps/missing.toml") == null, "Factory rejects invalid map")
	var loader = load("res://scripts/core/maps/map_loader.gd")
	var validator = load("res://scripts/core/maps/map_validator.gd")
	var malformed = loader.from_dictionary(load("res://scripts/core/maps/toml_map_parser.gd").parse('id = "bad"\nsize = [8,8,8]\n[[spawns]]\nteam = 1\nposition = [oops,1,2]'))
	check(not validator.validate_definition(malformed).is_empty(), "Invalid numeric TOML token rejected")
	var invalid_def = loader.from_dictionary({"id":"bad","size":[0,24,24],"spawns":[{"position":[1,2],"team":1}]})
	check(not validator.validate(invalid_def, world).is_empty(), "Malformed map geometry rejected")
	print("Terrain50 tests: %d failures" % failures)
	quit(1 if failures else 0)
