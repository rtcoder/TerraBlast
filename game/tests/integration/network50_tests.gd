extends SceneTree
const Client := preload("res://scripts/networking/transport/match_client.gd")
const Server := preload("res://scripts/networking/transport/match_server.gd")
const Factory := preload("res://scripts/core/rules/match_factory.gd")
const Protocol := preload("res://scripts/networking/messages/match_protocol.gd")
class CapturingServer:
	extends "res://scripts/networking/transport/match_server.gd"
	var sent: Dictionary = {}
	func _send(_id: int, data: Dictionary) -> void:
		sent = data
	func _send_snapshot(_id: int) -> void:
		pass

var failures := 0
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var client = Client.new()
	client.runner = Factory.create_match(2)
	client.ready_for_match = true
	var state: Dictionary = client.runner.state_snapshot()
	state.revision = 3
	client._handle({"type": "state", "state": state, "terrain_revision": 1})
	check(not client.ready_for_match, "Missing terrain result triggers recovery before state can mask gap")
	check(client.runner.state.revision == 0, "Gapped state never published")
	client.ready_for_match = true
	client._handle({"type": "state", "state": state, "terrain_revision": 0})
	check(not client.ready_for_match and client.runner.state.revision == 0, "State revision gap also requests recovery")
	client.free()
	var source = Factory.create_match(2)
	source.state.players[0].rotation = Basis(Vector3.UP, 1.2)
	var decoded = Protocol.decode_state(source.state_snapshot())
	check(decoded.players[0].rotation.is_equal_approx(source.state.players[0].rotation), "Snapshot roundtrip preserves player facing")
	var invalid: Dictionary = source.state_snapshot()
	invalid.active_index = -1
	check(Protocol.decode_state(invalid) == null, "Playing snapshot requires active player")
	invalid = source.state_snapshot()
	invalid.winner_team = 1
	check(Protocol.decode_state(invalid) == null, "Playing snapshot cannot declare winner")
	invalid = source.state_snapshot()
	invalid.status = "ended"
	invalid.winner_team = 1
	invalid.winner_player = "blue_1"
	check(Protocol.decode_state(invalid) == null, "Ended snapshot cannot declare winner while opposing team lives")
	invalid = source.state_snapshot()
	invalid.time_remaining = -1
	check(Protocol.decode_state(invalid) == null, "Negative turn timer rejected")
	var command_check = load("res://scripts/core/turns/player_action_command.gd").new()
	command_check.player_id = "blue_1"
	command_check.weapon_id = 1
	command_check.aim_direction = Vector3(0.2, 0.8, 0.3)
	command_check.shot_power = 1.7
	var command_wire := Protocol.unpack(Protocol.packet(Protocol.encode_command(command_check)))
	var command_roundtrip = Protocol.decode_command(command_wire)
	check(command_roundtrip != null and command_roundtrip.aim_direction.is_equal_approx(command_check.aim_direction) and is_equal_approx(command_roundtrip.shot_power, 1.7), "Command serialization preserves validated aim and power")
	var World = load("res://scripts/core/voxels/voxel_world_data.gd")
	source.world = World.new(Vector3i(7, 5, 3), 4)
	source.world.set_voxel(Vector3i(6, 4, 2), 2, 170)
	var dynamic = Client.new()
	dynamic.runner = Factory.create_match(2)
	var previous_world = dynamic.runner.world
	var begin := {"type": "snapshot_begin", "player_id": "blue_1", "resume_token": "test", "size": [7, 5, 3], "chunk_size": 4, "chunk_count": 4, "generation": 0, "revision": 0, "terrain_revision": 0}
	dynamic._handle(begin)
	for y in range(2):
		for x in range(2):
			dynamic._handle({"type": "chunk", "chunk": Protocol.chunk_snapshot(source.world, Vector3i(x,y,0))})
	dynamic._handle({"type": "snapshot_end", "state": source.state_snapshot(), "terrain_revision": 0, "checksum": "corrupted"})
	check(not dynamic.ready_for_match and dynamic.runner.world == previous_world, "Checksum mismatch preserves published world atomically")
	dynamic._handle(begin)
	for y in range(2):
		for x in range(2):
			dynamic._handle({"type": "chunk", "chunk": Protocol.chunk_snapshot(source.world, Vector3i(x,y,0))})
	dynamic._handle({"type": "snapshot_end", "state": source.state_snapshot(), "terrain_revision": 0, "checksum": Protocol.terrain_checksum(source.world)})
	check(dynamic.ready_for_match and dynamic.runner.world.size == Vector3i(7,5,3) and dynamic.runner.world.health_values == source.world.health_values, "Dynamic partial-edge snapshot accepts advertised chunk count")
	dynamic.timeout = 90.0
	dynamic.request_snapshot()
	check(dynamic.timeout == 0.0, "Recovery gets its own timeout after long sessions")
	dynamic.free()
	var limiter = Server.new()
	for index in range(100):
		check(limiter._allow_packet(17, 12), "Normal packets fit per-peer budget")
	check(not limiter._allow_packet(17, 12), "Flood exceeds packet budget")
	check(limiter._allow_packet(18, 12), "Flood does not consume another peer budget")
	check(not limiter._allow_packet(19, 8193), "Oversize command packet rejected")
	limiter.free()
	var policy = CapturingServer.new()
	policy.runner = Factory.create_match(2)
	policy.pending[20] = Time.get_ticks_msec()
	policy.reservations["active-token"] = {"player": "blue_1", "peer": 17, "expires": 0}
	policy._accept_hello(20, {"resume_token": "active-token"})
	check(policy.sent.get("reason") == "resume_token_in_use", "Live token gets distinct retryable rejection")
	var retry_client = Client.new()
	retry_client.resume_token = "active-token"
	retry_client._handle(policy.sent)
	check(retry_client.resume_token == "active-token", "In-use token rejection preserves valid resume credentials")
	retry_client.free()
	policy.slots[17] = "blue_1"
	policy._handle(17, {"type": "restart"})
	var restarted_generation: int = policy.runner.state.generation
	policy._handle(17, {"type": "restart"})
	check(policy.runner.state.generation == restarted_generation, "Restart flood cannot repeatedly rebuild and broadcast full arena")
	policy.free()
	var server = Server.new()
	root.add_child(server)
	var bind_error: int = server.start(19176, "res://maps/two_islands.toml")
	check(bind_error == OK, "Server binds isolated ENet port on alternate map")
	if bind_error != OK:
		server.queue_free()
		quit(1)
		return
	var a = Client.new()
	var b = Client.new()
	root.add_child(a)
	root.add_child(b)
	a.connect_to_server("127.0.0.1", 19176)
	b.connect_to_server("127.0.0.1", 19176)
	for attempt in range(300):
		if a.ready_for_match and b.ready_for_match:
			break
		await create_timer(0.02).timeout
	check(a.ready_for_match and b.ready_for_match, "Both clients receive validated full snapshot")
	if a.ready_for_match and b.ready_for_match:
		var original_id: String = a.player_id
		check(a.get("resume_token") is String and not str(a.get("resume_token")).is_empty(), "Server provides opaque resume token")
		check(a.runner.world.health_values == server.runner.world.health_values, "Snapshot includes coherent terrain health")
		a.close()
		await create_timer(0.15).timeout
		a.connect_to_server("127.0.0.1", 19176)
		for attempt in range(300):
			if a.ready_for_match:
				break
			await create_timer(0.02).timeout
		check(a.ready_for_match and a.player_id == original_id, "Reconnect resumes reserved original player slot")
		var active = a if a.player_id == "blue_1" else b
		var command = load("res://scripts/core/turns/player_action_command.gd").new()
		command.player_id = active.player_id
		command.weapon_id = 1
		command.shot_power = 1.0
		command.aim_direction = Vector3.DOWN
		active.send_command(command)
		for attempt in range(300):
			if a.runner.state.turn_id > 0 and b.runner.state.turn_id > 0:
				break
			await create_timer(0.02).timeout
		check(a.runner.world.material_ids == server.runner.world.material_ids and b.runner.world.health_values == server.runner.world.health_values, "Validated result applies coherent terrain on both clients")
		var intruder = Client.new()
		root.add_child(intruder)
		intruder.connect_to_server("127.0.0.1", 19176)
		intruder.resume_token = "invalid-token"
		for attempt in range(100):
			if intruder.connection_state == "error":
				break
			await create_timer(0.02).timeout
		check(not intruder.ready_for_match and intruder.last_error == "invalid_or_expired_resume_token", "Invalid resume token rejected without slot assignment")
		intruder.close()
		intruder.queue_free()
		var before_revision: int = a.runner.state.revision
		var gapped_state: Dictionary = server.runner.state_snapshot()
		gapped_state.revision += 3
		a._handle({"type": "state", "state": gapped_state, "terrain_revision": a.terrain_revision + 1})
		check(not a.ready_for_match and a.runner.state.revision == before_revision, "Live missing-delta detection preserves published state")
		for attempt in range(200):
			if a.ready_for_match:
				break
			await create_timer(0.02).timeout
		check(a.ready_for_match and a.runner.world.health_values == server.runner.world.health_values, "Gap automatically recovers from server snapshot")
		server.reservation_seconds = 0.1
		var expired_token: String = a.resume_token
		a.close()
		await create_timer(0.3).timeout
		check(not server.reservations.has(expired_token), "Disconnected reservation expires")
		a.connect_to_server("127.0.0.1", 19176)
		for attempt in range(100):
			if a.connection_state == "error":
				break
			await create_timer(0.02).timeout
		check(a.last_error == "invalid_or_expired_resume_token", "Expired resume token cannot reclaim slot")
		check(a.resume_token.is_empty(), "Explicit expired-token rejection clears stale token for retry")
		a.retry_connection()
		for attempt in range(200):
			if a.ready_for_match:
				break
			await create_timer(0.02).timeout
		check(a.ready_for_match and not a.resume_token.is_empty() and a.resume_token != expired_token, "Explicit retry after expiry obtains fresh vacant slot")
	a.close()
	b.close()
	server.close()
	a.queue_free()
	b.queue_free()
	server.queue_free()
	print("Network50: %d failures" % failures)
	quit(1 if failures else 0)
