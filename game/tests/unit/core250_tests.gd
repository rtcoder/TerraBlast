extends SceneTree
const Loader = preload("res://scripts/core/maps/map_loader.gd")
const Parser = preload("res://scripts/core/maps/toml_map_parser.gd")
const Generator = preload("res://scripts/core/maps/arena_generator.gd")
var Factory = load("res://scripts/core/rules/match_factory.gd")
const Validator = preload("res://scripts/core/maps/map_validator.gd")
const World = preload("res://scripts/core/voxels/voxel_world_data.gd")
var failures := 0
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	check(not Parser.parse('id="a"\nid="b"')._errors.is_empty(), "Reject duplicate keys")
	check(not Parser.parse('[[typo]]\nx=1')._errors.is_empty(), "Reject unknown table")
	check(ResourceLoader.exists("res://scripts/core/maps/map_serializer.gd"), "Map serializer exists")
	check(ResourceLoader.exists("res://scripts/core/maps/arena_analysis.gd"), "Arena analysis exists")
	check(ResourceLoader.exists("res://scripts/core/projectiles/trajectory_analysis.gd"), "Trajectory analysis exists")
	check(ResourceLoader.exists("res://scripts/core/projectiles/trajectory_solver.gd"), "Trajectory solver exists")
	if failures == 0:
		maps()
		analysis()
		trajectories()
		content()
	print("CORE250: %d failures" % failures)
	quit(1 if failures else 0)
func maps() -> void:
	var serializer = load("res://scripts/core/maps/map_serializer.gd")
	var d = Loader.load_from_file("res://maps/twin_forts.toml")
	var data: Dictionary = serializer.to_dictionary(d)
	var isolated = Loader.from_dictionary(data)
	data.spawns[0].position[0] = -999
	check(isolated.spawns[0].position[0] >= 0, "Loader deep copies input")
	var copied = isolated.copy()
	copied.spawns[0].position[0] = -999
	check(isolated.spawns[0].position[0] >= 0, "Definition copy isolated")
	var encoded: Dictionary = serializer.to_toml(d)
	check(encoded.ok, "Export map")
	var roundtrip = Loader.from_dictionary(Parser.parse(encoded.text))
	check(serializer.to_dictionary(roundtrip) == serializer.to_dictionary(d), "Map canonical roundtrip")
	d.display_name = 'Quote " slash \\ hash #'
	encoded = serializer.to_toml(d)
	check(Loader.from_dictionary(Parser.parse(encoded.text)).display_name == d.display_name, "Escaped name roundtrip")
	for bad in ['id="unfinished', 'id="bad\\q"', 'size=[1,,2]', 'id="a"\nweird=3']:
		check(not Parser.parse(bad)._errors.is_empty(), "Malformed TOML rejected")
	check(Parser.parse('\n# comment\nwhat')._errors[0].contains("3"), "Parser line diagnostic")
	for bad in [null,true,3,"bad",{}]:
		var invalid = Loader.from_dictionary({"id":"a","size":[4,4,4],"_errors":bad,"spawns":bad})
		check(not invalid.errors.is_empty(), "Malformed containers controlled")
	var path := ("/private/tmp" if OS.get_name()=="macOS" else "/tmp").path_join("core250-map-%s.toml") % OS.get_process_id()
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.close()
	check(not Loader.load_from_file(path).errors.is_empty(), "Empty file rejected")
	file = FileAccess.open(path,FileAccess.WRITE)
	file.seek(1048576)
	file.store_8(0)
	file.close()
	check(not Loader.load_from_file(path).errors.is_empty(), "Oversize file rejected")
	DirAccess.remove_absolute(path)
	check(not Loader.load_from_file(path).errors.is_empty(), "Missing file rejected")
	for field in ["id","display_name","theme"]:
		var invalid = d.copy()
		invalid.set(field,"bad\nvalue")
		check(not Validator.validate_definition(invalid).is_empty(), "Metadata control rejected")
	var huge = d.copy()
	huge.carves.clear()
	for i in range(200): huge.carves.append({"position":[40,10,40],"radius":256})
	check(not Validator.validate_definition(huge).is_empty(), "Voxel work bounded")
	var invalid = d.copy()
	invalid.boxes[0].position = [9223372036854775807,0,0]
	check(not Validator.validate_definition(invalid).is_empty(), "Overflow coordinate rejected")
	for health in [-1,0,10001]:
		invalid = d.copy()
		invalid.boxes[0].health = health
		check(not Validator.validate_definition(invalid).is_empty(), "Solid health validated")
	var mats: Dictionary = Generator.materials()
	var catalog = load("res://scripts/core/voxels/material_catalog.gd")
	check(catalog.validate(mats).is_empty(), "Default material catalog valid")
	var bad_mats: Dictionary = mats.duplicate()
	bad_mats[1] = mats[1].duplicate()
	bad_mats[1].blast_resistance = NAN
	check(not catalog.validate(bad_mats).is_empty(), "Material NaN rejected")
	var arena: Dictionary = Generator.from_definition(d)
	check(arena.errors.is_empty(), "Base map valid")
	var selector = load("res://scripts/core/maps/spawn_selector.gd")
	var chosen: Dictionary = selector.select(arena.spawns,5)
	arena.spawns.reverse()
	check(chosen.ok and selector.select(arena.spawns,5).spawns == chosen.spawns, "Stable selected spawns")
	invalid = d.copy()
	for spawn in invalid.spawns: spawn.team = 1
	check(Factory.from_definition(invalid,2) == null, "Single team rejected")
	var first = Factory.create_match(2)
	var second = Factory.from_definition(Loader.load_from_file("res://maps/twin_forts.toml"),2)
	check(first.world.material_ids == second.world.material_ids and first.state_snapshot() == second.state_snapshot(), "Factory definition equivalence")
	var original_speed: float = second.weapons[1].projectile_speed
	first.weapons[1].projectile_speed = 1
	check(second.weapons[1].projectile_speed == original_speed, "Weapon resources isolated")
func analysis() -> void:
	var helper = load("res://scripts/core/maps/arena_analysis.gd")
	var world = World.new(Vector3i(5,5,5))
	world.fill_box(Vector3i.ZERO,Vector3i(5,1,5),1,100)
	var materials: Dictionary = Generator.materials()
	var summary: Dictionary = helper.summarize(world,materials)
	check(summary.solid_count == 25 and summary.destructible_count == 25, "Terrain summary exact")
	check(helper.walk_components(world,materials).components.size() == 1, "Connected floor")
	world.fill_box(Vector3i(2,1,0),Vector3i(3,5,5),3,255)
	check(helper.walk_components(world,materials).components.size() == 2, "Wall separates components")
	check(helper.walk_components(world,materials,2).truncated, "Graph node budget")
	var destroy = load("res://scripts/core/terrain/voxel_destruction.gd").new(world,materials)
	var before: PackedInt32Array = world.material_ids.duplicate()
	var preview: Array = destroy.preview_explosion(Vector3i(0,0,0),2,500)
	check(world.material_ids == before, "Explosion preview immutable")
	var report: Dictionary = load("res://scripts/core/terrain/terrain_impact_analysis.gd").summarize(world,preview,materials)
	check(report.ok and report.destroyed > 0, "Terrain impact report")
	var actual: Array = destroy.apply_explosion(Vector3i(0,0,0),2,500)
	check(actual.size() == preview.size(), "Preview application size")
	for i in range(actual.size()): check(actual[i].position == preview[i].position and actual[i].health == preview[i].health, "Preview exact delta")
func trajectories() -> void:
	var ray = load("res://scripts/core/voxels/voxel_raycast.gd")
	var helper = load("res://scripts/core/projectiles/trajectory_analysis.gd")
	var world = World.new(Vector3i(8,8,8))
	world.set_voxel(Vector3i(4,2,2),1,100)
	var hit: Dictionary = ray.segment_hit(world,Vector3(1.5,2.5,2.5),Vector3(6.5,2.5,2.5))
	check(hit.hit and hit.voxel == Vector3i(4,2,2) and hit.normal == Vector3.LEFT and hit.distance == 2.5, "Segment hit accurate")
	check(not ray.segment_hit(world,Vector3(NAN,0,0),Vector3.ONE).hit, "Segment nonfinite rejected")
	var result := {"path":PackedVector3Array([Vector3.ZERO,Vector3(0,3,0),Vector3(4,3,0)]),"position":Vector3(4,3,0),"reason":"miss","hit":false,"deltas":[]}
	check(helper.validate_result(result).is_empty(), "Valid trace")
	var summary: Dictionary = helper.summarize(result)
	check(summary.ok and summary.length == 7.0 and summary.apex.y == 3.0, "Trajectory summary geometry")
	var intersections: Dictionary = helper.trace_intersections(world,PackedVector3Array([Vector3(1.5,2.5,2.5),Vector3(6.5,2.5,2.5)]))
	check(intersections.hits.size() == 1, "Trace intersection")
	var runner = Factory.create_match(2)
	var solution: Dictionary = load("res://scripts/core/projectiles/trajectory_solver.gd").solve(runner.world,Vector3(12,12,12),Vector3(30,8,12),runner.weapons[1],runner.rules,runner.materials,3)
	check(solution.candidates <= 3 and solution.candidates > 0, "Solver budget")
func content() -> void:
	var registry = load("res://scripts/core/maps/map_registry.gd")
	var catalog = load("res://scripts/core/weapons/weapon_catalog.gd")
	check(registry.PATHS.size() == 9, "Nine complete arenas")
	check(catalog.load_loadout("unknown").is_empty(), "Unknown loadout rejected")
	check(not catalog.validate_configs([null,3,"bad"]).is_empty(), "Catalog invalid types controlled")
	for id in registry.PATHS:
		var meta: Dictionary = registry.describe(id)
		check(meta.player_capacity == 10 and meta.supported_player_counts.size() == 9, "Supported arena counts " + id)
		for count in range(2,11):
			var counted = Factory.create_match(count,registry.PATHS[id])
			check(counted != null and counted.state.players.size()==count,"Actual supported count %s/%d" % [id,count])
		for loadout in ["classic","artillery"]:
			var runner = Factory.create_match(2,registry.PATHS[id],"classic",loadout)
			check(runner != null, "Arena/loadout fixture " + id + loadout)
			if runner == null: continue
			var before: PackedInt32Array = runner.world.material_ids.duplicate()
			var health_before: PackedInt32Array = runner.world.health_values.duplicate()
			var command = load("res://scripts/core/turns/player_action_command.gd").new()
			command.player_id = runner.state.get_active_player().player_id
			command.turn_id = runner.state.turn_id
			command.generation = runner.state.generation
			command.weapon_id = 1
			command.aim_direction = Vector3(1,0.5,0)
			command.shot_power = 1
			var result: Dictionary = runner.submit(command)
			check(result.ok, "Content shot legal")
			for point in result.path: check(point.is_finite(),"Content trajectory finite")
			for delta in result.deltas:
				check(runner.world.is_in_bounds(Vector3i(delta.position[0],delta.position[1],delta.position[2])) and delta.health>=0,"Content delta legal")
			runner.reset()
			check(runner.world.material_ids == before and runner.world.health_values == health_before, "Content reset exact")
