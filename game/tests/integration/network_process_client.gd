extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var scene = load("res://scenes/debug/VoxelDebug.tscn").instantiate()
	root.add_child(scene)
	var fired := false
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		if scene.network.ready_for_match:
			if scene.turn_controller.turn_id >= 2:
				if not fired:
					push_error("Client never submitted its turn")
					quit(1)
					return
				var identity: String = scene.network.player_id
				scene.queue_free()
				await process_frame
				await process_frame
				print("Network process client passed: " + identity)
				quit(0)
				return
			if scene._can_control() and not scene.projectile_in_flight and not fired:
				scene._fire_at_screen_center(0.25)
				fired = true
		await create_timer(0.03).timeout
	push_error("Remote gameplay UI timed out")
	quit(1)
