extends SceneTree
const World = preload("res://scripts/core/voxels/voxel_world_data.gd")
const Generator = preload("res://scripts/core/maps/arena_generator.gd")
const Rules = preload("res://scripts/core/rules/game_rules_config.gd")
const Weapon = preload("res://scripts/core/weapons/weapon_config.gd")
const Simulation = preload("res://scripts/core/projectiles/projectile_simulation.gd")
const Analysis = preload("res://scripts/core/projectiles/trajectory_analysis.gd")
const Replay = preload("res://scripts/core/replay/match_replay.gd")
var failures := 0
const GOLDENS := {
  "drill_0_escape": "810bf85f0591ac2bbc0eece82cc0a58f0d025d14479b692954bf924a71fe7b8b",
  "drill_0_metal": "9236494c5e5976e2d6a1b1341b0c65d8b2aa6112a8a9aba75edb419d79c80cf1",
  "drill_0_wall": "9236494c5e5976e2d6a1b1341b0c65d8b2aa6112a8a9aba75edb419d79c80cf1",
  "drill_1_escape": "810bf85f0591ac2bbc0eece82cc0a58f0d025d14479b692954bf924a71fe7b8b",
  "drill_1_metal": "9236494c5e5976e2d6a1b1341b0c65d8b2aa6112a8a9aba75edb419d79c80cf1",
  "drill_1_wall": "941f9b00c8681db2b4ff6843fc07f1f6d00e04eda29f3759e8a5243a0652507a",
  "drill_64_escape": "810bf85f0591ac2bbc0eece82cc0a58f0d025d14479b692954bf924a71fe7b8b",
  "drill_64_metal": "9236494c5e5976e2d6a1b1341b0c65d8b2aa6112a8a9aba75edb419d79c80cf1",
  "drill_64_wall": "941f9b00c8681db2b4ff6843fc07f1f6d00e04eda29f3759e8a5243a0652507a",
  "drill_air": "9d12b9f21aad55228ca1ef9a053577291c71ca2eb8a6f376285aaadb017fe4a0",
  "drill_corner": "dec3a736f17521a17a2bcfeecc33c722ba2800016f546edc34a726ee223b4e00",
  "drill_escape": "810bf85f0591ac2bbc0eece82cc0a58f0d025d14479b692954bf924a71fe7b8b",
  "drill_inside": "97509819c1b0ccb5b221a1ce44ba761330b4fb513fb1b89d4f796bf11a1d63f0",
  "drill_tangent": "157b08ca96788f6672460e4e02d41e43b334ee2978889d436c340449037c49d7",
  "grenade_0.0_corner": "7b2b32edb0d0884ad010097fccc949069eb3beb8d02b24685116af9980d3b610",
  "grenade_0.0_escape": "810bf85f0591ac2bbc0eece82cc0a58f0d025d14479b692954bf924a71fe7b8b",
  "grenade_0.0_floor": "5518ac1a4fb9f1bc68a4bfe28ae555a783815e11e14681f143383edcd408e938",
  "grenade_0.0_rest": "442de0f560efd4de910155caaa2eaededbe13454addead1db75d2bfa557363a8",
  "grenade_0.0_wall": "3eb89ae4c814271f020ea9e81214a40f416e117ce7dff452352e0c12c799c998",
  "grenade_1.0_corner": "2d76bb83b60cfd58fdcdd16b56d07e922daf7d2fcfc62587c6011cd0122852a9",
  "grenade_1.0_escape": "810bf85f0591ac2bbc0eece82cc0a58f0d025d14479b692954bf924a71fe7b8b",
  "grenade_1.0_floor": "cb1e9904e94918b9d4337c6723fc88c18b033605fde27c51d821bb6b9a2ac094",
  "grenade_1.0_rest": "4b2b5fbebf8341a2e1876662104fa10adb327e4dc56c3ee0656d25e49843634d",
  "grenade_1.0_wall": "e6aefca35873517998bb42740332ee2b6b1b113ee55fb76a825921327df1d4dc",
  "grenade_air": "169601f3cb314fdc6f5bd22313e6ed5d49fbd37b8f2898bcb78d8c063260cfcb",
  "grenade_corner": "f64f11582fc9e36a5aaa3b10d869ef4d8e8dbc576fb7a55e2e6f7c79b0048995",
  "grenade_escape": "810bf85f0591ac2bbc0eece82cc0a58f0d025d14479b692954bf924a71fe7b8b",
  "grenade_inside": "43464619af54a49ef652887a7bb570211f8af3934955588583cd8b09f83885a9",
  "grenade_tangent": "e22ed6e8a832695f76fd2e8cdff0575f0e0f1d3253a0558282eba045ddaeffa9",
  "impact_air": "9d12b9f21aad55228ca1ef9a053577291c71ca2eb8a6f376285aaadb017fe4a0",
  "impact_corner": "289a321cd36437fa1b5a63bf34d784827dce11c77c1a1bfb9886f26cd1baec25",
  "impact_escape": "810bf85f0591ac2bbc0eece82cc0a58f0d025d14479b692954bf924a71fe7b8b",
  "impact_inside": "9472b69141c745b30ff1cddaacdca0c06ca2082ec29eec80b74c45c59b98721d",
  "impact_tangent": "0f42d2e7d5b470fe4ae2d03db2659e226aeef02c7c255de84c544d44bd41d5e3"
}
func check(value: bool,label: String) -> void:
	if not value:
		failures += 1
		push_error(label)
func signature(result: Dictionary) -> String:
	var points := []
	for point in result.path: points.append([point.x,point.y,point.z])
	return JSON.stringify({"path":points,"position":[result.position.x,result.position.y,result.position.z],"hit":result.hit,"reason":result.reason,"deltas":result.deltas},"",true,true).sha256_text()
func _initialize() -> void:
	var actual := {}
	for behavior in ["impact","grenade","drill"]:
		for scenario in ["air","inside","tangent","corner","escape"]:
			actual[behavior+"_"+scenario] = fixture(behavior,scenario)
	for bounce in [0.0,1.0]:
		for scenario in ["floor","wall","corner","rest","escape"]:
			actual["grenade_%s_%s" % [bounce,scenario]] = fixture("grenade",scenario,bounce)
	for depth in [0,1,64]:
		for scenario in ["wall","metal","escape"]:
			actual["drill_%d_%s" % [depth,scenario]] = fixture("drill",scenario,0.55,depth)
	check(actual == GOLDENS,"Frozen legacy trajectories remain exact")
	preview_execution()
	print("TRAJECTORY250: %d failures" % failures)
	quit(1 if failures else 0)
func fixture(behavior: String,scenario: String,bounce: float=0.55,depth: int=4) -> String:
	var world = World.new(Vector3i(16,16,16))
	var materials: Dictionary = Generator.materials()
	world.fill_box(Vector3i.ZERO,Vector3i(16,1,16),1,100)
	if scenario in ["wall","corner","inside","metal"]: world.fill_box(Vector3i(8,1,0),Vector3i(9,10,16),3 if scenario=="metal" else 1,100)
	if scenario == "corner": world.fill_box(Vector3i(0,1,8),Vector3i(16,10,9),2,180)
	var weapon = Weapon.new()
	weapon.id = 1
	weapon.code = behavior
	weapon.behavior = behavior
	weapon.projectile_speed = 25
	weapon.min_projectile_speed = 10
	weapon.fuse_time = 0.517
	weapon.bounce = bounce
	weapon.drill_voxels = depth
	var rules = Rules.new()
	var origin := Vector3(3.5,4,4.5)
	var direction := Vector3(1,0.2,0)
	if scenario == "inside": origin = Vector3(8.5,4,4.5)
	if scenario == "tangent": origin.y = 1.0
	if scenario == "corner": direction = Vector3(1,0,1)
	if scenario == "floor": direction = Vector3(0,-1,0)
	if scenario == "rest":
		origin.y = 1.001
		direction = Vector3(0,-1,0)
	if scenario == "escape":
		origin.x = 15.9
		direction = Vector3.RIGHT
	var before: PackedInt32Array = world.material_ids.duplicate()
	var hp: PackedInt32Array = world.health_values.duplicate()
	var result: Dictionary = Simulation.simulate(world,origin,direction,2,weapon,rules,materials)
	check(Analysis.validate_result(result).is_empty(),"Simulation result contract "+behavior+scenario)
	check(world.material_ids == before and world.health_values == hp,"Prediction immutable "+behavior+scenario)
	check(signature(result)==signature(Simulation.simulate(world,origin,direction,2,weapon,rules,materials)),"Repeat deterministic "+behavior+scenario)
	check(result.deltas.size() <= depth,"Drill penetration capped")
	var seen := {}
	for delta in result.deltas:
		var key := str(delta.position)
		check(not seen.has(key),"No repeated drill delta")
		seen[key] = true
		var p := Vector3i(delta.position[0],delta.position[1],delta.position[2])
		check(world.get_material_id(p) != 3,"Metal never drilled")
	return signature(result)
func preview_execution() -> void:
	var factory = load("res://scripts/core/rules/match_factory.gd")
	for id in [1,2,3]:
		var runner = factory.create_match(2,"res://maps/ballistics_range.toml")
		var player = runner.state.get_active_player()
		var command = load("res://scripts/core/turns/player_action_command.gd").new()
		command.player_id = player.player_id
		command.turn_id = runner.state.turn_id
		command.generation = runner.state.generation
		command.weapon_id = id
		command.shot_power = 1
		command.aim_direction = Vector3(1,0.2,0)
		var hash_before: String = Replay.state_hash(runner)
		var preview: Dictionary = Simulation.simulate(runner.world,player.position+Vector3.UP*1.3,command.aim_direction,command.shot_power,runner.weapons[id],runner.rules,runner.materials)
		check(Replay.state_hash(runner)==hash_before,"Preview leaves full state unchanged")
		var result: Dictionary = runner.submit(command)
		check(result.ok and result.path == preview.path and result.reason == preview.reason,"Execution matches exact preview")
		check(runner.state.turn_id == 1,"Accepted shot advances one turn")
