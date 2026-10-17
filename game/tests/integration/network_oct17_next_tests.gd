extends SceneTree
const S = preload("res://scripts/networking/transport/match_server.gd")
const C = preload("res://scripts/networking/transport/match_client.gd")
const P = preload("res://scripts/networking/messages/match_protocol.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
func _initialize() -> void:
	call_deferred("run")
func settle(seconds: float = 0.15) -> void:
	await create_timer(seconds).timeout
func synced(clients: Array) -> void:
	for i in range(500):
		if clients.all(func(c): return c.ready_for_match): return
		await settle(0.02)
func run() -> void:
	var port_probe := PacketPeerUDP.new()
	check(port_probe.bind(0, "127.0.0.1") == OK, "Allocate independent UDP port")
	var port := port_probe.get_local_port()
	port_probe.close()
	var server = S.new()
	root.add_child(server)
	check(server.start(port, "res://maps/twin_forts.toml", "classic", 11, true) != OK and server.peer == null, "Invalid capacity cannot bind")
	if server.start(port, "res://maps/twin_forts.toml", "classic", 4, true) != OK:
		check(false, "Four-slot lobby binds")
		server.queue_free()
		quit(1)
		return
	var clients := []
	for i in range(4):
		var c = C.new()
		root.add_child(c)
		clients.append(c)
		c.connect_to_server("127.0.0.1", port)
		await synced([c])
	await settle()
	check(server.slots.size() == 4 and server.slots.values().size() == 4, "All four unique slots admitted")
	check(clients.all(func(c): return c.lobby_state.roster.size() == 4 and c.match_phase == "waiting"), "All clients receive full waiting roster")
	var command = load("res://scripts/core/turns/player_action_command.gd").new()
	command.player_id = clients[0].player_id
	command.weapon_id = 1
	command.aim_direction = Vector3.DOWN
	command.shot_power = 1.0
	clients[0]._send({"type":"command", "command":P.encode_command(command)})
	clients[0]._send({"type":"surrender"})
	await settle()
	check(server.runner.state.revision == 0 and server.runner.history.is_empty(), "Prestart shot and surrender cannot alter match")
	var clock_before: float = server.runner.state.time_remaining
	await settle()
	check(clock_before == server.runner.state.time_remaining, "Full lobby clock frozen until ready")
	var extra = C.new()
	root.add_child(extra)
	extra.connect_to_server("127.0.0.1",port)
	await settle(0.3)
	check(extra.last_error == "match_slots_reserved_or_full", "Capacity plus one rejected")
	extra.free()
	var a = clients[0]
	var id: String = a.player_id
	var lobby: Dictionary = a.lobby_state.duplicate(true)
	var malformed: Dictionary = lobby.duplicate(true)
	for key in ["capacity", "generation", "require_ready", "started", "roster"]:
		var invalid := lobby.duplicate(true)
		invalid[key] = null
		check(not P.valid_lobby(invalid), "Missing typed lobby field rejects")
	malformed.roster[1].id = malformed.roster[0].id
	check(not P.valid_lobby(malformed), "Duplicate roster IDs rejected")
	a._handle({"type":"lobby_state","lobby":malformed})
	check(a.lobby_state == lobby, "Malformed roster never mutates client")
	malformed = lobby.duplicate(true)
	malformed.roster[0].team = 3
	check(not P.valid_lobby(malformed), "Unsupported lobby team rejected")
	a._handle({"type":"lobby_state", "lobby":malformed})
	check(a.lobby_state == lobby, "Unsupported team packet cannot mutate lobby")
	for value in ["", "  ", "a".repeat(25), "abc\n", "abc\u007f", 17]:
		check(not P.valid_display_name(value), "Invalid display name rejected")
	a._send({"type":"ready","ready":true,"generation":0,"player_id":clients[1].player_id})
	a._send({"type":"ready","ready":1,"generation":0})
	a._send({"type":"display_name","name":"spoof","generation":0,"player_id":clients[1].player_id})
	await settle()
	check(server.ready_slots.is_empty(), "Spoofed and non-bool readiness rejected")
	a.set_ready(true)
	a.set_display_name("  Pilot Żółw  ")
	await settle()
	check(not server.ready_slots.has(id) and a.runner.state.players[0].display_name == "Pilot Żółw", "Name trims, syncs state, and clears ready")
	check(clients.all(func(c): return c.lobby_state.roster[0].name == "Pilot Żółw"), "Name visible across roster")
	for i in range(20): a.set_display_name("Flood%d" % i)
	await settle()
	check(server.diagnostics.rejections > 10 and server.lobby_budgets.values().any(func(b): return b.count > 8), "Lobby flood bounded")
	await settle(1.1)
	a.set_display_name("Pilot Żółw")
	a.set_ready(true)
	a.set_ready(false)
	await settle()
	check(not server.ready_slots.get(id, false), "Ready cancellation works")
	for c in clients.slice(0,3): c.set_ready(true)
	await settle()
	check(server.match_phase == "waiting" and server.terrain_revision == 0, "Three ready cannot start four-player match")
	clients[3].set_ready(true)
	await settle()
	check(server.started and clients.all(func(c): return c.match_phase == "playing"), "Full ready roster starts atomically")
	a.set_display_name("Late name")
	await settle()
	check(server.runner.state.players[0].display_name == "Pilot Żółw", "Playing name change rejected")
	var reconnect = clients[3]
	var reconnect_id: String = reconnect.player_id
	reconnect.close()
	await settle()
	clock_before = server.runner.state.time_remaining
	await settle()
	check(server.match_phase == "waiting" and clock_before == server.runner.state.time_remaining, "Missing fourth slot freezes clock")
	reconnect.retry_connection()
	await synced([reconnect])
	await settle()
	check(reconnect.player_id == reconnect_id and server.match_phase == "playing", "Fourth slot token restores identity and resumes without ready")
	for c in clients:
		if c.runner.state.players.filter(func(p): return p.player_id == c.player_id)[0].team_id == 1:
			c.surrender()
			await settle()
	check(server.runner.state.status == "ended", "Team surrender ends four-player match")
	a.restart_match()
	await settle()
	check(server.runner.state.generation == 0, "Legacy restart cannot bypass quorum")
	a.vote_rematch(true)
	a.vote_rematch(false)
	await settle()
	check(not server.rematch_votes.get(id, false), "Rematch vote cancellation works")
	for c in clients.slice(0,3): c.vote_rematch(true)
	await settle()
	check(server.runner.state.generation == 0, "Partial quorum never resets")
	reconnect.close()
	await settle()
	check(server.rematch_votes.is_empty() and server.runner.state.generation == 0, "Disconnect invalidates votes without lowering quorum")
	reconnect.retry_connection()
	await synced([reconnect])
	await settle(1.1)
	var old_state: Dictionary = server.runner.state_snapshot()
	for c in clients: c.vote_rematch(true)
	await settle(0.5)
	await synced(clients)
	check(server.runner.state.generation == 1 and not server.started and server.ready_slots.is_empty() and server.rematch_votes.is_empty(), "Quorum resets once to unready new generation")
	check(clients.all(func(c): return c.runner.state.generation == 1 and c.lobby_state.generation == 1 and c.match_phase == "waiting"), "New generation snapshot reaches all four")
	check(server.runner.state.players[0].display_name == "Pilot Żółw" and a.last_result.is_empty(), "Rematch preserves names and clears result")
	a._handle({"type":"state","state":old_state,"terrain_revision":0})
	check(a.ready_for_match and a.runner.state.generation == 1, "Old state cannot rewind or trigger recovery after rematch")
	a._send({"type":"ready","ready":true,"generation":0})
	a._handle({"type":"lobby_state","lobby":lobby})
	await settle()
	check(server.ready_slots.is_empty() and a.lobby_state.generation == 1, "Old generation intents and lobby ignored")
	for c in clients: c.close()
	server.close()
	for c in clients: c.free()
	server.free()
	print("Network Oct17: %d failures" % failures)
	quit(1 if failures else 0)
