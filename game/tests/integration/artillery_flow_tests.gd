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
		var dt := 1.0 / float(Engine.physics_ticks_per_second)
		for index in range(1, mini(points.size() - 1, 8)):
			projectile._physics_process(dt)
			check(projectile.global_position.distance_to(points[index]) < 0.001, "Preview must match projectile steps")
		var player: Variant = scene.turn_controller.get_active_player()
		var before: Vector3 = player.position
		scene._try_jump_active_player()
		scene._update_active_player_movement(0.2)
		check(player.position == before, "Flight must block player movement")
		mouse(scene, MOUSE_BUTTON_LEFT, true)
		check(not scene.is_charging_shot, "Flight must block another charge")
		projectile.queue_free()
	var world: Node = scene.voxel_world
	var inactive: Variant = scene.players[2]
	var x := floori(inactive.position.x)
	var z := floori(inactive.position.z)
	for y in range(world.world_size.y):
		world.world.set_voxel(Vector3i(x, y, z), 0, 0)
	world.world.set_voxel(Vector3i(x, 0, z), 2, 180)
	scene._resolve_explosion(Vector3i(-100, 0, -100), false)
	check(is_equal_approx(inactive.position.y, 1.0), "Inactive player must settle after terrain destruction")
	check(scene.player_velocities[inactive.player_id] == Vector3.ZERO, "Settling must clear velocity")
	# A roof above the pawn must not become its landing surface.
	world.world.set_voxel(Vector3i(x, 10, z), 2, 180)
	inactive.position.y = 4.0
	scene._resolve_explosion(Vector3i(-100, 0, -100), false)
	check(is_equal_approx(inactive.position.y, 1.0), "Settling must not teleport onto roofs")
	world.world.set_voxel(Vector3i(x, 0, z), 0, 0)
	scene._resolve_explosion(Vector3i(-100, 0, -100), false)
	check(not inactive.is_alive, "Player without any support must be eliminated")
	var projectile_type = load("res://scripts/client/debug/debug_projectile.gd")
	var arc: PackedVector3Array = projectile_type.predict_trajectory(Vector3(40, 50, 40), Vector3(10, 0, 0), world, 0.1)
	check(arc[1].is_equal_approx(Vector3(41, 49.82, 40)), "First prediction step must include gravity")
	check(arc[2].is_equal_approx(Vector3(42, 49.46, 40)), "Prediction must accumulate gravity")
	print("Artillery flow: %d failures" % failures)
	quit(1 if failures else 0)
