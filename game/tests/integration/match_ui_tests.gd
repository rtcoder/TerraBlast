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
	check(scene.has_method("restart_match"), "UI supports match restart")
	if scene.has_method("restart_match"):
		var key := InputEventKey.new()
		key.keycode = KEY_2
		key.pressed = true
		scene._input(key)
		check(scene.selected_weapon_id == 2, "Key 2 selects grenade")
		check(scene.hud_label.text.contains("Grenade"), "HUD shows selected weapon")
		scene._fire_at_screen_center(1.0)
		check(scene.projectile_in_flight, "Accepted command starts playback")
		scene.restart_match()
		check(not scene.projectile_in_flight and scene.turn_controller.turn_id == 0, "Reset cancels playback and turn")
		check(scene.runner.state.inventory["blue_1"][2] == 5, "Reset restores ammo")
		await create_timer(0.2).timeout
		check(scene.turn_controller.turn_id == 0, "Old playback cannot advance reset match")
	print("Match UI tests: %d failures" % failures)
	quit(1 if failures else 0)
