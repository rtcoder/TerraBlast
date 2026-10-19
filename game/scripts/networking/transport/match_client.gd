class_name MatchClient
extends Node
signal chat_changed
signal chat_rejected(nonce:String,reason:String)
const Chat=preload("res://scripts/networking/messages/lobby_chat.gd")
var requested_role:="player"
var role:="player"
var spectator_id:=""
var chat_enabled:=false
var chat_messages:Array=[]
var chat_generation:=-1
var chat_sequence:=0
var chat_request_at:=-2000
var chat_pending:Dictionary={}
signal snapshot_progress_changed(completed: int, total: int)
signal metrics_changed
signal rejected(reason: String)
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
const Endpoints = preload("res://scripts/client/backend/connection_profiles.gd")
const SYNC_DEADLINE := 45.0
const SYNC_IDLE := 10.0
var sync_age := 0.0
var sync_idle := 0.0
var recovery_attempts := 0
var last_pong_at := -1
var last_send_error := OK
var newest_transfer := -1

func _status(state: String, message: String) -> void:
	connection_state = state
	connection_state_changed.emit(state)
	status_changed.emit(message)

func _fail(message: String) -> void:
	close()
	last_error = message
	_status("error", message)

func connect_to_server(host: String = "127.0.0.1", port: int = 19170, connection_role:String="player") -> Error:
	if connection_role not in ["player","spectator"] or not Endpoints.valid_host(host) or port<1 or port>65535:
		return ERR_INVALID_PARAMETER
	close()
	sync_age=0.0
	sync_idle=0.0
	recovery_attempts=0
	newest_transfer=-1
	if host != last_host or port != last_port or connection_role!=requested_role:
		resume_token = ""
	requested_role=connection_role
	role=connection_role
	spectator_id=""
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
	return connect_to_server(last_host, last_port, requested_role)

func _process(delta: float) -> void:
	if not chat_pending.is_empty() and Time.get_ticks_msec()-int(chat_pending.at)>5000:
		var nonce:String=chat_pending.nonce
		chat_pending.clear()
		chat_rejected.emit(nonce,"chat_confirmation_timeout")
	if peer == null:
		return
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		peer.poll()
	timeout += delta
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		if had_connection or timeout > 10:
			_fail("Disconnected. Retry to resume your %s slot." % requested_role)
		return
	had_connection = peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	if had_connection and not hello_sent:
		hello_sent = true
		_send({"type": "hello", "resume_token": resume_token,"role":requested_role,"extensions":["spectators_v1","chat_v1"]})
	if had_connection and _sync_watchdog(delta): return
	if not ready_for_match and not had_connection and timeout > 15:
		_fail("Server snapshot timed out. Retry connection.")
		return
	if latency_ms>=0 and last_pong_at>=0 and Time.get_ticks_msec()-last_pong_at>5000:
		latency_ms=-1
		metrics_changed.emit()
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
			request_snapshot()
	for index in range(mini(peer.get_available_packet_count(), 128)):
		var source := peer.get_packet_peer()
		var bytes := peer.get_packet()
		if source == 1: _handle(Protocol.unpack(bytes))
		if peer == null:
			break

func _handle(data: Dictionary) -> void:
	if data.get("type") in ["pong","phase","server_shutdown","rejected"] and not Protocol.valid_control(data): return
	match data.get("type", ""):
		"chat_event":
			_accept_chat_event(data.get("event"))
		"chat_history":
			if data.get("enabled") is bool: _accept_chat_history(data.get("history"),data.enabled)
		"chat_rejected":
			if data.get("nonce") is String and data.get("reason") is String and data.reason.length()<=64:
				if chat_pending.get("nonce")==data.nonce: chat_pending.clear()
				chat_rejected.emit(data.nonce,data.reason)
		"lobby_state":
			_accept_lobby(data.get("lobby"))
		"server_shutdown":
			_fail("server_shutdown")
		"pong":
			if ping_pending >= 0 and data.get("nonce") == ping_pending:
				latency_ms = clampi(Time.get_ticks_msec() - ping_sent_at, 0, 60000)
				ping_pending = -1
				last_pong_at = Time.get_ticks_msec()
				metrics_changed.emit()
		"phase":
			_set_phase(data.get("phase"))
		"snapshot_begin":
			if data.get("role","player")!=requested_role:
				_fail("unsupported_spectator_server" if requested_role=="spectator" else "unexpected_server_role")
				return
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
			if int(data.transfer_id)<newest_transfer or (int(data.transfer_id)==newest_transfer and staging!=null): return
			newest_transfer=int(data.transfer_id)
			if ready_for_match: sync_age=0.0; sync_idle=0.0; recovery_attempts=0
			ready_for_match = false
			player_id = data.player_id
			role=data.get("role","player")
			spectator_id=data.get("spectator_id","")
			if chat_generation!=int(data.generation): _clear_chat(int(data.generation))
			chat_enabled=data.get("chat_enabled",false)==true
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
			if Protocol.integer(data.get("transfer_id"),0,2147483647) and data.transfer_id<newest_transfer: return
			var chunk = data.get("chunk")
			if staging == null or not chunk is Dictionary or data.get("transfer_id") != snapshot_metadata.get("transfer_id") or chunks.has(str(chunk.get("chunk"))) or not Protocol.apply_chunk(staging.world, chunk):
				request_snapshot()
				return
			chunks[str(chunk.chunk)] = true
			sync_idle=0.0
			_progress(chunks.size(), int(snapshot_metadata.chunk_count))
		"snapshot_end":
			if Protocol.integer(data.get("transfer_id"),0,2147483647) and data.transfer_id<newest_transfer: return
			var state = Protocol.decode_state(data.get("state"))
			if staging == null or state == null or data.get("transfer_id") != snapshot_metadata.get("transfer_id") or chunks.size() != snapshot_metadata.get("chunk_count", -1) or data.get("checksum") != Protocol.terrain_checksum(staging.world) or data.get("terrain_revision") != snapshot_metadata.get("terrain_revision") or state.generation != snapshot_metadata.get("generation") or state.revision != snapshot_metadata.get("revision"):
				request_snapshot()
				return
			if role=="player" and not state.players.any(func(player): return player.player_id == player_id):
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
			sync_age=0.0; sync_idle=0.0; recovery_attempts=0
			recovery_wait = 0.0
			last_error = ""
			synchronized.emit()
			_status("connected", "Connected as " + (spectator_id+" (spectator)" if role=="spectator" else player_id))
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
				rejected.emit(reason)
				status_changed.emit(reason)

func send_command(command: RefCounted) -> void:
	if role=="player" and ready_for_match and match_phase == "playing":
		_send({"type": "command", "command": Protocol.encode_command(command)})

func request_snapshot() -> void:
	if ready_for_match: sync_age=0.0; sync_idle=0.0
	ready_for_match=false
	staging=null
	chunks.clear()
	timeout=0.0
	if recovery_wait>0: return
	if recovery_attempts>=5:
		_fail("snapshot_retries_exhausted")
		return
	recovery_attempts+=1
	ready_for_match=false
	staging=null
	chunks.clear()
	_progress(0,0)
	_status("synchronizing","Recovering arena snapshot…")
	_send({"type":"snapshot"})
	recovery_wait=minf(5.0,1.2*recovery_attempts)

func restart_match() -> void:
	if role!="player": return
	_send({"type": "restart"})

func _send(data: Dictionary) -> Error:
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	data.version = Protocol.VERSION
	peer.set_target_peer(1)
	peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	last_send_error=peer.put_packet(Protocol.packet(data))
	if last_send_error!=OK:
		last_error="send_failed: " + error_string(last_send_error)
		status_changed.emit(last_error)
	return last_send_error

func close() -> void:
	_clear_chat(-1)
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
	last_pong_at=-1
	ping_pending = -1
	ping_elapsed = 0.0
	_progress(0, 0)

func _exit_tree() -> void:
	close()

func move_player(axis: Vector2, yaw: float, jump: bool = false) -> void:
	if role=="player" and ready_for_match and match_phase == "playing":
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
	if role=="player" and ready_for_match and match_phase in ["playing", "waiting"]:
		_send({"type": "surrender"})

func _accept_lobby(value: Variant) -> void:
	if not Protocol.valid_lobby(value):
		return
	if not lobby_state.is_empty() and value.generation < lobby_state.generation:
		return
	lobby_state = value.duplicate(true)
	lobby_changed.emit()

func set_ready(value: bool) -> void:
	if role!="player": return
	_send({"type": "ready", "ready": value, "generation": lobby_state.get("generation", -1)})

func set_display_name(value: String) -> void:
	_send({"type": "display_name", "name": value, "generation": lobby_state.get("generation", -1)})

func vote_rematch(value: bool) -> void:
	if role!="player": return
	_send({"type": "rematch", "vote": value, "generation": lobby_state.get("generation", -1)})

func forget_resume() -> void: resume_token=""
func leave() -> void:
	if _send({"type":"leave"})==OK and peer!=null:
		if is_inside_tree():
			var delivery=preload("res://scripts/networking/transport/leave_delivery.gd").new()
			get_tree().root.add_child(delivery)
			delivery.begin(peer)
			peer=null
		else: peer.host.flush()
	close()
	forget_resume()
func status_snapshot() -> Dictionary:
	return {"role":role,"requested_role":requested_role,"spectator_id":spectator_id,"state":connection_state,"host":last_host,"port":last_port,"phase":match_phase,"progress":snapshot_progress.duplicate(),"latency_ms":latency_ms,"last_error":last_error,"can_retry":connection_state in ["error","disconnected"],"recovery_attempts":recovery_attempts}

func _sync_watchdog(delta: float) -> bool:
	if ready_for_match: return false
	sync_age+=delta
	sync_idle+=delta
	if sync_age>SYNC_DEADLINE:
		_fail("snapshot_overall_timeout")
		return true
	if sync_idle>SYNC_IDLE:
		_fail("snapshot_idle_timeout")
		return true
	return false

func _clear_chat(generation:int)->void:
	chat_generation=generation; chat_sequence=0; chat_enabled=false
	chat_messages.clear(); chat_pending.clear(); chat_request_at=-2000
	chat_changed.emit()

func chat_snapshot()->Dictionary:
	return {"generation":maxi(0,chat_generation),"first_sequence":chat_messages[0].sequence if not chat_messages.is_empty() else chat_sequence+1,"messages":chat_messages.duplicate(true),"enabled":chat_enabled,"pending_nonce":chat_pending.get("nonce","")}

func send_chat(text:String)->Dictionary:
	if not ready_for_match or not chat_enabled: return {"ok":false,"reason":"chat_unavailable"}
	if not Chat.valid_text(text): return {"ok":false,"reason":"invalid_chat"}
	if not chat_pending.is_empty(): return {"ok":false,"reason":"chat_pending"}
	var nonce:String=Crypto.new().generate_random_bytes(16).hex_encode()
	var error:Error=_send({"type":"chat_send","text":text,"nonce":nonce,"generation":runner.state.generation})
	if error!=OK: return {"ok":false,"reason":"chat_send_failed"}
	chat_pending={"nonce":nonce,"at":Time.get_ticks_msec()}
	return {"ok":true,"reason":"","nonce":nonce}

func _request_chat_history()->void:
	var now:int=Time.get_ticks_msec()
	if now-chat_request_at<1000: return
	chat_request_at=now
	_send({"type":"chat_history_request"})

func _accept_chat_history(value:Variant,enabled:bool)->void:
	if not ready_for_match or not Chat.valid_history(value) or value.generation!=runner.state.generation: return
	var latest:int=int(value.first_sequence)+value.messages.size()-1
	if value.generation==chat_generation and latest<chat_sequence: return
	chat_generation=int(value.generation); chat_sequence=latest
	chat_messages=value.messages.duplicate(true); chat_enabled=enabled
	for row in chat_messages: _ack_chat(row)
	chat_changed.emit()

func _ack_chat(event:Dictionary)->void:
	var own:String=spectator_id if role=="spectator" else player_id
	if event.author_id==own and event.nonce==chat_pending.get("nonce",""): chat_pending.clear()

func _accept_chat_event(value:Variant)->void:
	if not ready_for_match or not Chat.valid_event(value) or value.generation!=runner.state.generation: return
	_ack_chat(value)
	if value.sequence<=chat_sequence: return
	if chat_generation!=int(value.generation) or value.sequence!=chat_sequence+1:
		_request_chat_history(); return
	chat_sequence=int(value.sequence)
	chat_messages.append(value.duplicate(true))
	while chat_messages.size()>Chat.MAX_MESSAGES or JSON.stringify(chat_messages).to_utf8_buffer().size()>Chat.MAX_BYTES: chat_messages.pop_front()
	chat_changed.emit()
