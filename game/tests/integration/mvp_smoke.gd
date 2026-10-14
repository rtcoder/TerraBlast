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
	check(scene.has_node("MatchEffects"), "Client effects adapter exists")
	if scene.has_node("MatchEffects"):
		var health: PackedInt32Array = scene.runner.world.health_values.duplicate()
		var effects = scene.get_node("MatchEffects")
		effects.play_events([{"type": "ShotResolved", "hit": true, "position": [14, 4, 36], "radius": 5}])
		check(effects.get_child_count() > 0, "Explosion event creates visual/audio effect")
		check(health == scene.runner.world.health_values, "Effects never mutate simulation")
		var aim := InputEventMouseButton.new()
		aim.button_index = MOUSE_BUTTON_RIGHT
		aim.pressed = true
		scene._input(aim)
		await create_timer(0.15).timeout
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/tmp/terrablast-mvp.png")
		await create_timer(0.8).timeout
		check(effects.get_child_count() == 0, "Transient effects are cleaned up")
		scene.backend_menu.toggle(true)
		check(scene.menu_open and not scene._can_control(), "Multiplayer menu blocks gameplay")
	print("Desktop MVP smoke: %d failures" % failures)
	quit(1 if failures else 0)
