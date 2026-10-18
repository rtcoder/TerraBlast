extends SceneTree
const Loader = preload("res://scripts/core/maps/map_loader.gd")
const Parser = preload("res://scripts/core/maps/toml_map_parser.gd")
const Generator = preload("res://scripts/core/maps/arena_generator.gd")
const Validator = preload("res://scripts/core/maps/map_validator.gd")
const World = preload("res://scripts/core/voxels/voxel_world_data.gd")
const Ray = preload("res://scripts/core/voxels/voxel_raycast.gd")
const Analysis = preload("res://scripts/core/maps/arena_analysis.gd")
const Trace = preload("res://scripts/core/projectiles/trajectory_analysis.gd")
const Catalog = preload("res://scripts/core/weapons/weapon_catalog.gd")
const Spawn = preload("res://scripts/core/maps/spawn_point.gd")
const Selector = preload("res://scripts/core/maps/spawn_selector.gd")
var failures := 0
func check(value: bool,label: String) -> void:
	if not value:
		failures += 1
		push_error(label)
func definition() -> RefCounted:
	return Loader.from_dictionary({"id":"small","name":"Small","size":[8,6,8],"spawns":[{"team":1,"position":[1,1,1],"slot":0},{"team":2,"position":[6,1,6],"slot":0}],"boxes":[{"position":[0,0,0],"size":[8,1,8],"material":"dirt"}]})
func _initialize() -> void:
	parser_edges()
	map_edges()
	analysis_edges()
	trajectory_edges()
	content_geometry()
	print("CORE250 EDGES: %d failures" % failures)
	quit(1 if failures else 0)
func parser_edges() -> void:
	check(not Parser.parse('[[spawns]]\nteam=1\nteam=2')._errors.is_empty(),"Table duplicate rejected")
	check(Parser.parse('[[spawns]]\nteam=1\n[[spawns]]\nteam=2')._errors.is_empty(),"Keys independent across tables")
	check(Parser.parse('name="A # B \\"quoted\\"" # comment').name == 'A # B "quoted"',"Escaped quote comment boundary")
	for bad in ['[[bad]]','[spawns]','size=[1,2,]','size=[1,"2",3]','id="x" trailing','id="x"\nid="y"']:
		check(not Parser.parse(bad)._errors.is_empty(),"Invalid subset syntax")
	var d = definition()
	d.display_name = "Żółć " + "x".repeat(123)
	check(Validator.validate_definition(d).is_empty(),"Unicode title at128")
	d.display_name += "x"
	check(not Validator.validate_definition(d).is_empty(),"Title over128 rejected")
	d = definition()
	d.id = "a".repeat(64)
	check(Validator.validate_definition(d).is_empty(),"ID64 allowed")
	d.id += "a"
	check(not Validator.validate_definition(d).is_empty(),"ID65 rejected")
	d = definition()
	d.theme = "x".repeat(65)
	check(not Validator.validate_definition(d).is_empty(),"Theme cap")
	var report: Dictionary = Validator.inspect_definition(d)
	check(not report.ok and report.errors == Validator.validate_definition(d) and report.warnings is Array,"Structured validator compatibility")
func map_edges() -> void:
	var d = definition()
	for bad in [{"shape":"cube","position":[1,1,1],"radius":1},{"position":[99999,0,0],"radius":2},{"position":[0,0,0],"radius":257}]:
		d.carves.assign([bad])
		check(not Validator.validate_definition(d).is_empty(),"Invalid carve rejected")
	d = definition()
	d.boxes.append({"position":[0,0,0],"size":[1,1,1],"material":"air","health":1})
	check(not Validator.validate_definition(d).is_empty(),"Air health invariant")
	d.boxes[-1].health = 0
	check(Validator.validate_definition(d).is_empty(),"Air zero valid")
	var world = World.new(Vector3i(5,5,5))
	world.fill_box(Vector3i(-100,-100,-100),Vector3i(2,2,2),1,100)
	check(world.material_ids.count(1) == 8,"Clipped fill exact")
	var reference: PackedInt32Array = world.material_ids.duplicate()
	world.fill_box(Vector3i(4,4,4),Vector3i(3,3,3),1,100)
	check(world.material_ids == reference,"Reversed box empty")
	world.fill_box(Vector3i.ZERO,world.size,1,100)
	load("res://scripts/core/maps/map_builder.gd")._carve_sphere(world,Vector3i.ZERO,2)
	var expected_air := 0
	for z in range(5):
		for y in range(5):
			for x in range(5):
				if x*x+y*y+z*z <= 4: expected_air += 1
	check(world.material_ids.count(0)==expected_air,"Clipped carve exact reference")
	var materials: Dictionary = Generator.materials()
	var mat = load("res://scripts/core/voxels/voxel_material_config.gd").new()
	mat.id = 4
	mat.code = "mist"
	mat.max_health = 100
	materials[4] = mat
	d = definition()
	d.boxes.append({"position":[1,1,1],"size":[1,2,1],"material":"mist"})
	check(Generator.from_definition(d,16,materials).errors.is_empty(),"Custom nonsolid material permits spawn")
	check(not Generator.from_definition(d).errors.is_empty(),"Unknown material rejected")
	materials[4] = 3
	check(not Generator.from_definition(d,16,materials).errors.is_empty(),"Invalid override catalog controlled")
	d = definition()
	d.boxes.append({"position":[1,2,1],"size":[1,1,1],"material":"stone"})
	check(not Generator.from_definition(d).errors.is_empty(),"Spawn actual headroom")
	d = definition()
	d.spawns[1].position = [1,2,1]
	check(not Generator.from_definition(d).errors.is_empty(),"Vertically overlapping pawns rejected")
	var only := [Spawn.new(Vector3i(1,1,1),1,0),Spawn.new(Vector3i(2,1,1),1,1)]
	check(not Selector.select(only,2).ok,"Selector requires opponent")
	var uneven := [Spawn.new(Vector3i(1,1,1),1,0),Spawn.new(Vector3i(2,1,1),2,0),Spawn.new(Vector3i(3,1,1),2,1)]
	check(Selector.select(uneven,3).ok and Selector.select(uneven,3).spawns.size()==3,"Uneven team capacity supported")
	var catalog = load("res://scripts/core/voxels/material_catalog.gd")
	var values: Array = Generator.materials().values()
	check(catalog.from_configs(values).size()==4,"Material catalog construction")
	values.append(values[0])
	check(catalog.from_configs(values).is_empty(),"Duplicate material ID rejected")
func analysis_edges() -> void:
	var d = definition()
	var arena: Dictionary = Generator.from_definition(d)
	var before: PackedInt32Array = arena.world.material_ids.duplicate()
	var summary: Dictionary = Analysis.summarize(arena.world,arena.materials)
	check(summary.heightmap[0][0]==1 and summary.occupied_min==Vector3i.ZERO and summary.occupied_max==Vector3i(7,0,7),"Terrain height/bounds")
	var clearance: Array = Analysis.spawn_clearance(arena.world,arena.spawns,arena.materials,1)
	check(clearance[0].free_supported_neighbors==8 and clearance[0].cover_neighbors==0,"Open spawn clearance")
	var compare: Dictionary = Analysis.compare_teams(arena.world,arena.spawns,arena.materials)
	check(compare.differences.height==0 and compare.differences.free_supported_neighbors==0,"Symmetric start metrics")
	arena.world.set_voxel(Vector3i(2,1,1),3,255)
	compare = Analysis.compare_teams(arena.world,arena.spawns,arena.materials)
	check(compare.differences.cover_neighbors!=0 and not compare.warnings.is_empty(),"Asymmetric cover reported")
	arena.world.material_ids = before
	var destroy = load("res://scripts/core/terrain/voxel_destruction.gd").new(arena.world,arena.materials)
	var impact = load("res://scripts/core/terrain/terrain_impact_analysis.gd")
	var delta := {"position":[1,0,1],"material_id":0,"health":0}
	var report: Dictionary = impact.summarize(arena.world,[delta,delta],arena.materials)
	check(report.ok and report.changed==1 and report.destroyed==1 and report.health_lost==100 and report.affected_chunks.size()==1,"Impact deduplicates final changes")
	check(not impact.summarize(arena.world,[{"position":[1,0],"material_id":0,"health":0}],arena.materials).ok,"Impact malformed controlled")
	for radius in [-1,17,1000000]: check(destroy.preview_explosion(Vector3i.ZERO,radius,100).is_empty(),"Invalid blast radius bounded")
	check(arena.world.material_ids==before,"Analysis and invalid explosion immutable")
	for radius in [0,1,4,16]:
		var expected := []
		for z in range(8):
			for x in range(8):
				var p:=Vector3i(x,0,z)
				var distance:=Vector3(p-Vector3i(3,0,3)).length()
				if distance>radius:continue
				var factor: float=1.0-distance/radius if radius>0 else 1.0
				var damage:=roundi(150*factor)
				if damage>0: expected.append([p,maxi(0,100-damage)])
		var actual: Array = destroy.preview_explosion(Vector3i(3,0,3),radius,150)
		check(actual.size()==expected.size(),"Blast reference size")
		for i in range(actual.size()):check(actual[i].position==expected[i][0] and actual[i].health==expected[i][1],"Blast reference delta")
func trajectory_edges() -> void:
	var world=World.new(Vector3i(8,8,8))
	world.set_voxel(Vector3i(3,3,3),1,100)
	check(Ray.segment_hit(world,Vector3(3.5,3.5,3.5),Vector3(3.5,3.5,3.5)).hit,"Zero-length inside solid")
	check(not Ray.segment_hit(world,Vector3.ZERO,Vector3.ZERO).hit,"Zero-length air")
	check(Ray.segment_hit(world,Vector3(1.5,1.5,1.5),Vector3(5.5,5.5,5.5)).hit,"Diagonal DDA")
	check(Ray.segment_hit(world,Vector3(3,3.5,3.5),Vector3(1,3.5,3.5)).distance==0,"Starting boundary deterministic")
	check(Ray.segment_hit(world,Vector3.ZERO,Vector3(5000,0,0)).reason=="invalid","Segment distance capped")
	for reason in ["miss","impact","fuse","invalid","simulation_budget"]:
		var result: Dictionary={"path":PackedVector3Array([Vector3.ZERO]),"position":Vector3.ZERO,"hit":reason in ["impact","fuse"],"reason":reason,"deltas":[]}
		check(Trace.classify(result).complete==(reason in ["miss","impact","fuse"]),"Terminal classification "+reason)
	for bad in [{},{"path":[]},{"path":PackedVector3Array([Vector3(NAN,0,0)]),"position":Vector3.ZERO,"hit":false,"reason":"miss","deltas":[]}]:
		check(not Trace.classify(bad).valid and not Trace.summarize(bad).ok,"Malformed trace rejected")
	var line:=PackedVector3Array([Vector3.ZERO,Vector3.ONE,Vector3(2,2,2)])
	check(Trace.trace_intersections(world,line,{},1).truncated,"Trace segment budget")
	var solver = load("res://scripts/core/projectiles/trajectory_solver.gd")
	var rules = load("res://scripts/core/rules/game_rules_config.gd").new()
	check(not solver.solve(world,Vector3.ZERO,Vector3.ONE,Resource.new(),rules).ok,"Solver rejects wrong config resource")
	check(not solver.solve(world,Vector3.ZERO,Vector3.ONE,Catalog.load_all()[1],Resource.new()).ok,"Solver rejects wrong rules resource")
	var weapon: Resource = Catalog.load_all()[1]
	var origin := Vector3(1.5,5,1.5)
	var target := Vector3(6,2,4)
	var solution: Dictionary = solver.solve(world,origin,target,weapon,rules,{},3)
	var yaw := atan2(target.x-origin.x,target.z-origin.z)
	var expected_error := INF
	for pair in [[0.25,0.4],[0.25,0.85],[0.6,0.4]]:
		var direction := Vector3(sin(yaw)*cos(pair[0]),sin(pair[0]),cos(yaw)*cos(pair[0]))
		var power: float = lerpf(rules.min_shot_power,rules.max_shot_power,pair[1])
		var candidate: Dictionary = load("res://scripts/core/projectiles/projectile_simulation.gd").simulate(world,origin,direction,power,weapon,rules)
		if Trace.classify(candidate).complete: expected_error = minf(expected_error,candidate.position.distance_to(target))
	check(solution.ok and solution.candidates==3 and solution.error==expected_error,"Solver ranks exact evaluated candidate set")
	var config: Resource=Catalog.load_all()[1]
	var info: Dictionary=Catalog.describe(config)
	check(info.damage_samples==[config.damage_at_distance(0),config.damage_at_distance(config.player_damage_radius/2),0],"Weapon description exact damage curve")
	info.damage_samples[0]=-1
	check(Catalog.describe(config).damage_samples[0]>=0,"Weapon description isolated")
	check(not Catalog.validate_configs([config,config]).is_empty(),"Duplicate weapon catalog diagnostics")
func content_geometry() -> void:
	var arena: Dictionary=Generator.generate("res://maps/ballistics_range.toml")
	check(arena.world.get_material_id(Vector3i(24,5,8))==1 and arena.world.get_material_id(Vector3i(32,5,24))==2 and arena.world.get_material_id(Vector3i(40,5,40))==3,"Range target materials")
	arena=Generator.generate("res://maps/terraced_quarry.toml")
	check(arena.world.get_material_id(Vector3i(17,4,22))!=0 and arena.world.get_material_id(Vector3i(18,5,22))!=0 and arena.world.get_material_id(Vector3i(19,6,22))!=0,"Quarry stair heights")
	arena=Generator.generate("res://maps/split_pass.toml")
	var destroy=load("res://scripts/core/terrain/voxel_destruction.gd").new(arena.world,arena.materials)
	destroy.apply_explosion(Vector3i(32,3,10),5,1000)
	check(arena.world.get_material_id(Vector3i(32,3,10))==0 and arena.world.get_material_id(Vector3i(32,3,36))!=0,"Independent crossings")
	arena=Generator.generate("res://maps/bunker_court.toml")
	destroy=load("res://scripts/core/terrain/voxel_destruction.gd").new(arena.world,arena.materials)
	destroy.apply_explosion(Vector3i(20,6,12),4,1000)
	check(arena.world.get_material_id(Vector3i(20,6,12))==0 and arena.world.get_material_id(Vector3i(18,6,12))==3,"Bunker door and frame")
	arena=Generator.generate("res://maps/ring_island.toml")
	check(arena.world.get_material_id(Vector3i(0,0,10))==0 and arena.world.get_material_id(Vector3i(6,3,8))!=0,"Island exposed edge with safe spawn")
	arena=Generator.generate("res://maps/three_lane_foundry.toml")
	check(arena.world.get_material_id(Vector3i(20,5,15))==3 and arena.world.get_material_id(Vector3i(30,5,15))==1,"Foundry divider and cross passage")
	var classic: Dictionary=Catalog.load_loadout("classic")
	var artillery: Dictionary=Catalog.load_loadout("artillery")
	for id in [1,2,3]:
		check(artillery[id].validate() and artillery[id].id==id and artillery[id].max_uses_per_match>0,"Artillery legal bounded ammo")
		var sim=load("res://scripts/core/projectiles/projectile_simulation.gd")
		var rules=load("res://scripts/core/rules/game_rules_config.gd").new()
		var a: Dictionary=sim.simulate(arena.world,Vector3(6.5,5.3,8.5),Vector3(1,0.4,0),1,classic[id],rules,arena.materials)
		var b: Dictionary=sim.simulate(arena.world,Vector3(6.5,5.3,8.5),Vector3(1,0.4,0),1,artillery[id],rules,arena.materials)
		check(a.path!=b.path,"Artillery creates distinct trajectory")
