class_name MatchServer
extends Node
const Factory := preload("res://scripts/core/rules/match_factory.gd")
const Protocol := preload("res://scripts/networking/messages/match_protocol.gd")
var peer: ENetMultiplayerPeer
var runner: RefCounted
var slots := {}
var snapshot_times := {}
var playback_remaining := 0.0
var state_timer := 0.0
var motion := {}
var velocities := {}
const Motion := preload("res://scripts/core/rules/player_motion.gd")

func start(port: int = 19170) -> Error:
	runner = Factory.create_match(2)
	peer = ENetMultiplayerPeer.new()
	peer.peer_connected.connect(_connected)
	peer.peer_disconnected.connect(_disconnected)
	return peer.create_server(port, 2)

func _connected(id: int) -> void:
	for player in runner.state.players:
		if not slots.values().has(player.player_id):
			slots[id] = player.player_id
			_send_snapshot(id)
			return

func _disconnected(id: int) -> void:
	slots.erase(id)
	snapshot_times.erase(id)

func _process(delta: float) -> void:
	if peer == null or peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	peer.poll()
	for index in range(mini(peer.get_available_packet_count(), 32)):
		var sender := peer.get_packet_peer()
		var bytes := peer.get_packet()
		if bytes.size() > 8192 or not slots.has(sender):
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
			_broadcast({"type": "state", "state": runner.state_snapshot()})

func _handle(sender: int, data: Dictionary) -> void:
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
				_broadcast({"type": "result", "result": Protocol.encode_result(result)})
			else:
				_send(sender, {"type": "rejected", "reason": result.reason})
		"restart":
			if slots[sender] == "blue_1":
				runner.reset()
				motion.clear()
				velocities.clear()
				playback_remaining = 0.0
				for id in slots:
					_send_snapshot(id)

func _send_snapshot(id: int) -> void:
	_send(id, {"type": "snapshot_begin", "player_id": slots[id]})
	var size: Vector3i = runner.world.size
	var edge: int = runner.world.chunk_size
	for z in range(ceili(float(size.z) / edge)):
		for y in range(ceili(float(size.y) / edge)):
			for x in range(ceili(float(size.x) / edge)):
				_send(id, {"type": "chunk", "chunk": Protocol.chunk_snapshot(runner.world, Vector3i(x, y, z))})
	_send(id, {"type": "snapshot_end", "state": runner.state_snapshot()})

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

func _exit_tree() -> void:
	close()
