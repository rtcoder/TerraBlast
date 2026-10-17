extends SceneTree

const Factory = preload("res://scripts/core/rules/match_factory.gd")
const Generator = preload("res://scripts/core/maps/arena_generator.gd")
const Loader = preload("res://scripts/core/maps/map_loader.gd")
const Validator = preload("res://scripts/core/maps/map_validator.gd")
const Replay = preload("res://scripts/core/replay/match_replay.gd")
var failures := 0

func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)

func _initialize() -> void:
	for invalid_count in [-1, 0, 1, 11]:
		check(Factory.create_match(invalid_count) == null, "Factory rejects invalid player count %d" % invalid_count)
	var definition = Loader.load_from_file("res://maps/twin_forts.toml")
	definition.size = Vector3i(256, 128, 256)
	check(not Validator.validate_definition(definition).is_empty(), "Volume capped before allocation")
	definition = Loader.load_from_file("res://maps/twin_forts.toml")
	while definition.boxes.size() < 4097:
		definition.boxes.append(definition.boxes[0].duplicate())
	check(not Validator.validate_definition(definition).is_empty(), "Operation count capped")
	check(FileAccess.file_exists("res://scripts/core/maps/map_registry.gd"), "Registry exists")
	check(FileAccess.file_exists("res://maps/canyon_bridge.toml"), "Canyon exists")
	_test_registry_and_arena()
	_test_factory_and_replay()
	_test_limits()
	print("ARENA OCT17 TESTS: %s" % ("PASS" if failures == 0 else "FAIL %d" % failures))
	quit(0 if failures == 0 else 1)

func _test_registry_and_arena() -> void:
	var registry = load("res://scripts/core/maps/map_registry.gd")
	if registry == null:
		return
	check(registry.PATHS.size() == 3 and registry.describe("unknown").is_empty(), "Registry has three known maps")
	for id in registry.PATHS:
		var meta: Dictionary = registry.describe(id)
		check(meta.id == id and not meta.name.is_empty() and not meta.description.is_empty() and meta.player_capacity == 10, "Complete metadata: " + id)
		meta.size[0] = -1
		meta.name = "changed"
		check(registry.describe(id).size[0] > 0 and registry.describe(id).name != "changed", "Metadata mutations isolated")
	var definition = Loader.load_from_file("res://maps/canyon_bridge.toml")
	var first: Dictionary = Generator.from_definition(definition)
	check(first.errors.is_empty() and first.world != null, "Canyon generation valid")
	if first.world == null:
		return
	check(first.world.size == Vector3i(80, 24, 64) and first.spawns.size() == 10, "Canyon dimensions and all ten spawns")
	check(Validator.validate(definition, first.world).is_empty(), "All spawns have headroom and ground")
	definition.spawns.reverse()
	var second: Dictionary = Generator.from_definition(definition)
	check(hash(first.world.material_ids) == hash(second.world.material_ids), "Generation hashes deterministic")
	for i in range(10):
		check(first.spawns[i].position == second.spawns[i].position, "Shuffled TOML spawn order stable")
		check(first.spawns[i].slot == i / 2 and first.spawns[i].team == i % 2 + 1, "Interleaved slot/team ordering")
	var center := Vector3i(30, 7, 28)
	var before_materials: PackedInt32Array = first.world.material_ids.duplicate()
	var before_health: PackedInt32Array = first.world.health_values.duplicate()
	var destruction = load("res://scripts/core/terrain/voxel_destruction.gd")
	check(not destruction.new(first.world, first.materials).apply_explosion(center, 5, 999).is_empty(), "Bridge explosion changes terrain")
	destruction.new(second.world, second.materials).apply_explosion(center, 5, 999)
	check(first.world.material_ids == second.world.material_ids and first.world.health_values == second.world.health_values, "Destruction deterministic")
	var allowed := true
	for z in range(64):
		for y in range(24):
			for x in range(80):
				var position := Vector3i(x, y, z)
				var index: int = first.world.get_index(position)
				if before_materials[index] != first.world.material_ids[index] or before_health[index] != first.world.health_values[index]:
					allowed = allowed and position.distance_squared_to(center) <= 25 and first.materials[before_materials[index]].is_destructible
	check(allowed, "Explosion changes only destructible voxels inside radius")
	check(first.world.get_material_id(Vector3i(30, 8, 27)) == 3, "Bridge metal cover survives explosion")

func _test_factory_and_replay() -> void:
	for count in [2, 4, 10]:
		var runner = Factory.create_match(count, "res://maps/canyon_bridge.toml")
		check(runner != null, "Factory Canyon count %d" % count)
		if runner == null:
			continue
		check(runner.state.players.size() == count, "Factory returns exact count")
		for i in range(count):
			check(runner.state.players[i].team_id == i % 2 + 1, "Factory keeps both teams")
	var path := "/tmp/arena-oct17-small-%s.toml" % OS.get_process_id()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string('id = "small"\nsize = [4, 4, 4]\n[[spawns]]\nteam = 1\nslot = 0\nposition = [1, 1, 1]\n[[boxes]]\nposition = [0, 0, 0]\nsize = [4, 1, 4]\nmaterial = "dirt"\n')
	file.close()
	check(Factory.create_match(2, path) == null, "Insufficient spawns explicitly rejected")
	DirAccess.remove_absolute(path)
	var runner = Factory.create_match(10, "res://maps/canyon_bridge.toml")
	if runner == null:
		return
	var recorder := Replay.new()
	recorder.capture(runner)
	var command = load("res://scripts/core/bots/bot_planner.gd").choose(runner)
	check(command != null, "Canyon bot finds a shot")
	if command == null:
		return
	check(recorder.submit(runner, command).ok, "Canyon bot shot legal")
	path = "/tmp/arena-oct17-%s.json" % OS.get_process_id()
	var archive = load("res://scripts/core/replay/replay_archive.gd")
	check(archive.save(path, recorder, runner) == OK, "Canyon archive saved")
	var loaded: Dictionary = archive.load_verified(path)
	check(loaded.ok, "Canyon archive verifies")
	if loaded.ok:
		check(Replay.state_hash(loaded.runner) == Replay.state_hash(runner), "Canyon archive exact roundtrip")
	DirAccess.remove_absolute(path)

func _test_limits() -> void:
	var definition = Loader.load_from_file("res://maps/twin_forts.toml")
	definition.size = Vector3i(256, 32, 256)
	check(Validator.validate_definition(definition).is_empty(), "Exact volume limit allowed")
	definition.size.y += 1
	check(Generator.from_definition(definition).world == null, "Oversize never allocates a world")
	definition = Loader.load_from_file("res://maps/twin_forts.toml")
	definition.boxes.clear()
	definition.carves.clear()
	for i in range(2048):
		definition.boxes.append({"position":[0,0,0], "size":[1,1,1], "material":"dirt"})
		definition.carves.append({"position":[0,0,0], "radius":1})
	check(Validator.validate_definition(definition).is_empty(), "Exact combined operation limit allowed")
	definition.carves.append({"position":[0,0,0], "radius":1})
	check(Generator.from_definition(definition).world == null, "Mixed operation overrun rejected before build")
	definition = Loader.load_from_file("res://maps/twin_forts.toml")
	definition.spawns.clear()
	for i in range(32):
		definition.spawns.append({"team":1, "slot":i, "position":[i,1,0]})
	check(Validator.validate_definition(definition).is_empty(), "Exactly 32 spawns accepted")
	definition.spawns.append({"team":1, "slot":32, "position":[32,1,0]})
	check(Generator.from_definition(definition).world == null, "33 spawns rejected before allocation")
