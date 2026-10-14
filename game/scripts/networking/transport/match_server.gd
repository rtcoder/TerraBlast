class_name MatchServer
extends Node
const Factory := preload("res://scripts/core/rules/match_factory.gd")
const Protocol := preload("res://scripts/networking/messages/match_protocol.gd")
var peer: ENetMultiplayerPeer
var runner: RefCounted
var slots := {}
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

func start(port: int = 19170, map_path: String = "res://maps/twin_forts.toml") -> Error:
	close()
	runner = Factory.create_match(2, map_path)
	if runner == null:
		return ERR_INVALID_DATA
	peer = ENetMultiplayerPeer.new()
	peer.peer_connected.connect(_connected)
	peer.peer_disconnected.connect(_disconnected)
	return peer.create_server(port, 16)

func _connected(id: int) -> void:
	pending[id] = Time.get_ticks_msec()

func _disconnected(id: int) -> void:
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
	_send_snapshot(id)

func _allow_packet(sender: int, byte_count: int) -> bool:
	var now := Time.get_ticks_msec()
	var budget: Dictionary = packet_budgets.get(sender, {"at": now, "packets": 0, "bytes": 0})
	if now - int(budget.at) >= 1000:
		budget = {"at": now, "packets": 0, "bytes": 0}
	budget.packets += 1
	budget.bytes += byte_count
	packet_budgets[sender] = budget
	return byte_count <= 8192 and budget.packets <= MAX_PACKETS_PER_SECOND and budget.bytes <= MAX_BYTES_PER_SECOND

func _process(delta: float) -> void:
	if peer == null or peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	peer.poll()
	_expire_reservations()
	for index in range(mini(peer.get_available_packet_count(), 256)):
		var sender := peer.get_packet_peer()
		var bytes := peer.get_packet()
		if not _allow_packet(sender, bytes.size()):
			continue
		_handle(sender, Protocol.unpack(bytes))
	playback_remaining = maxf(0.0, playback_remaining - delta)
	if slots.size() == 2 and playback_remaining == 0:
		var active = runner.state.get_active_player()
		if active != null and runner.state.status == "playing":
			var input: Dictionary = motion.get(active.player_id, {})
			var vector: Vector2 = input.get("vector", Vector2.ZERO) if Time.get_ticks_msec() - int(input.get("at", 0)) < 250 else Vector2.ZERO
			velocities[active.player_id] = Motion.move(runner.world, active, velocities.get(active.player_id, Vector3.ZERO), vector, float(input.get("yaw", 0.0)), input.get("jump", false), minf(delta, 0.05), runner.rules)
			input["jump"] = false
		var events: Array = runner.tick(delta)
		state_timer += delta
		if not events.is_empty() or state_timer >= 0.1:
			state_timer = 0.0
			_broadcast({"type": "state", "state": runner.state_snapshot(), "terrain_revision": terrain_revision})

func _handle(sender: int, data: Dictionary) -> void:
	if data.get("type") == "hello":
		_accept_hello(sender, data)
		return
	if not slots.has(sender):
		return
	match data.get("type", ""):
		"snapshot":
			var now := Time.get_ticks_msec()
			if now - int(snapshot_times.get(sender, -2000)) > 1000:
				snapshot_times[sender] = now
				_send_snapshot(sender)
		"move":
			var active = runner.state.get_active_player()
			if active == null or slots[sender] != active.player_id or data.get("turn_id") != runner.state.turn_id or data.get("generation") != runner.state.generation or playback_remaining > 0:
				return
			var axis = data.get("axis")
			if not axis is Array or axis.size() != 2 or not Protocol.number(axis[0]) or not Protocol.number(axis[1]) or absf(axis[0]) > 1 or absf(axis[1]) > 1 or not Protocol.number(data.get("yaw")) or absf(data.yaw) > 1e6 or not data.get("jump") is bool:
				return
			motion[active.player_id] = {"vector": Vector2(axis[0], axis[1]), "yaw": data.yaw, "jump": data.jump or motion.get(active.player_id, {}).get("jump", false), "at": Time.get_ticks_msec()}
		"command":
			var command = Protocol.decode_command(data.get("command"))
			if command == null or command.player_id != slots[sender]:
				_send(sender, {"type": "rejected", "reason": "invalid_identity_or_command"})
				return
			if slots.size() < 2 or playback_remaining > 0:
				_send(sender, {"type": "rejected", "reason": "waiting_for_players_or_projectile"})
				return
			var result: Dictionary = runner.submit(command)
			if result.ok:
				motion.clear()
				velocities.clear()
				playback_remaining = maxf(0.05, (result.path.size() - 1) * runner.rules.projectile_step)
				terrain_revision += 1
				_broadcast({"type": "result", "result": Protocol.encode_result(result), "base_terrain_revision": terrain_revision - 1, "terrain_revision": terrain_revision})
			else:
				_send(sender, {"type": "rejected", "reason": result.reason})
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

func _send_snapshot(id: int) -> void:
	var size: Vector3i = runner.world.size
	var edge: int = runner.world.chunk_size
	var count := ceili(float(size.x) / edge) * ceili(float(size.y) / edge) * ceili(float(size.z) / edge)
	_send(id, {"type": "snapshot_begin", "player_id": slots[id], "resume_token": peer_tokens[id], "size": [size.x, size.y, size.z], "chunk_size": edge, "chunk_count": count, "generation": runner.state.generation, "revision": runner.state.revision, "terrain_revision": terrain_revision})
	for z in range(ceili(float(size.z) / edge)):
		for y in range(ceili(float(size.y) / edge)):
			for x in range(ceili(float(size.x) / edge)):
				_send(id, {"type": "chunk", "chunk": Protocol.chunk_snapshot(runner.world, Vector3i(x, y, z))})
	_send(id, {"type": "snapshot_end", "state": runner.state_snapshot(), "checksum": Protocol.terrain_checksum(runner.world), "terrain_revision": terrain_revision})

func _broadcast(data: Dictionary) -> void:
	for id in slots:
		_send(id, data)

func _send(id: int, data: Dictionary) -> void:
	data.version = Protocol.VERSION
	peer.set_target_peer(id)
	peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	peer.put_packet(Protocol.packet(data))

func close() -> void:
	if peer != null:
		peer.close()
		peer = null
	slots.clear()
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
