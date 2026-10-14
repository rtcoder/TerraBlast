extends SceneTree

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func mouse(scene: Node, button: int, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	scene._input(event)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene: Node = load("res://scenes/debug/VoxelDebug.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_physics_process(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	mouse(scene, MOUSE_BUTTON_LEFT, true)
	check(not scene.is_charging_shot, "Capturing cursor must not charge a shot")
	mouse(scene, MOUSE_BUTTON_LEFT, false)
	check(not scene.projectile_in_flight, "Capturing cursor must not fire")
	scene.projectile_in_flight = false
	mouse(scene, MOUSE_BUTTON_LEFT, true)
	check(not scene.is_charging_shot, "Camera mode must not charge")
	mouse(scene, MOUSE_BUTTON_RIGHT, true)
	mouse(scene, MOUSE_BUTTON_LEFT, true)
	check(scene.is_charging_shot, "RMB aim must allow charging")
	mouse(scene, MOUSE_BUTTON_RIGHT, false)
	mouse(scene, MOUSE_BUTTON_LEFT, false)
	check(not scene.projectile_in_flight, "Releasing aim must cancel charge")
	mouse(scene, MOUSE_BUTTON_RIGHT, true)
	mouse(scene, MOUSE_BUTTON_LEFT, true)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	scene._input(escape)
	mouse(scene, MOUSE_BUTTON_LEFT, false)
	check(not scene.projectile_in_flight, "Escape must cancel charge")
	check(scene.has_method("_get_trajectory_points"), "Trajectory preview must exist")
	if scene.has_method("_get_trajectory_points"):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		mouse(scene, MOUSE_BUTTON_RIGHT, true)
		scene._update_trajectory_preview()
		check(scene.trajectory_preview.visible and scene.trajectory_preview.mesh.get_surface_count() == 1, "Aiming must render the preview")
		var points: PackedVector3Array = scene._get_trajectory_points()
		scene.shot_charge = scene.max_charge_time
		var strong_points: PackedVector3Array = scene._get_trajectory_points()
		check(strong_points[0].distance_to(strong_points[1]) > points[0].distance_to(points[1]), "Charge must increase preview speed")
		scene.shot_charge = 0.0
		check(points.size() > 2, "Preview must contain an arc")
		scene._fire_at_screen_center(scene._get_current_shot_power())
		check(not scene.trajectory_preview.visible, "Firing must hide preview")
		var projectile: Node = scene.get_child(scene.get_child_count() - 1)
		projectile.set_physics_process(false)
		var dt: float = scene.rules.projectile_step
		for index in range(1, mini(points.size() - 1, 8)):
			projectile._physics_process(dt)
			check(projectile.global_position.distance_to(points[index]) < 0.001, "Preview must match projectile playback")
		var player: Variant = scene.turn_controller.get_active_player()
		var before: Vector3 = player.position
		scene._try_jump_active_player()
		scene._update_active_player_movement(0.2)
		check(player.position == before, "Flight must block player movement")
		mouse(scene, MOUSE_BUTTON_LEFT, true)
		check(not scene.is_charging_shot, "Flight must block another charge")
		projectile.queue_free()
	print("Artillery flow: %d failures" % failures)
	quit(1 if failures else 0)
