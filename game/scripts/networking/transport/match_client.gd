class_name MatchClient
extends Node
signal synchronized
signal result_received(result: Dictionary)
signal status_changed(message: String)
const Protocol := preload("res://scripts/networking/messages/match_protocol.gd")
const Factory := preload("res://scripts/core/rules/match_factory.gd")
var peer: ENetMultiplayerPeer
var runner: RefCounted
var staging: RefCounted
var chunks := {}
var player_id := ""
var ready_for_match := false
var last_result: Dictionary = {}
var timeout := 0.0
var had_connection := false

func connect_to_server(host: String = "127.0.0.1", port: int = 19170) -> Error:
	close()
	runner = Factory.create_match(2)
	peer = ENetMultiplayerPeer.new()
	timeout = 0.0
	had_connection = false
	status_changed.emit("Connecting to %s:%d" % [host, port])
	return peer.create_client(host, port)

func _process(delta: float) -> void:
	if peer == null:
		return
	peer.poll()
	timeout += delta
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		if had_connection or timeout > 10:
			close()
			status_changed.emit("Disconnected. Reconnect from the multiplayer menu.")
		return
	had_connection = peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	if not ready_for_match and timeout > 15:
		close()
		status_changed.emit("Server snapshot timed out.")
		return
	for index in range(mini(peer.get_available_packet_count(), 128)):
		_handle(Protocol.unpack(peer.get_packet()))

func _handle(data: Dictionary) -> void:
	match data.get("type", ""):
		"snapshot_begin":
			if not data.get("player_id") in ["blue_1", "red_1"]:
				return
			ready_for_match = false
			player_id = data.player_id
			staging = Factory.create_match(2)
			chunks.clear()
			timeout = 0.0
		"chunk":
			if staging != null and Protocol.apply_chunk(staging.world, data.get("chunk")):
				chunks[str(data.chunk.chunk)] = true
		"snapshot_end":
			var state = Protocol.decode_state(data.get("state"))
			if staging == null or state == null or chunks.size() != 72:
				status_changed.emit("Incomplete snapshot; reconnect required.")
				return
			staging.state = state
			runner = staging
			staging = null
			ready_for_match = true
			synchronized.emit()
			status_changed.emit("Connected as " + player_id)
		"state":
			var state = Protocol.decode_state(data.get("state"))
			if ready_for_match and state != null and state.generation == runner.state.generation and state.revision >= runner.state.revision:
				runner.state = state
				synchronized.emit()
		"result":
			var result = data.get("result")
			if not ready_for_match or not result is Dictionary or result.get("version") != Protocol.VERSION or result.get("ok") != true or not result.get("reason") is String or not Protocol.valid_events(result.get("events")):
				return
			var state = Protocol.decode_state(result.get("state"))
			var path := Protocol.decode_path(result.get("path"))
			if state == null or path.is_empty() or state.generation != runner.state.generation or state.revision <= runner.state.revision:
				return
			if not Protocol.apply_deltas(runner.world, result.get("deltas")):
				request_snapshot()
				return
			runner.state = state
			last_result = result
			var decoded: Dictionary = result.duplicate(true)
			decoded.path = path
			result_received.emit(decoded)
		"rejected":
			status_changed.emit(str(data.get("reason", "Rejected")))

func send_command(command: RefCounted) -> void:
	if ready_for_match:
		_send({"type": "command", "command": Protocol.encode_command(command)})

func request_snapshot() -> void:
	_send({"type": "snapshot"})

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

func _exit_tree() -> void:
	close()

func move_player(axis: Vector2, yaw: float, jump: bool = false) -> void:
	if ready_for_match:
		_send({"type": "move", "axis": [axis.x, axis.y], "yaw": yaw, "jump": jump, "turn_id": runner.state.turn_id, "generation": runner.state.generation})
