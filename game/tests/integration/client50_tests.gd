extends SceneTree
var failures := 0
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var Settings = load("res://scripts/client/settings/client_settings.gd")
	if Settings == null:
		check(false, "Settings model exists")
		quit(1)
		return
	var preferences = Settings.new()
	preferences.update({"volume": -7, "sensitivity": INF, "invert_y": "wrong", "fullscreen": true})
	check(preferences.volume == 0.0 and preferences.sensitivity == 1.0 and not preferences.invert_y, "Invalid settings bounded/rejected")
	preferences.update({"volume": 0.42, "sensitivity": 1.7, "invert_y": true, "muted": true})
	check(preferences.save_to("user://test_preferences.cfg") == OK, "Save preferences")
	var restored = Settings.new()
	restored.load_from("user://test_preferences.cfg")
	check(is_equal_approx(restored.volume, 0.42) and restored.invert_y and restored.muted and is_equal_approx(restored.sensitivity, 1.7), "Preference roundtrip")
	var corrupted := FileAccess.open("user://test_preferences.cfg", FileAccess.WRITE)
	corrupted.store_string("invalid [ configuration")
	corrupted.close()
	var fallback = Settings.new()
	fallback.load_from("user://test_preferences.cfg")
	check(fallback.volume == 0.8 and fallback.sensitivity == 1.0, "Corrupt file uses defaults")
	DirAccess.remove_absolute("user://test_preferences.cfg")
	var scene = load("res://scenes/debug/VoxelDebug.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_physics_process(false)
	scene.preferences.sensitivity = 2.0
	scene.preferences.invert_y = false
	scene.mouse_look_enabled = true
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(10, 10)
	var yaw: float = scene.orbit_yaw
	var pitch: float = scene.camera_pitch
	scene._input(motion)
	check(is_equal_approx(scene.orbit_yaw, yaw - 0.12) and is_equal_approx(scene.camera_pitch, pitch - 0.08), "Sensitivity affects both axes")
	scene.preferences.invert_y = true
	scene._input(motion)
	check(is_equal_approx(scene.camera_pitch, pitch), "Invert Y reverses vertical look")
	scene.preferences.volume = 0.25
	scene.preferences.muted = true
	scene.preferences.apply()
	check(AudioServer.is_bus_mute(0) and is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(0)), 0.25), "Audio preference changes master bus")
	scene._select_weapon(2)
	var first: String = scene.turn_controller.get_active_player().player_id
	scene.runner.advance([])
	scene._sync_selected_weapon()
	check(scene.selected_weapon_id == 1, "New player defaults bazooka")
	scene._select_weapon(3)
	scene.turn_controller.active_player_index = 0
	scene._sync_selected_weapon()
	check(scene.selected_weapon_id == 2 and scene.weapon_by_player[first] == 2, "Weapon selection retained per player")
	scene.is_aiming = true
	scene._start_charging_shot()
	scene._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not scene.is_charging_shot and not scene.is_aiming, "Focus loss cancels charge")
	var turn_before_release: int = scene.turn_controller.turn_id
	scene._release_charged_shot()
	check(scene.turn_controller.turn_id == turn_before_release and not scene.projectile_in_flight, "Release after focus loss cannot fire")
	scene._toggle_settings()
	check(scene.menu_open and not scene._can_control(), "Settings suppress gameplay")
	scene._toggle_settings()
	scene._update_scoreboard()
	check(scene.scoreboard.text.contains("Blue 1") and scene.scoreboard.text.contains("HP") and scene.scoreboard.text.contains("ACTIVE"), "Scoreboard individual HP")
	if DisplayServer.get_name() != "headless":
		scene.scoreboard.show()
		scene._toggle_settings()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/terrablast-client50.png")
		scene._toggle_settings()
	scene.restart_match()
	var before: int = scene.turn_controller.turn_id
	scene._fire_at_screen_center(0.25)
	check(scene.projectile_in_flight and scene.turn_controller.turn_id > before, "Real scene shot advances authoritative turn")
	check(not scene.pending_result.get("deltas", []).is_empty(), "Real scene shot changes terrain")
	scene.restart_match()
	scene.queue_free()
	await process_frame
	print("Client50 tests: %d failures" % failures)
	quit(1 if failures else 0)
