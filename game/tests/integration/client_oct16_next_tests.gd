extends SceneTree
const Replay = preload("res://scripts/core/replay/match_replay.gd")
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
	if not scene.has_method("_save_session"):
		check(false, "Local session saving exists")
		scene.queue_free()
		quit(1)
		return
	check(scene.start_local_match("two_islands", 2, "quick", "solo", "easy"), "Solo setup")
	check(scene.session.options.mode == "solo" and scene._can_control(), "Human controls blue")
	scene._physics_process(0.1)
	var save_path := "/tmp/terrablast-oct16-%d-session.json" % OS.get_process_id()
	var replay_path := "/tmp/terrablast-oct16-%d-replay.json" % OS.get_process_id()
	scene._try_jump_active_player()
	scene._physics_process(0.05)
	var saved_velocity: Vector3 = scene.player_velocities["blue_1"]
	check(saved_velocity.y > 0, "Save scenario is airborne")
	var saved_hash := Replay.state_hash(scene.runner)
	check(scene._save_session(save_path), "Save checkpoint")
	scene._physics_process(0.2)
	check(scene._load_session(save_path), "Load checkpoint")
	check(Replay.state_hash(scene.runner) == saved_hash and scene.session.options.mode == "solo", "Load preserves hash/options")
	check(scene.player_velocities["blue_1"] == saved_velocity, "Load preserves airborne velocity")
	check(not scene._load_session("/tmp/terrablast-no-such-save.json") and Replay.state_hash(scene.runner) == saved_hash, "Invalid load preserves match")
	scene._close_overlays()
	scene.session.recorder.tick(scene.runner, scene.rules.turn_time)
	check(scene.session.is_bot_turn() and not scene._can_control(), "Red bot input blocked")
	scene._toggle_pause()
	var turn: int = scene.runner.state.turn_id
	scene._physics_process(1.0)
	check(scene.runner.state.turn_id == turn and scene.session.bot == null, "Pause blocks bot")
	scene._toggle_pause()
	for i in 100:
		scene.session.update_bot()
		if scene.projectile_in_flight:
			break
	check(scene.projectile_in_flight, "Bot submitted shot")
	check(not scene._save_session(save_path), "Cannot save during flight")
	scene._finish_playback()
	check(scene._save_replay(replay_path), "Live recording exports")
	var live_hash := Replay.state_hash(scene.runner)
	check(scene._open_replay(replay_path), "Open verified replay")
	check(not scene._can_control(), "Playback cannot control")
	var key := InputEventKey.new()
	key.keycode = KEY_F2
	key.pressed = true
	scene._input(key)
	check(not scene.backend_menu.panel.visible, "Playback blocks multiplayer overlay")
	scene.backend_menu.connect_game.emit("127.0.0.1")
	check(not scene.remote_mode and scene.network == null, "Playback blocks direct connection intent")
	var playback_hash := Replay.state_hash(scene.runner)
	scene._physics_process(1.0)
	check(Replay.state_hash(scene.runner) == playback_hash, "Playback does not tick")
	while not scene.session.playback.finished:
		scene._step_replay()
	check(Replay.state_hash(scene.runner) == live_hash, "Step playback reaches recorded state")
	scene._rewind_replay()
	check(scene.session.playback.index == 0, "Replay rewind")
	scene._return_from_replay()
	check(Replay.state_hash(scene.runner) == live_hash and scene.session.playback == null, "Return preserves live game")
	scene.restart_match()
	check(scene.session.bot == null and scene.session.recorder.data.actions.is_empty(), "Restart resets recorder and bot")
	scene.remote_mode = true
	check(not scene._save_session(save_path) and not scene._open_replay(replay_path), "Online local authority operations blocked")
	scene.remote_mode = false
	if DisplayServer.get_name() != "headless":
		scene.preferences.hud_scale = 1.25
		scene._apply_client_preferences()
		scene._toggle_setup()
		await process_frame
		await process_frame
		scene._update_hud()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/terrablast-oct16-setup.png")
		scene._toggle_pause()
		await process_frame
		await process_frame
		scene._update_hud()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/terrablast-oct16-session.png")
	scene.queue_free()
	await process_frame
	print("Client Oct16 tests: %d failures" % failures)
	quit(1 if failures else 0)
