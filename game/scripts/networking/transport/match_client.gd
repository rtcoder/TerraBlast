class_name MatchClient
extends Node
signal snapshot_progress_changed(completed: int, total: int)
signal lobby_changed
var lobby_state: Dictionary = {}
signal synchronized
signal result_received(result: Dictionary)
signal status_changed(message: String)
signal connection_state_changed(state: String)
const Protocol := preload("res://scripts/networking/messages/match_protocol.gd")
const Factory := preload("res://scripts/core/rules/match_factory.gd")
const World := preload("res://scripts/core/voxels/voxel_world_data.gd")
var match_phase := "waiting"
var latency_ms := -1
var snapshot_progress := {"completed": 0, "total": 0}
var ping_pending := -1
var ping_sent_at := 0
var ping_elapsed := 0.0
var peer: ENetMultiplayerPeer
var runner: RefCounted
var staging: RefCounted
var chunks := {}
var player_id := ""
var ready_for_match := false
var last_result: Dictionary = {}
var timeout := 0.0
var had_connection := false
var connection_state := "disconnected"
var last_error := ""
var resume_token := ""
var terrain_revision := 0
var snapshot_metadata := {}
var last_host := "127.0.0.1"
var last_port := 19170
var recovery_wait := 0.0
var hello_sent := false

func _status(state: String, message: String) -> void:
	connection_state = state
	connection_state_changed.emit(state)
	status_changed.emit(message)

func _fail(message: String) -> void:
	close()
	last_error = message
	_status("error", message)

func connect_to_server(host: String = "127.0.0.1", port: int = 19170) -> Error:
	close()
	if host != last_host or port != last_port:
		resume_token = ""
	last_host = host
	last_port = port
	if runner == null:
		runner = Factory.create_match(2)
	peer = ENetMultiplayerPeer.new()
	timeout = 0.0
	had_connection = false
	hello_sent = false
	last_error = ""
	_status("connecting", "Connecting to %s:%d" % [host, port])
	var error := peer.create_client(host, port)
	if error != OK:
		_fail("Cannot connect: " + error_string(error))
	return error

func retry_connection() -> Error:
	return connect_to_server(last_host, last_port)

func _process(delta: float) -> void:
	if peer == null:
		return
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		peer.poll()
	timeout += delta
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		if had_connection or timeout > 10:
			_fail("Disconnected. Retry to resume your player slot.")
		return
	had_connection = peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	if had_connection and not hello_sent:
		hello_sent = true
		_send({"type": "hello", "resume_token": resume_token})
	if not ready_for_match and timeout > 15:
		_fail("Server snapshot timed out. Retry connection.")
		return
	ping_elapsed += delta
	if had_connection and ping_elapsed >= 1.0:
		ping_elapsed = 0.0
		if ping_pending == -1 or Time.get_ticks_msec() - ping_sent_at > 3000:
			ping_sent_at = Time.get_ticks_msec()
			ping_pending = ping_sent_at % 2147483647
			_send({"type": "ping", "nonce": ping_pending})
	if recovery_wait > 0:
		recovery_wait -= delta
		if recovery_wait <= 0:
			_send({"type": "snapshot"})
	for index in range(mini(peer.get_available_packet_count(), 128)):
		_handle(Protocol.unpack(peer.get_packet()))
		if peer == null:
			break

func _handle(data: Dictionary) -> void:
	match data.get("type", ""):
		"lobby_state":
			_accept_lobby(data.get("lobby"))
		"server_shutdown":
			_fail("server_shutdown")
		"pong":
			if ping_pending >= 0 and data.get("nonce") == ping_pending:
				latency_ms = clampi(Time.get_ticks_msec() - ping_sent_at, 0, 60000)
				ping_pending = -1
		"phase":
			_set_phase(data.get("phase"))
		"snapshot_begin":
			if not Protocol.valid_snapshot_metadata(data):
				request_snapshot()
				return
			if data.has("lobby") and (not Protocol.valid_lobby(data.lobby) or data.lobby.generation != data.generation):
				return
			if not lobby_state.is_empty() and data.generation < lobby_state.generation:
				return
			var configuration := Protocol.decode_configuration(data.configuration)
			if configuration.is_empty():
				request_snapshot()
				return
			ready_for_match = false
			player_id = data.player_id
			resume_token = data.get("resume_token", resume_token)
			staging = Factory.create_match(2)
			staging.rules = configuration.rules
			staging.weapons = configuration.weapons
			staging.world = World.new(Vector3i(data.size[0], data.size[1], data.size[2]), int(data.chunk_size))
			snapshot_metadata = data.duplicate(true)
			chunks.clear()
			_progress(0, int(data.chunk_count))
			timeout = 0.0
			recovery_wait = 0.0
			_status("synchronizing", "Synchronizing arena…")
		"chunk":
			var chunk = data.get("chunk")
			if staging == null or not chunk is Dictionary or data.get("transfer_id") != snapshot_metadata.get("transfer_id") or chunks.has(str(chunk.get("chunk"))) or not Protocol.apply_chunk(staging.world, chunk):
				request_snapshot()
				return
			chunks[str(chunk.chunk)] = true
			_progress(chunks.size(), int(snapshot_metadata.chunk_count))
		"snapshot_end":
			var state = Protocol.decode_state(data.get("state"))
			if staging == null or state == null or data.get("transfer_id") != snapshot_metadata.get("transfer_id") or chunks.size() != snapshot_metadata.get("chunk_count", -1) or data.get("checksum") != Protocol.terrain_checksum(staging.world) or data.get("terrain_revision") != snapshot_metadata.get("terrain_revision") or state.generation != snapshot_metadata.get("generation") or state.revision != snapshot_metadata.get("revision"):
				request_snapshot()
				return
			if not state.players.any(func(player): return player.player_id == player_id):
				request_snapshot()
				return
			if not Protocol.valid_configured_state(state, staging):
				request_snapshot()
				return
			staging.initial_materials = staging.world.material_ids.duplicate()
			staging.initial_health = staging.world.health_values.duplicate()
			staging.state = state
			if snapshot_metadata.has("lobby"):
				_accept_lobby(snapshot_metadata.lobby)
			last_result.clear()
			runner = staging
			_summary(data.state)
			_set_phase(snapshot_metadata.get("phase", "playing"))
			staging = null
			terrain_revision = int(data.terrain_revision)
			ready_for_match = true
			recovery_wait = 0.0
			last_error = ""
			synchronized.emit()
			_status("connected", "Connected as " + player_id)
		"state":
			var state = Protocol.decode_state(data.get("state"))
			if not ready_for_match or state == null:
				return
			if state.generation < runner.state.generation:
				return
			if state.generation != runner.state.generation or state.revision > runner.state.revision + 1 or data.get("terrain_revision", 0) != terrain_revision:
				request_snapshot()
				return
			if not Protocol.valid_configured_state(state, runner):
				request_snapshot()
				return
			if state.revision >= runner.state.revision:
				runner.state = state
				_summary(data.state)
				_set_phase(data.get("phase", match_phase))
				synchronized.emit()
		"result":
			if not ready_for_match:
				return
			var result = data.get("result")
			if not Protocol.valid_result(result):
				request_snapshot()
				return
			var state = Protocol.decode_state(result.state)
			if state.generation < runner.state.generation:
				return
			if state.generation == runner.state.generation and int(data.get("terrain_revision", -1)) <= terrain_revision:
				return
			if state.generation != runner.state.generation or state.revision > runner.state.revision + 1 or data.get("base_terrain_revision") != terrain_revision or data.get("terrain_revision") != terrain_revision + 1:
				request_snapshot()
				return
			if not Protocol.valid_configured_state(state, runner):
				request_snapshot()
				return
			if not Protocol.apply_deltas(runner.world, result.deltas):
				request_snapshot()
				return
			terrain_revision = int(data.terrain_revision)
			runner.state = state
			_summary(result.state)
			_set_phase(data.get("phase", "playback"))
			last_result = result
			var decoded: Dictionary = result.duplicate(true)
			decoded.path = Protocol.decode_path(result.path)
			result_received.emit(decoded)
		"rejected":
			var reason: String = str(data.get("reason", "Rejected"))
			if data.get("fatal", false):
				if reason == "invalid_or_expired_resume_token":
					resume_token = ""
				_fail(reason)
			else:
				status_changed.emit(reason)

func send_command(command: RefCounted) -> void:
	if ready_for_match and match_phase == "playing":
		_send({"type": "command", "command": Protocol.encode_command(command)})

func request_snapshot() -> void:
	timeout = 0.0
	ready_for_match = false
	staging = null
	chunks.clear()
	_progress(0, 0)
	_status("synchronizing", "Recovering arena snapshot…")
	_send({"type": "snapshot"})
	# If the server's snapshot rate limit rejected this request, retry once the window expires.
	recovery_wait = 1.2

func restart_match() -> void:
	_send({"type": "restart"})

func _send(data: Dictionary) -> void:
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	data.version = Protocol.VERSION
	peer.set_target_peer(1)
	peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	peer.put_packet(Protocol.packet(data))

func close() -> void:
	if peer != null:
		peer.close()
		peer = null
	ready_for_match = false
	lobby_state.clear()
	lobby_changed.emit()
	staging = null
	recovery_wait = 0.0
	connection_state = "disconnected"
	match_phase = "waiting"
	latency_ms = -1
	ping_pending = -1
	ping_elapsed = 0.0
	_progress(0, 0)

func _exit_tree() -> void:
	close()

func move_player(axis: Vector2, yaw: float, jump: bool = false) -> void:
	if ready_for_match and match_phase == "playing":
		_send({"type": "move", "axis": [axis.x, axis.y], "yaw": yaw, "jump": jump, "turn_id": runner.state.turn_id, "generation": runner.state.generation})

func _progress(completed: int, total: int) -> void:
	snapshot_progress = {"completed": completed, "total": total}
	snapshot_progress_changed.emit(completed, total)

func _set_phase(value: Variant) -> void:
	if value is String and value in ["waiting", "playing", "playback", "ended"]:
		match_phase = value
		status_changed.emit("Waiting for second player" if value == "waiting" else value)

func _summary(data: Dictionary) -> void:
	runner.statistics = data.get("statistics", {}).duplicate(true)
	for row in runner.statistics.values():
		for key in row:
			row[key] = int(row[key])
	runner.history.assign(data.get("history", []).duplicate(true))
	for row in runner.history:
		for key in ["weapon_id", "turn_id", "damage", "kills", "terrain_changes", "terrain_destroyed"]:
			row[key] = int(row[key])

func surrender() -> void:
	if ready_for_match and match_phase in ["playing", "waiting"]:
		_send({"type": "surrender"})

func _accept_lobby(value: Variant) -> void:
	if not Protocol.valid_lobby(value):
		return
	if not lobby_state.is_empty() and value.generation < lobby_state.generation:
		return
	lobby_state = value.duplicate(true)
	lobby_changed.emit()

func set_ready(value: bool) -> void:
	_send({"type": "ready", "ready": value, "generation": lobby_state.get("generation", -1)})

func set_display_name(value: String) -> void:
	_send({"type": "display_name", "name": value, "generation": lobby_state.get("generation", -1)})

func vote_rematch(value: bool) -> void:
	_send({"type": "rematch", "vote": value, "generation": lobby_state.get("generation", -1)})
