class_name MatchServer
extends Node
const Factory := preload("res://scripts/core/rules/match_factory.gd")
const Protocol := preload("res://scripts/networking/messages/match_protocol.gd")
var diagnostics := {"packets": 0, "bytes": 0, "rejections": 0, "snapshots": 0,"sent_packets":0,"sent_bytes":0,"send_failures":0}
const FrozenWorld=preload("res://scripts/core/voxels/voxel_world_data.gd")
const Options=preload("res://scripts/networking/transport/server_runtime_options.gd")
var runtime_options=Options.new()
var snapshot_queues := {}
var rejected_disconnects := {}
var last_send_error := OK
var _draining := false
var _round_robin := 0
var started_at := 0
var last_receive_bytes := 0
var last_receive_packets := 0
var match_phase := "waiting"
var capacity := 2
var require_ready := false
var started := false
var ready_slots := {}
var rematch_votes := {}
var lobby_budgets := {}
var ping_times := {}
var rejection_times := {}
var transfer_serial := 0
var shutdown_remaining := 0.0
var shutting_down := false
var peer: ENetMultiplayerPeer
var runner: RefCounted
var slots := {}
var transport_peers := {}
var snapshot_times := {}
var restart_times := {}
var playback_remaining := 0.0
var state_timer := 0.0
var motion := {}
var velocities := {}
var terrain_revision := 0
var reservations := {}
var peer_tokens := {}
var pending := {}
var packet_budgets := {}
var reservation_seconds := 30.0
const MAX_PACKETS_PER_SECOND := 100
const MAX_BYTES_PER_SECOND := 65536
const Motion := preload("res://scripts/core/rules/player_motion.gd")

func start(port: int = 19170, map_path: String = "res://maps/twin_forts.toml", preset: String = "classic", player_count: int = 2, lobby_required: bool = false) -> Error:
	close()
	capacity = player_count
	require_ready = lobby_required
	if capacity < 2 or capacity > 10:
		return ERR_INVALID_PARAMETER
	runner = Factory.create_match(capacity, map_path, preset)
	if runner == null or runner.state.players.size() != capacity:
		return ERR_INVALID_DATA
	peer = ENetMultiplayerPeer.new()
	peer.peer_connected.connect(_connected)
	peer.peer_disconnected.connect(_disconnected)
	var error:=peer.create_server(port,16)
	if error==OK: started_at=Time.get_ticks_msec()
	return error

func _connected(id: int) -> void:
	transport_peers[id] = peer.get_peer(id)
	pending[id] = Time.get_ticks_msec()

func _disconnected(id: int) -> void:
	snapshot_queues.erase(id)
	rejected_disconnects.erase(id)
	transport_peers.erase(id)
	if peer_tokens.has(id):
		var token: String = peer_tokens[id]
		reservations[token].peer = 0
		reservations[token].expires = Time.get_ticks_msec() + int(reservation_seconds * 1000)
		peer_tokens.erase(id)
	if slots.has(id):
		ready_slots.erase(slots[id])
		rematch_votes.clear()
		motion.erase(slots[id])
		velocities.erase(slots[id])
	slots.erase(id)
	snapshot_times.erase(id)
	restart_times.erase(id)
	lobby_budgets.erase(id)
	pending.erase(id)
	packet_budgets.erase(id)
	ping_times.erase(id)
	rejection_times.erase(id)
	_update_phase()
	_broadcast_lobby()

func _expire_reservations() -> void:
	var now := Time.get_ticks_msec()
	for token in reservations.keys():
		if reservations[token].peer == 0 and reservations[token].expires <= now:
			reservations.erase(token)
	for id in rejected_disconnects.keys():
		if now>=rejected_disconnects[id]:
			peer.disconnect_peer(id)
			_disconnected(id)
	for id in pending.keys():
		if now - int(pending[id]) > runtime_options.values.hello_seconds*1000:
			peer.disconnect_peer(id)
			_disconnected(id)

func _accept_hello(id: int, data: Dictionary) -> void:
	if not pending.has(id) or rejected_disconnects.has(id): return
	if not Protocol.valid_resume_token(data.get("resume_token")):
		_fatal_hello(id,"invalid_or_expired_resume_token")
		return
	_expire_reservations()
	var token: String = data.resume_token
	var player_id := ""
	if not token.is_empty():
		if not reservations.has(token):
			_fatal_hello(id,"invalid_or_expired_resume_token")
			return
		if reservations[token].peer != 0:
			_fatal_hello(id,"resume_token_in_use")
			return
		player_id = reservations[token].player
	else:
		var reserved := []
		for reservation in reservations.values():
			reserved.append(reservation.player)
		for player in runner.state.players:
			if not reserved.has(player.player_id):
				player_id = player.player_id
				break
		if player_id.is_empty():
			_fatal_hello(id,"match_slots_reserved_or_full")
			return
		token = Crypto.new().generate_random_bytes(32).hex_encode()
	reservations[token] = {"player": player_id, "peer": id, "expires": 0}
	peer_tokens[id] = token
	slots[id] = player_id
	pending.erase(id)
	_maybe_start()
	_update_phase()
	_broadcast_lobby()
	_send_snapshot(id)

func _allow_packet(sender: int, byte_count: int, clock_ms: int = -1) -> bool:
	_count("packets")
	_count("bytes",byte_count)
	var now:=Time.get_ticks_msec() if clock_ms<0 else clock_ms
	var rate: float=runtime_options.values.packets_per_second
	var byte_rate: float=runtime_options.values.bytes_per_second
	var budget: Dictionary=packet_budgets.get(sender,{"at":now,"packets":rate,"bytes":byte_rate})
	var elapsed:=maxf(0.0,(now-int(budget.at))/1000.0)
	budget.packets=minf(rate,float(budget.packets)+elapsed*rate)
	budget.bytes=minf(byte_rate,float(budget.bytes)+elapsed*byte_rate)
	budget.at=now
	var allowed: bool=byte_count>=0 and byte_count<=8192 and budget.packets>=1.0 and budget.bytes>=byte_count
	if allowed:
		budget.packets-=1.0
		budget.bytes-=byte_count
	else: _count("rejections")
	packet_budgets[sender]=budget
	return allowed

func _process(delta: float) -> void:
	if peer == null or peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	peer.poll()
	if shutting_down:
		shutdown_remaining -= delta
		if shutdown_remaining <= 0:
			close()
		return
	_expire_reservations()
	last_receive_bytes=0
	last_receive_packets=0
	for index in range(mini(peer.get_available_packet_count(), 256)):
		if last_receive_bytes>=runtime_options.values.receive_bytes_per_frame: break
		var sender := peer.get_packet_peer()
		var bytes := peer.get_packet()
		last_receive_bytes+=bytes.size()
		last_receive_packets+=1
		if not _allow_packet(sender, bytes.size()):
			continue
		_handle(sender, Protocol.unpack(bytes))
	_drain_snapshots()
	playback_remaining = maxf(0.0, playback_remaining - delta)
	_update_phase()
	if match_phase == "playing":
		var active = runner.state.get_active_player()
		if active != null and runner.state.status == "playing":
			var input: Dictionary = motion.get(active.player_id, {})
			var vector: Vector2 = input.get("vector", Vector2.ZERO) if Time.get_ticks_msec() - int(input.get("at", 0)) < 250 else Vector2.ZERO
			velocities[active.player_id] = Motion.move(runner.world, active, velocities.get(active.player_id, Vector3.ZERO), vector, float(input.get("yaw", 0.0)), input.get("jump", false), minf(delta, 0.05), runner.rules, runner.materials)
			input["jump"] = false
		var events: Array = runner.tick(delta)
		state_timer += delta
		if not events.is_empty() or state_timer >= 0.1:
			state_timer = 0.0
			_broadcast({"type": "state", "state": runner.state_snapshot(), "terrain_revision": terrain_revision, "phase": _phase()})

func _handle(sender: int, data: Dictionary) -> void:
	if shutting_down:
		return
	if data.get("type") == "hello":
		_accept_hello(sender, data)
		return
	if not slots.has(sender):
		return
	match data.get("type", ""):
		"ready", "display_name", "rematch":
			_handle_lobby(sender, data)
		"ping":
			var now := Time.get_ticks_msec()
			if Protocol.integer(data.get("nonce"), 0, 2147483647) and now - int(ping_times.get(sender, -2000)) >= 500:
				ping_times[sender] = now
				_send(sender, {"type": "pong", "nonce": data.nonce})
		"surrender":
			if require_ready and not started:
				_reject(sender, "match_not_started")
				return
			if data.has("player_id") and data.player_id != slots[sender]:
				_reject(sender, "invalid_identity")
				return
			var result: Dictionary = runner.surrender(slots[sender])
			if not result.ok:
				_reject(sender, result.reason)
				return
			motion.clear()
			velocities.clear()
			playback_remaining = 0.0
			_update_phase()
			_broadcast({"type": "state", "state": runner.state_snapshot(), "terrain_revision": terrain_revision, "phase": _phase()})
		"snapshot":
			var now := Time.get_ticks_msec()
			if now - int(snapshot_times.get(sender, -2000)) > 1000:
				snapshot_times[sender] = now
				_send_snapshot(sender)
		"move":
			var active = runner.state.get_active_player()
			if _phase() != "playing" or active == null or slots[sender] != active.player_id or data.get("turn_id") != runner.state.turn_id or data.get("generation") != runner.state.generation or playback_remaining > 0:
				_reject(sender, "not_active_turn")
				return
			var axis = data.get("axis")
			if not axis is Array or axis.size() != 2 or not Protocol.number(axis[0]) or not Protocol.number(axis[1]) or absf(axis[0]) > 1 or absf(axis[1]) > 1 or not Protocol.number(data.get("yaw")) or absf(data.yaw) > 1e6 or not data.get("jump") is bool:
				_reject(sender, "invalid_move")
				return
			motion[active.player_id] = {"vector": Vector2(axis[0], axis[1]), "yaw": data.yaw, "jump": data.jump or motion.get(active.player_id, {}).get("jump", false), "at": Time.get_ticks_msec()}
		"command":
			var command = Protocol.decode_command(data.get("command"))
			if command == null or command.player_id != slots[sender]:
				_reject(sender, "invalid_identity_or_command")
				return
			if _phase() != "playing":
				_reject(sender, "waiting_for_players_or_projectile")
				return
			var result: Dictionary = runner.submit(command)
			if result.ok:
				motion.clear()
				velocities.clear()
				playback_remaining = maxf(0.05, (result.path.size() - 1) * runner.rules.projectile_step)
				terrain_revision += 1
				_broadcast({"type": "result", "result": Protocol.encode_result(result), "base_terrain_revision": terrain_revision - 1, "terrain_revision": terrain_revision, "phase": _phase()})
			else:
				_reject(sender, result.reason)
		"restart":
			if require_ready:
				_reject(sender, "rematch_quorum_required")
				return
			if slots[sender] == "blue_1":
				var now := Time.get_ticks_msec()
				if now - int(restart_times.get(sender, -2000)) < 1000:
					return
				restart_times[sender] = now
				runner.reset()
				terrain_revision = 0
				motion.clear()
				velocities.clear()
				playback_remaining = 0.0
				for id in slots:
					_send_snapshot(id)

		_:
			_reject(sender, "unknown_message")

func _send_snapshot(id: int) -> void:
	if not slots.has(id) or not peer_tokens.has(id): return
	_count("snapshots")
	transfer_serial+=1
	var size: Vector3i=runner.world.size
	var edge: int=runner.world.chunk_size
	var count:=ceili(float(size.x)/edge)*ceili(float(size.y)/edge)*ceili(float(size.z)/edge)
	# Copy terrain once; serialize only the bounded chunk batch on each frame.
	var frozen=FrozenWorld.new(size,edge)
	frozen.material_ids=runner.world.material_ids.duplicate()
	frozen.health_values=runner.world.health_values.duplicate()
	var messages: Array=[{"type":"snapshot_begin","transfer_id":transfer_serial,"configuration":Protocol.encode_configuration(runner),"player_id":slots[id],"resume_token":peer_tokens[id],"size":[size.x,size.y,size.z],"chunk_size":edge,"chunk_count":count,"generation":runner.state.generation,"revision":runner.state.revision,"terrain_revision":terrain_revision,"phase":_phase(),"lobby":lobby_snapshot()}]
	for z in range(ceili(float(size.z)/edge)):
		for y in range(ceili(float(size.y)/edge)):
			for x in range(ceili(float(size.x)/edge)):
				messages.append({"type":"queued_chunk","transfer_id":transfer_serial,"coordinate":Vector3i(x,y,z)})
	messages.append({"type":"snapshot_end","transfer_id":transfer_serial,"state":runner.state_snapshot(),"checksum":Protocol.terrain_checksum(runner.world),"terrain_revision":terrain_revision,"phase":_phase()})
	snapshot_queues[id]={"world":frozen,"messages":messages.duplicate(true),"cursor":0,"catchup":0,"catchup_bytes":0}

func _drain_snapshots() -> void:
	var ids:=snapshot_queues.keys()
	if ids.is_empty(): return
	var sent:=0
	var byte_count:=0
	var chunk_limit: int=runtime_options.values.snapshot_chunks_per_frame
	var byte_limit: int=runtime_options.values.snapshot_bytes_per_frame
	while sent<chunk_limit and not ids.is_empty():
		var id: int=ids[_round_robin%ids.size()]
		_round_robin+=1
		if not snapshot_queues.has(id): ids.erase(id); continue
		var queue: Dictionary=snapshot_queues[id]
		var data: Dictionary=queue.messages[queue.cursor]
		if data.type=="queued_chunk":
			data={"type":"chunk","transfer_id":data.transfer_id,"chunk":Protocol.chunk_snapshot(queue.world,data.coordinate)}
		var packet_size:=_wire_size(data)
		# One indivisible packet may exceed the byte budget, never more than one.
		if sent>0 and byte_count+packet_size>byte_limit: break
		_draining=true
		_send(id,data)
		_draining=false
		if last_send_error!=OK:
			snapshot_queues.erase(id)
			ids.erase(id)
			continue
		queue.cursor+=1
		sent+=1
		byte_count+=packet_size
		if queue.cursor>=queue.messages.size(): snapshot_queues.erase(id); ids.erase(id)
		if byte_count>=byte_limit: break

func _broadcast(data: Dictionary) -> void:
	for id in slots:
		_send(id, data)

func _send(id: int, data: Dictionary) -> void:
	if not _draining and snapshot_queues.has(id) and data.get("type") in ["state","result","phase","lobby_state"]:
		var queue: Dictionary=snapshot_queues[id]
		var size:=_wire_size(data)
		if queue.catchup>=128 or queue.catchup_bytes+size>8*1024*1024:
			_send_snapshot(id)
			return
		queue.messages.append(data.duplicate(true))
		queue.catchup+=1
		queue.catchup_bytes+=size
		return
	last_send_error=_send_packet(id,data)
	if last_send_error==OK:
		_count("sent_packets")
		_count("sent_bytes",_wire_size(data))
	else: _count("send_failures")

func _send_packet(id: int, data: Dictionary) -> Error:
	if peer==null or peer.get_connection_status()==MultiplayerPeer.CONNECTION_DISCONNECTED: return ERR_UNCONFIGURED
	var target: ENetPacketPeer=transport_peers.get(id)
	if target==null or not target.is_active() or target.get_state()!=ENetPacketPeer.STATE_CONNECTED or target.get_channels()<=0: return ERR_UNCONFIGURED
	var envelope:=data.duplicate()
	envelope.version=Protocol.VERSION
	peer.set_target_peer(id)
	peer.transfer_mode=MultiplayerPeer.TRANSFER_MODE_RELIABLE
	return peer.put_packet(Protocol.packet(envelope))

func close() -> void:
	snapshot_queues.clear()
	rejected_disconnects.clear()
	started_at=0
	last_send_error=OK
	if peer != null:
		peer.close()
		peer = null
	for key in diagnostics:
		diagnostics[key] = 0
	ping_times.clear()
	rejection_times.clear()
	shutting_down = false
	shutdown_remaining = 0.0
	match_phase = "waiting"
	started = false
	ready_slots.clear()
	rematch_votes.clear()
	lobby_budgets.clear()
	slots.clear()
	transport_peers.clear()
	reservations.clear()
	peer_tokens.clear()
	pending.clear()
	packet_budgets.clear()
	snapshot_times.clear()
	restart_times.clear()
	motion.clear()
	velocities.clear()
	terrain_revision = 0
	playback_remaining = 0.0
	state_timer = 0.0

func _exit_tree() -> void:
	close()

func _count(key: String, amount: int = 1) -> void:
	diagnostics[key] = mini(2147483647, diagnostics[key] + amount)

func _phase() -> String:
	if runner != null and runner.state.status == "ended":
		return "ended"
	if slots.size() < capacity or (require_ready and not started):
		return "waiting"
	return "playback" if playback_remaining > 0 else "playing"

func _update_phase() -> void:
	var next := _phase()
	if next != match_phase:
		match_phase = next
		_broadcast({"type": "phase", "phase": match_phase})

func _reject(sender: int, reason: String) -> void:
	_count("rejections")
	var now := Time.get_ticks_msec()
	if now - int(rejection_times.get(sender, -1000)) >= 100:
		rejection_times[sender] = now
		_send(sender, {"type": "rejected", "reason": reason.substr(0, 64)})

func graceful_shutdown() -> void:
	if peer == null or shutting_down:
		return
	snapshot_queues.clear()
	shutting_down = true
	shutdown_remaining = 0.25
	_broadcast({"type": "server_shutdown"})
	peer.host.flush()

func lobby_snapshot() -> Dictionary:
	var roster := []
	if runner != null:
		for player in runner.state.players:
			roster.append({"id": player.player_id, "name": player.display_name, "team": player.team_id, "connected": slots.values().has(player.player_id), "ready": ready_slots.get(player.player_id, false), "rematch": rematch_votes.get(player.player_id, false)})
	return {"capacity": capacity, "require_ready": require_ready, "started": started, "generation": runner.state.generation if runner != null else 0, "roster": roster}

func _broadcast_lobby() -> void:
	_broadcast({"type": "lobby_state", "lobby": lobby_snapshot()})

func _maybe_start() -> void:
	if started or slots.size() != capacity:
		return
	for player_id in slots.values():
		if require_ready and not ready_slots.get(player_id, false):
			return
	started = true

func _handle_lobby(sender: int, data: Dictionary) -> void:
	var now := Time.get_ticks_msec()
	var budget: Dictionary = lobby_budgets.get(sender, {"at": now, "count": 0})
	if now - int(budget.at) >= 1000:
		budget = {"at": now, "count": 0}
	budget.count += 1
	lobby_budgets[sender] = budget
	if budget.count > 8:
		_reject(sender, "lobby_rate_limit")
		return
	var player_id: String = slots[sender]
	if data.has("player_id") and data.player_id != player_id:
		_reject(sender, "invalid_identity")
		return
	if data.get("generation") != runner.state.generation or not Protocol.integer(data.get("generation"), 0, 2147483647):
		_reject(sender, "stale_generation")
		return
	match data.type:
		"ready":
			if started or not require_ready or not data.get("ready") is bool:
				_reject(sender, "invalid_ready")
				return
			ready_slots[player_id] = data.ready
		"display_name":
			if started or not Protocol.valid_display_name(data.get("name")):
				_reject(sender, "invalid_display_name")
				return
			var name_value: String = data.name.strip_edges()
			for player in runner.state.players:
				if player.player_id == player_id:
					player.display_name = name_value
			for player in runner.initial_players:
				if player.id == player_id:
					player.name = name_value
			ready_slots.erase(player_id)
			_broadcast({"type": "state", "state": runner.state_snapshot(), "terrain_revision": terrain_revision, "phase": _phase()})
		"rematch":
			if not require_ready or runner.state.status != "ended" or not data.get("vote") is bool:
				_reject(sender, "invalid_rematch")
				return
			rematch_votes[player_id] = data.vote
			if slots.size() == capacity and slots.values().all(func(id): return rematch_votes.get(id, false)):
				runner.reset()
				started = false
				ready_slots.clear()
				rematch_votes.clear()
				terrain_revision = 0
				motion.clear()
				velocities.clear()
				playback_remaining = 0.0
				state_timer = 0.0
				_update_phase()
				_broadcast_lobby()
				for id in slots:
					_send_snapshot(id)
				return
	_maybe_start()
	_update_phase()
	_broadcast_lobby()

func apply_options(candidate: Dictionary) -> Dictionary:
	if peer!=null: return {"ok":false,"reason":"server_running"}
	var result: Dictionary=runtime_options.apply(candidate)
	if result.ok: reservation_seconds=runtime_options.values.reservation_seconds
	return result
func diagnostic_snapshot() -> Dictionary:
	return {"uptime_seconds":maxf(0.0,(Time.get_ticks_msec()-started_at)/1000.0) if started_at>0 else 0.0,"phase":match_phase,"peers":slots.size(),"pending":pending.size(),"reservations":reservations.size(),"transfers":snapshot_queues.size(),"counters":diagnostics.duplicate(),"last_receive_packets":last_receive_packets,"last_receive_bytes":last_receive_bytes,"shutting_down":shutting_down}
func _fatal_hello(id: int, reason: String) -> void:
	_send(id,{"type":"rejected","reason":reason,"fatal":true})
	rejected_disconnects[id]=Time.get_ticks_msec()+250

static func _wire_size(data: Dictionary) -> int:
	var envelope := data.duplicate()
	envelope.version = Protocol.VERSION
	return Protocol.packet(envelope).size()
