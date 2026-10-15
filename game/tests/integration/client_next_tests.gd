extends SceneTree
var failures := 0
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var scene = load("res://scenes/debug/VoxelDebug.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_physics_process(false)
	if not scene.has_method("_toggle_pause"):
		check(false, "Local pause available")
		quit(1)
		return
	scene.is_aiming = true
	scene._start_charging_shot()
	scene._toggle_pause()
	var before: float = scene.runner.state.time_remaining
	scene._physics_process(1.0)
	check(scene.local_paused and scene.runner.state.time_remaining == before and not scene.is_charging_shot, "Pause stops timer and cancels charge")
	scene._toggle_pause()
	scene._release_charged_shot()
	check(not scene.projectile_in_flight, "Resume cannot fire old charge")
	scene._fire_at_screen_center(1.0)
	scene._toggle_pause()
	var flight_time: float = scene.active_projectile.elapsed
	await create_timer(0.1).timeout
	check(scene.projectile_in_flight and scene.active_projectile.elapsed == flight_time, "Pause freezes projectile playback")
	scene._toggle_pause()
	check(scene.start_local_match("two_islands", 4, "quick"), "Setup starts arena and preset")
	check(scene.players.size() == 4 and scene.rules.turn_time == 20, "Setup uses selected players/rules")
	check(not scene.start_local_match("invalid", 4, "classic"), "Invalid setup rejected")
	scene.preferences.update({"hud_scale": 1.25, "show_trajectory": false, "high_contrast": true})
	scene._apply_client_preferences()
	check(scene.hud_label.get_theme_font_size("font_size") == 25, "HUD scale applied")
	scene.is_aiming = true
	scene._update_trajectory_preview()
	check(not scene.trajectory_preview.visible and scene.aim_indicator.visible, "Preview preference preserves aim indicator")
	check(scene.get_node("Hud/Crosshair/Horizontal").color != Color(1,1,1,0.9), "Contrast crosshair applied")
	scene.settings_panel.reset_preferences(false)
	check(scene.preferences.hud_scale == 1.0 and scene.preferences.show_trajectory, "Reset defaults and widgets")
	scene._toggle_help()
	check(scene.menu_open and not scene._can_control(), "Help blocks gameplay")
	scene._toggle_help()
	var player = scene.turn_controller.get_active_player()
	check(scene.player_nodes[player.player_id].has_node("HealthLabel"), "World HP label exists")
	player.health = 71
	scene._update_player_nodes()
	check(scene.player_nodes[player.player_id].get_node("HealthLabel").text.contains("71"), "HP label updates")
	scene._physics_process(0.0)
	var banner_count: int = scene.turn_banner_count
	scene._physics_process(0.0)
	check(scene.turn_banner_count == banner_count, "Repeated state does not retrigger banner")
	scene._fire_at_screen_center(0.25)
	var destroyed := 0
	for change in scene.pending_result.deltas:
		if change.material_id == 0:
			destroyed += 1
	check(scene.runner.history.back().get("terrain_destroyed", -1) == destroyed, "History distinguishes destroyed voxels from damage deltas")
	scene._finish_playback()
	scene._update_match_panels(0.0)
	check(not scene.last_shot_label.text.is_empty(), "Authoritative shot summary displayed")
	scene._update_scoreboard()
	check(scene.scoreboard.text.contains("Shots") and scene.scoreboard.text.contains("Damage"), "Scoreboard shows stats")
	scene.start_local_match("twin_forts", 2, "classic")
	scene._surrender()
	scene._update_match_panels(0.0)
	check(scene.runner.state.status == "ended" and scene.match_panels.end_panel.visible, "Surrender ends match and opens results")
	scene._toggle_setup()
	scene._physics_process(0.0)
	check(scene.match_panels.setup_panel.visible and not scene.match_panels.end_panel.visible, "End panel does not steal setup overlay")
	scene._toggle_help()
	scene._physics_process(0.0)
	check(scene.match_panels.help_panel.visible, "Help remains usable after match ends")
	scene.restart_match()
	check(scene.runner.state.status == "playing" and not scene.match_panels.end_panel.visible, "Restart closes result and resets stats")
	if DisplayServer.get_name() != "headless":
		scene._toggle_setup()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/terrablast-next-setup.png")
		scene._toggle_settings()
		scene.preferences.update({"hud_scale": 1.25, "high_contrast": true})
		scene._apply_client_preferences()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/terrablast-next-settings.png")
	scene.queue_free()
	await process_frame
	print("Client next tests: %d failures" % failures)
	quit(1 if failures else 0)
