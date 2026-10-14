extends SceneTree
var failures := 0
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var server_path := "res://scripts/networking/transport/match_server.gd"
	check(ResourceLoader.exists(server_path), "ENet match server exists")
	if not ResourceLoader.exists(server_path):
		quit(1)
		return
	var server = load(server_path).new()
	root.add_child(server)
	check(server.start(19173) == OK, "Server binds")
	var a = load("res://scripts/networking/transport/match_client.gd").new()
	var b = load("res://scripts/networking/transport/match_client.gd").new()
	root.add_child(a)
	root.add_child(b)
	a.connect_to_server("127.0.0.1", 19173)
	b.connect_to_server("127.0.0.1", 19173)
	for attempt in range(200):
		if a.ready_for_match and b.ready_for_match:
			break
		await create_timer(0.02).timeout
	check(a.ready_for_match and b.ready_for_match, "Both peers receive initial snapshot")
	if a.ready_for_match and b.ready_for_match:
		check(a.player_id != b.player_id, "Server assigns different player slots")
		var active = a if a.player_id == "blue_1" else b
		var other = b if active == a else a
		var command = load("res://scripts/core/turns/player_action_command.gd").new()
		command.player_id = active.player_id
		command.weapon_id = 1
		command.shot_power = 1.0
		command.aim_direction = Vector3.DOWN
		other.send_command(command)
		await create_timer(0.15).timeout
		check(server.runner.state.turn_id == 0, "Spoofed identity rejected")
		active.send_command(command)
		for attempt in range(100):
			if a.runner.state.turn_id == 1 and b.runner.state.turn_id == 1:
				break
			await create_timer(0.02).timeout
		check(a.runner.state.turn_id == 1 and b.runner.state.turn_id == 1, "Authoritative turn replicated")
		check(a.runner.world.material_ids == server.runner.world.material_ids and b.runner.world.health_values == server.runner.world.health_values, "Terrain deltas synchronize both peers")
		check(a.last_result.has("deltas") and not a.last_result.has("chunks"), "Shot result has deltas, no world snapshot")
		active.send_command(command)
		await create_timer(0.1).timeout
		check(server.runner.state.turn_id == 1, "Duplicate turn rejected")
		a.runner.world.set_voxel(Vector3i(0, 0, 0), 0, 0)
		a.request_snapshot()
		for attempt in range(200):
			if a.runner.world.material_ids == server.runner.world.material_ids:
				break
			await create_timer(0.02).timeout
		check(a.runner.world.material_ids == server.runner.world.material_ids, "Explicit snapshot recovers desync")
	a.close()
	b.close()
	server.close()
	print("Network smoke: %d failures" % failures)
	quit(1 if failures else 0)
