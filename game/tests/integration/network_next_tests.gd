extends SceneTree
const P = preload("res://scripts/networking/messages/match_protocol.gd")
const F = preload("res://scripts/core/rules/match_factory.gd")
const C = preload("res://scripts/networking/transport/match_client.gd")
const S = preload("res://scripts/networking/transport/match_server.gd")
class Capture:
	extends "res://scripts/networking/transport/match_server.gd"
	var last := {}
	func _send(_id: int, data: Dictionary) -> void:
		last = data
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var runner = F.create_match(2)
	for malformed in [null, {}, 42, {"id":null}, {"id":[]}]:
		var malformed_state: Dictionary = runner.state_snapshot()
		malformed_state.players[0] = malformed
		check(P.decode_state(malformed_state) == null, "Malformed player summary rejects without script error")
	var bad = runner.state_snapshot()
	bad.players[0].rotation = [1,0,0,0.5,1,0,0,0,1]
	check(P.decode_state(bad) == null, "Sheared determinant-one rotation must be rejected")
	var server = S.new()
	check(server.get("diagnostics") is Dictionary, "Server exposes bounded diagnostics")
	for i in range(101):
		server._allow_packet(77, 10)
	check(server.diagnostics.rejections == 1 and server.diagnostics.packets == 101, "Packet flood counted")
	server.close()
	check(server.diagnostics.packets == 0, "Session counters reset")
	server.free()
	var capture = Capture.new()
	capture.runner = runner
	capture.slots = {2:"blue_1", 3:"red_1"}
	capture._handle(2, {"type":"nonsense"})
	check(capture.last.reason == "unknown_message", "Unknown intent has bounded reason")
	capture.rejection_times.clear()
	capture._handle(2, {"type":"move", "turn_id":0,"generation":0,"axis":[INF,0],"yaw":0,"jump":false})
	check(capture.last.reason == "invalid_move", "Malformed movement has readable reason")
	capture.free()
	var draw = F.create_match(2)
	draw.rules.max_turns = 1
	draw.tick(100)
	check(P.decode_state(draw.state_snapshot()) != null and draw.state.status == "ended", "Turn-limit draw accepts multiple surviving teams")
	check(P.valid_configured_state(draw.state, draw), "Configured draw accepts reached turn limit")
	draw.rules.max_turns = 0
	check(not P.valid_configured_state(draw.state, draw), "Unlimited match cannot claim living-player draw")
	var config = P.encode_configuration(runner)
	check(not P.decode_configuration(config).is_empty(), "Rules and weapons roundtrip")
	config.rules.wind = 99999
	check(P.decode_configuration(config).is_empty(), "Invalid configuration rejected")
	config = P.encode_configuration(runner)
	var client = C.new()
	client.runner = runner
	var original = client.runner
	var size: Vector3i = runner.world.size
	var edge: int = runner.world.chunk_size
	var count := ceili(float(size.x)/edge)*ceili(float(size.y)/edge)*ceili(float(size.z)/edge)
	var begin := {"type":"snapshot_begin", "transfer_id":1, "configuration":config, "phase":"waiting", "player_id":"blue_1", "size":[size.x,size.y,size.z], "chunk_size":edge, "chunk_count":count, "terrain_revision":0,"generation":0,"revision":0}
	var missing = begin.duplicate(true)
	missing.erase("configuration")
	client._handle(missing)
	check(client.staging == null and client.runner == original, "Configless transfer rejected before allocation")
	missing = begin.duplicate(true)
	missing.erase("transfer_id")
	client._handle(missing)
	check(client.staging == null and client.runner == original, "Missing transfer identity rejected")
	var invalid_begin = begin.duplicate(true)
	invalid_begin.configuration.weapons["1"].projectile_speed = -1
	client._handle(invalid_begin)
	check(client.runner == original and client.staging == null, "Bad config never publishes runner")
	client._handle(begin)
	check(client.snapshot_progress.total == count, "Progress starts from metadata")
	var chunk := {"type":"chunk", "transfer_id":1, "chunk":P.chunk_snapshot(runner.world, Vector3i.ZERO)}
	client._handle(chunk)
	check(client.snapshot_progress.completed == 1, "Progress counts validated chunks")
	client._handle(chunk)
	check(client.staging == null and client.runner == original and client.snapshot_progress.total == 0, "Duplicate chunk aborts atomically")
	client._handle(begin)
	chunk.transfer_id = 2
	client._handle(chunk)
	check(client.staging == null and client.runner == original, "Mixed transfer rejected")
	client._handle(begin)
	client.ready_for_match = true
	client.snapshot_metadata = begin
	bad = runner.state_snapshot()
	bad.players[0].position = [999, 2, 2]
	client._handle({"type":"state","state":bad,"terrain_revision":0})
	check(not client.ready_for_match and client.runner.state.players[0].position.x != 999, "Arena bounds reject atomically")
	client.ready_for_match = true
	bad = runner.state_snapshot()
	bad.revision = 1
	bad.players[0].position = [999,2,2]
	var checksum := P.terrain_checksum(runner.world)
	client._handle({"type":"result", "base_terrain_revision":0,"terrain_revision":1,"result":{"version":P.VERSION,"ok":true,"reason":"ok","state":bad,"events":[],"path":[[0,0,0]],"deltas":[{"position":[0,0,0],"material_id":0,"health":0}]}})
	check(not client.ready_for_match and P.terrain_checksum(runner.world) == checksum, "Invalid result position cannot mutate terrain")
	bad = runner.state_snapshot()
	bad.statistics.blue_1.shots = -1
	check(P.decode_state(bad) == null, "Malformed statistics rejected")
	bad = runner.state_snapshot()
	bad.players[0].rotation = [-1,0,0,0,1,0,0,0,1]
	check(P.decode_state(bad) == null, "Reflection rejected")
	client.free()
	server = S.new()
	root.add_child(server)
	check(server.start(19177, "res://maps/twin_forts.toml", "quick") == OK, "Isolated ENet server binds")
	server.runner.rules.wind = 3.5
	var a = C.new()
	var b = C.new()
	root.add_child(a)
	root.add_child(b)
	a.connect_to_server("127.0.0.1",19177)
	for i in range(250):
		if a.ready_for_match: break
		await create_timer(0.02).timeout
	check(a.ready_for_match and a.match_phase == "waiting", "First client waits")
	var timer: float = server.runner.state.time_remaining
	await create_timer(0.15).timeout
	check(server.runner.state.time_remaining == timer, "Waiting freezes clock")
	b.connect_to_server("127.0.0.1",19177)
	for i in range(250):
		if b.ready_for_match and a.match_phase == "playing" and a.latency_ms >= 0: break
		await create_timer(0.02).timeout
	check(a.ready_for_match and b.ready_for_match and a.match_phase == "playing", "Two clients enter playing")
	check(a.latency_ms >= 0 and a.ping_pending == -1, "Real ENet measures bounded RTT")
	check(a.runner.rules.preset == "quick" and a.runner.rules.wind == 3.5 and P.encode_configuration(a.runner) == P.encode_configuration(server.runner), "Authoritative preview config survives transport")
	var revision: int = server.runner.state.revision
	a._send({"type":"ping","nonce":27})
	await create_timer(0.1).timeout
	check(server.runner.state.revision == revision, "Heartbeat never changes revision")
	a._send({"type":"surrender","player_id":b.player_id})
	await create_timer(0.1).timeout
	check(server.runner.state.status == "playing", "Surrender cannot spoof other slot")
	var actor = a if a.player_id == "blue_1" else b
	var command = load("res://scripts/core/turns/player_action_command.gd").new()
	command.player_id = actor.player_id
	command.weapon_id = 1
	command.aim_direction = Vector3.DOWN
	command.shot_power = 1.0
	actor.send_command(command)
	for i in range(250):
		if a.runner.history.size() == 1 and b.runner.history.size() == 1: break
		await create_timer(0.02).timeout
	check(a.runner.statistics == server.runner.statistics and a.runner.history == server.runner.history and a.runner.history.size() == 1, "Shot summaries synchronized")
	for i in range(250):
		if a.match_phase != "playback": break
		await create_timer(0.02).timeout
	var original_id: String = a.player_id
	a.close()
	await create_timer(0.1).timeout
	a.retry_connection()
	for i in range(250):
		if a.ready_for_match: break
		await create_timer(0.02).timeout
	check(a.ready_for_match and a.player_id == original_id and a.runner.history == server.runner.history and a.runner.statistics == server.runner.statistics, "Reconnect restores summaries and identity")
	a.surrender()
	for i in range(250):
		if a.match_phase == "ended" and b.match_phase == "ended": break
		await create_timer(0.02).timeout
	check(a.runner.state.status == "ended" and b.runner.state.status == "ended", "Peer surrender synchronizes winner")
	revision = server.runner.state.revision
	a._send({"type":"surrender"})
	await create_timer(0.1).timeout
	check(server.runner.state.revision == revision, "Repeat surrender rejected")
	server.graceful_shutdown()
	for i in range(100):
		if a.last_error == "server_shutdown" and b.last_error == "server_shutdown": break
		await create_timer(0.02).timeout
	check(a.last_error == "server_shutdown" and not a.ready_for_match and b.last_error == "server_shutdown", "Graceful shutdown arrives before transport closes")
	a.close()
	b.close()
	server.close()
	a.queue_free()
	b.queue_free()
	server.queue_free()
	print("Network next: %d failures" % failures)
	quit(1 if failures else 0)
