class_name MatchServer
extends Node
const Factory := preload("res://scripts/core/rules/match_factory.gd")
const Protocol := preload("res://scripts/networking/messages/match_protocol.gd")
var diagnostics := {"packets": 0, "bytes": 0, "rejections": 0, "snapshots": 0}
var match_phase := "waiting"
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

func start(port: int = 19170, map_path: String = "res://maps/twin_forts.toml", preset: String = "classic") -> Error:
	close()
	runner = Factory.create_match(2, map_path, preset)
	if runner == null:
		return ERR_INVALID_DATA
	peer = ENetMultiplayerPeer.new()
	peer.peer_connected.connect(_connected)
	peer.peer_disconnected.connect(_disconnected)
	return peer.create_server(port, 16)

func _connected(id: int) -> void:
	transport_peers[id] = peer.get_peer(id)
	pending[id] = Time.get_ticks_msec()

func _disconnected(id: int) -> void:
	transport_peers.erase(id)
	if peer_tokens.has(id):
		var token: String = peer_tokens[id]
		reservations[token].peer = 0
		reservations[token].expires = Time.get_ticks_msec() + int(reservation_seconds * 1000)
		peer_tokens.erase(id)
	if slots.has(id):
		motion.erase(slots[id])
		velocities.erase(slots[id])
	slots.erase(id)
	snapshot_times.erase(id)
	restart_times.erase(id)
	pending.erase(id)
	packet_budgets.erase(id)
	ping_times.erase(id)
	rejection_times.erase(id)
	_update_phase()

func _expire_reservations() -> void:
	var now := Time.get_ticks_msec()
	for token in reservations.keys():
		if reservations[token].peer == 0 and reservations[token].expires <= now:
			reservations.erase(token)
	for id in pending.keys():
		if now - int(pending[id]) > 5000:
			peer.disconnect_peer(id)
			_disconnected(id)

func _accept_hello(id: int, data: Dictionary) -> void:
	if not pending.has(id) or not data.get("resume_token") is String:
		return
	_expire_reservations()
	var token: String = data.resume_token
	var player_id := ""
	if not token.is_empty():
		if not reservations.has(token):
			_send(id, {"type": "rejected", "reason": "invalid_or_expired_resume_token", "fatal": true})
			return
		if reservations[token].peer != 0:
			_send(id, {"type": "rejected", "reason": "resume_token_in_use", "fatal": true})
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
			_send(id, {"type": "rejected", "reason": "match_slots_reserved_or_full", "fatal": true})
			return
		token = Crypto.new().generate_random_bytes(32).hex_encode()
	reservations[token] = {"player": player_id, "peer": id, "expires": 0}
	peer_tokens[id] = token
	slots[id] = player_id
	pending.erase(id)
	_update_phase()
	_send_snapshot(id)

func _allow_packet(sender: int, byte_count: int) -> bool:
	_count("packets")
	_count("bytes", byte_count)
	var now := Time.get_ticks_msec()
	var budget: Dictionary = packet_budgets.get(sender, {"at": now, "packets": 0, "bytes": 0})
	if now - int(budget.at) >= 1000:
		budget = {"at": now, "packets": 0, "bytes": 0}
	budget.packets += 1
	budget.bytes += byte_count
	packet_budgets[sender] = budget
	var allowed: bool = byte_count <= 8192 and budget.packets <= MAX_PACKETS_PER_SECOND and budget.bytes <= MAX_BYTES_PER_SECOND
	if not allowed:
		_count("rejections")
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
	for index in range(mini(peer.get_available_packet_count(), 256)):
		var sender := peer.get_packet_peer()
		var bytes := peer.get_packet()
		if not _allow_packet(sender, bytes.size()):
			continue
		_handle(sender, Protocol.unpack(bytes))
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
		"ping":
			var now := Time.get_ticks_msec()
			if Protocol.integer(data.get("nonce"), 0, 2147483647) and now - int(ping_times.get(sender, -2000)) >= 500:
				ping_times[sender] = now
				_send(sender, {"type": "pong", "nonce": data.nonce})
		"surrender":
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
			if slots.size() < 2 or playback_remaining > 0:
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
	_count("snapshots")
	transfer_serial += 1
	var size: Vector3i = runner.world.size
	var edge: int = runner.world.chunk_size
	var count := ceili(float(size.x) / edge) * ceili(float(size.y) / edge) * ceili(float(size.z) / edge)
	_send(id, {"type": "snapshot_begin", "transfer_id": transfer_serial, "configuration": Protocol.encode_configuration(runner), "player_id": slots[id], "resume_token": peer_tokens[id], "size": [size.x, size.y, size.z], "chunk_size": edge, "chunk_count": count, "generation": runner.state.generation, "revision": runner.state.revision, "terrain_revision": terrain_revision, "phase": _phase()})
	for z in range(ceili(float(size.z) / edge)):
		for y in range(ceili(float(size.y) / edge)):
			for x in range(ceili(float(size.x) / edge)):
				_send(id, {"type": "chunk", "transfer_id": transfer_serial, "chunk": Protocol.chunk_snapshot(runner.world, Vector3i(x, y, z))})
	_send(id, {"type": "snapshot_end", "transfer_id": transfer_serial, "state": runner.state_snapshot(), "checksum": Protocol.terrain_checksum(runner.world), "terrain_revision": terrain_revision, "phase": _phase()})

func _broadcast(data: Dictionary) -> void:
	for id in slots:
		_send(id, data)

func _send(id: int, data: Dictionary) -> void:
	if peer == null or peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	# A second disconnect may already have reset its ENet channels while the
	# first peer's disconnect callback is broadcasting the waiting phase.
	var target: ENetPacketPeer = transport_peers.get(id)
	if target == null or not target.is_active() or target.get_state() != ENetPacketPeer.STATE_CONNECTED or target.get_channels() <= 0:
		return
	data.version = Protocol.VERSION
	peer.set_target_peer(id)
	peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	peer.put_packet(Protocol.packet(data))

func close() -> void:
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
	if slots.size() < 2:
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
	shutting_down = true
	shutdown_remaining = 0.25
	_broadcast({"type": "server_shutdown"})
	peer.host.flush()
