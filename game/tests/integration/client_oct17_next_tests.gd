extends SceneTree
var failures := 0
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280, 720)
	var scene = load("res://scenes/debug/VoxelDebug.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_physics_process(false)
	if not scene.has_method("_toggle_lobby"):
		check(false, "Lobby UI exists")
		scene.queue_free()
		quit(1)
		return
	var panel = scene.lobby_panel
	var sample := {"capacity":4,"require_ready":true,"started":false,"generation":0,"roster":[
		{"id":"blue_1","name":"Alice","team":1,"connected":true,"ready":false,"rematch":false},
		{"id":"red_1","name":"Bob","team":2,"connected":true,"ready":true,"rematch":false},
		{"id":"blue_2","name":"Blue 2","team":1,"connected":false,"ready":false,"rematch":false},
		{"id":"red_2","name":"Red 2","team":2,"connected":false,"ready":false,"rematch":false}]}
	panel.present(sample, "blue_1", "waiting", true)
	check(panel.roster_label.text.contains("Alice [you]") and panel.roster_label.text.contains("Vacant"), "Roster identities and vacant slots")
	check(not panel.ready_button.disabled and not panel.name_apply.disabled, "Pre-game ready and rename")
	check(panel.summary.text.contains("2 / 4"), "Capacity visible")
	var intents := []
	panel.ready_requested.connect(func(value: bool): intents.append(value))
	panel.ready_button.pressed.emit()
	check(intents == [true] and panel.ready_button.text == "Ready", "Ready is intent, not optimistic authority")
	sample.roster[0].ready = true
	panel.present(sample, "blue_1", "waiting", true)
	check(panel.ready_button.text == "Not ready", "Server ready state reflected")
	sample.started = true
	panel.present(sample, "blue_1", "playing", true)
	check(panel.ready_button.disabled and panel.name_apply.disabled and panel.rematch_button.disabled, "Playing controls gated")
	panel.present(sample, "blue_1", "ended", true)
	check(not panel.rematch_button.disabled, "Rematch allowed after end")
	check(scene.backend_menu.port.value == 19170, "Default port")
	scene.backend_menu.port.value = 19179
	check(scene.backend_menu.selected_port() == 19179, "Custom port")
	check(scene.start_local_match("canyon_bridge", 4, "classic"), "Third map client start")
	check(scene.runner.world.size == Vector3i(80,24,64), "Third map dimensions")
	var maps = scene.match_panels.map_select
	var index := -1
	for i in maps.item_count:
		if maps.get_item_metadata(i) == "canyon_bridge": index = i
	check(index >= 0 and maps.get_item_text(index) == "Canyon Bridge", "Display name separate from map ID")
	maps.select(index)
	maps.item_selected.emit(index)
	check(scene.match_panels.map_description.text.contains("10"), "Capacity metadata shown")
	# Source identity guards stop callbacks from a closed transport affecting local authority.
	scene._begin_network_connection("127.0.0.1", 19179)
	var old = scene.network
	check(old.last_port == 19179 and scene.remote_mode, "Selected port used")
	old.resume_token = "test-token"
	scene._disconnect_to_local()
	var local_runner = scene.runner
	old.synchronized.emit()
	old.status_changed.emit("stale message")
	check(not scene.remote_mode and scene.network == null and scene.runner == local_runner and old.resume_token.is_empty(), "Disconnect clears authority and token; stale signals ignored")
	check(scene.session.options.mode == "hotseat" and not scene.menu_open, "Fresh hotseat after disconnect")
	await real_lobby_flow(scene)
	# Existing replay isolation includes the new lobby key and direct entry point.
	scene.session.playback = RefCounted.new()
	scene._begin_network_connection("127.0.0.1",19179)
	scene._toggle_lobby()
	check(not scene.remote_mode and not panel.visible, "Replay blocks network and lobby")
	scene.session.playback = null
	if DisplayServer.get_name() != "headless":
		scene.start_local_match("canyon_bridge",10,"classic")
		scene.preferences.hud_scale = 1.25
		scene._apply_client_preferences()
		scene._close_overlays()
		panel.present(sample,"blue_1","ended",true)
		panel.show()
		scene._refresh_menu_state()
		scene._update_hud()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/terrablast-oct17-lobby.png")
		scene._close_overlays()
		scene._toggle_setup()
		scene._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		check(scene.match_panels.setup_panel.visible and not scene.match_panels.pause_panel.visible, "Focus loss preserves existing menu")
		scene._update_hud()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/terrablast-oct17-arena.png")
	scene.queue_free()
	await process_frame
	print("Client Oct17 tests: %d failures" % failures)
	quit(1 if failures else 0)

func wait_until(predicate: Callable) -> bool:
	for i in 400:
		if predicate.call(): return true
		await create_timer(0.02).timeout
	return false

func real_lobby_flow(scene: Node) -> void:
	var profile_path := ("/private/tmp" if OS.get_name()=="macOS" else "/tmp").path_join("tb-lobby-profile-%d.json") % OS.get_process_id()
	scene.backend_menu.setup_profiles(load("res://scripts/client/backend/connection_profiles.gd").new(profile_path))
	var server = load("res://scripts/networking/transport/match_server.gd").new()
	root.add_child(server)
	var port := 28000 + OS.get_process_id() % 10000
	if server.start(port,"res://maps/canyon_bridge.toml","classic",4,true) != OK:
		check(false,"Real UI lobby binds")
		server.queue_free()
		return
	scene._begin_network_connection("127.0.0.1",port)
	check(await wait_until(func(): return scene.network.ready_for_match),"Scene receives lobby snapshot")
	var others := []
	for i in 3:
		var client = load("res://scripts/networking/transport/match_client.gd").new()
		root.add_child(client)
		client.connect_to_server("127.0.0.1",port)
		others.append(client)
	var connected := await wait_until(func(): return others.all(func(c):return c.ready_for_match) and server.slots.size()==4)
	check(connected,"Four-client scene lobby connects")
	if connected:
		check(scene.lobby_panel.visible and scene.menu_open and not scene.local_paused,"Online pregame panel without local authority pause")
		scene.lobby_panel.ready_button.pressed.emit()
		for c in others: c.set_ready(true)
		check(await wait_until(func(): return server.started and scene.network.match_phase=="playing"),"UI ready starts match")
		check(not scene.lobby_panel.visible,"Ready start closes lobby")
		for c in others:
			if c.player_id.begins_with("red_"): c.surrender()
		check(await wait_until(func(): return scene.runner.state.status=="ended"),"Scene receives ended match")
		scene._physics_process(0.0)
		check(scene.match_panels.end_panel.visible and scene.match_panels.restart_button.text=="Vote rematch","End panel offers consensual rematch")
		scene.set_physics_process(true)
		scene.restart_match()
		check(scene.match_panels.end_panel.visible,"Voting retains end panel")
		for c in others: c.vote_rematch(true)
		check(await wait_until(func(): return scene.runner.state.generation==1 and scene.network.ready_for_match),"Rematch snapshot received")
		scene._physics_process(0.0)
		check(scene.lobby_panel.visible and not scene.match_panels.end_panel.visible and not scene.projectile_in_flight,"Rematch returns to ready panel cleanly")
		scene.set_physics_process(false)
	scene._disconnect_to_local()
	for c in others:
		c.close()
		c.queue_free()
	server.close()
	server.queue_free()
	DirAccess.remove_absolute(profile_path)
	await process_frame
