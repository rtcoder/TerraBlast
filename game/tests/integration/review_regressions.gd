extends SceneTree
const Protocol := preload("res://scripts/networking/messages/match_protocol.gd")
const Factory := preload("res://scripts/core/rules/match_factory.gd")
var failures := 0
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var runner = Factory.create_match(2)
	var state: Dictionary = runner.state_snapshot()
	state.players[0].position = [1e100, 0, 0]
	check(Protocol.decode_state(state) == null, "Reject vectors overflowing Godot float representation")
	check(Protocol.decode_path([[1e100, 0, 0]]).is_empty(), "Reject overflowing trajectory")
	var client = load("res://scripts/networking/transport/match_client.gd").new()
	root.add_child(client)
	client.runner = runner
	client.ready_for_match = true
	state = runner.state_snapshot()
	state.revision = 1
	client._handle({"type": "result", "result": {"version": 1, "ok": true, "reason": "impact", "state": state, "path": [[1, 2, 3]], "events": "malformed", "deltas": [{"position": [0, 0, 0], "material_id": 0, "health": 0}]}})
	check(runner.world.get_material_id(Vector3i.ZERO) == 2 and runner.state.revision == 0, "Malformed events reject entire result atomically")
	var server = load("res://scripts/networking/transport/match_server.gd").new()
	root.add_child(server)
	server.runner = Factory.create_match(2)
	server.slots[2] = "blue_1"
	var motion := {"type": "move", "axis": [0, 0], "yaw": 0.0, "jump": true, "turn_id": 0, "generation": 0}
	server._handle(2, motion)
	motion.jump = false
	server._handle(2, motion)
	check(server.motion["blue_1"].jump, "Pending jump survives regular movement packet")
	var scene = load("res://scenes/debug/VoxelDebug.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_physics_process(false)
	var player = scene.turn_controller.get_active_player()
	for y in range(scene.runner.world.size.y):
		scene.runner.world.set_voxel(Vector3i(floori(player.position.x), y, floori(player.position.z)), 0, 0)
	for tick in range(300):
		scene._update_active_player_movement(1.0 / 60.0)
	check(not player.is_alive, "Local player falling into unsupported column is eliminated")
	print("Review regressions: %d failures" % failures)
	quit(1 if failures else 0)
