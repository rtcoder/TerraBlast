extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: PackedScene = load("res://scenes/debug/VoxelDebug.tscn")
	if scene == null:
		push_error("Failed to load VoxelDebug scene")
		quit(1)
		return

	var instance := scene.instantiate()
	if instance == null:
		push_error("Failed to instantiate VoxelDebug scene")
		quit(1)
		return

	root.add_child(instance)
	await process_frame

	if not instance.has_node("VoxelWorld"):
		push_error("VoxelDebug is missing VoxelWorld")
		quit(1)
		return
	if not instance.has_node("Hud/Crosshair"):
		push_error("VoxelDebug is missing crosshair")
		quit(1)
		return
	if not instance.has_node("Hud/PowerBar"):
		push_error("VoxelDebug is missing power bar")
		quit(1)
		return
	for hud_path in ["Hud/StatusLabel", "Hud/PowerBar", "Hud/Crosshair", "Hud/Crosshair/Horizontal", "Hud/Crosshair/Vertical"]:
		var hud_control: Control = instance.get_node(hud_path)
		if hud_control.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			push_error("HUD control should ignore gameplay mouse input: %s" % hud_path)
			quit(1)
			return

	var voxel_world: Node = instance.get_node("VoxelWorld")
	if voxel_world.world_size != Vector3i(96, 24, 96):
		push_error("Debug arena should use the larger 96x24x96 map")
		quit(1)
		return

	if instance.players.size() != 10:
		push_error("Debug match should spawn 10 players")
		quit(1)
		return

	var blue_count := 0
	var red_count := 0
	for player: Variant in instance.players:
		if player.team_id == 1:
			blue_count += 1
		elif player.team_id == 2:
			red_count += 1
	if blue_count != 5 or red_count != 5:
		push_error("Debug match should spawn 5 players per team")
		quit(1)
		return

	var mesh_chunk_count := 0
	for child: Node in voxel_world.get_children():
		if child is MeshInstance3D and child.mesh != null and child.mesh.get_surface_count() > 0:
			mesh_chunk_count += 1

	if mesh_chunk_count == 0:
		push_error("VoxelDebug did not generate visible mesh chunks")
		quit(1)
		return

	var camera: Camera3D = instance.get_node("CameraPivot/Camera3D")
	var active_player: Variant = instance.turn_controller.get_active_player()
	var camera_distance: float = camera.global_position.distance_to(active_player.position)
	if camera_distance > 24.0:
		push_error("Debug camera is too far from the active player for third-person view")
		quit(1)
		return
	if camera.global_position.y < active_player.position.y + 5.0:
		push_error("Debug camera should be high enough to see over the player head")
		quit(1)
		return

	var player_one: Variant = instance.players[0]
	var player_two: Variant = instance.players[1]
	if absf(player_one.position.y - player_two.position.y) > 0.01:
		push_error("Debug arena should start flat, but player spawn heights differ")
		quit(1)
		return

	instance._try_jump_active_player()
	var velocity: Vector3 = instance.player_velocities[active_player.player_id]
	if velocity.y <= 0.0:
		push_error("Active player jump did not apply upward velocity")
		quit(1)
		return

	var active_marker: Node = instance.player_nodes[active_player.player_id]
	for part_name in ["Head", "Body", "LeftArm", "RightArm", "LeftLeg", "RightLeg"]:
		if not active_marker.has_node(part_name):
			push_error("Player humanoid marker is missing part: %s" % part_name)
			quit(1)
			return

	instance.orbit_yaw = 1.25
	instance.player_velocities[active_player.player_id] = Vector3(4.0, 0.0, 0.0)
	instance.player_walk_phases[active_player.player_id] = 1.0
	instance._update_player_nodes()
	if absf(active_marker.rotation.y - 1.25) > 0.01:
		push_error("Active player marker does not rotate with camera yaw")
		quit(1)
		return

	var left_arm: Node3D = active_marker.get_node("LeftArm")
	var right_arm: Node3D = active_marker.get_node("RightArm")
	var left_leg: Node3D = active_marker.get_node("LeftLeg")
	var right_leg: Node3D = active_marker.get_node("RightLeg")
	if absf(left_arm.rotation.x + right_arm.rotation.x) > 0.01:
		push_error("Player arms are not animated in opposite phase")
		quit(1)
		return
	if absf(left_leg.rotation.x + right_leg.rotation.x) > 0.01:
		push_error("Player legs are not animated in opposite phase")
		quit(1)
		return
	if absf(left_arm.rotation.x) < 0.01 or absf(left_leg.rotation.x) < 0.01:
		push_error("Player limb animation did not apply visible swing")
		quit(1)
		return

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	instance._input(press)
	instance._update_shot_charge(instance.max_charge_time * 0.5)
	var power_bar: ProgressBar = instance.get_node("Hud/PowerBar")
	if power_bar.value <= 40.0 or power_bar.value >= 70.0:
		push_error("Power bar does not reflect charged shot power")
		quit(1)
		return
	if instance._get_current_shot_power() <= 1.0:
		push_error("Half charge should exceed the old 1.0 max shot power")
		quit(1)
		return
	instance._update_shot_charge(instance.max_charge_time)
	if not is_equal_approx(instance._get_current_shot_power(), 4.0):
		push_error("Full charge should reach 4x shot power")
		quit(1)
		return
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	instance._input(release)
	if instance.is_charging_shot:
		push_error("LMB release did not stop shot charging")
		quit(1)
		return

	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	var yaw_before: float = instance.orbit_yaw
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(20.0, -10.0)
	instance._input(motion)
	if is_equal_approx(instance.orbit_yaw, yaw_before):
		push_error("Mouse motion input did not rotate camera yaw")
		quit(1)
		return
	instance.camera_pitch = 0.0
	var look_up_motion := InputEventMouseMotion.new()
	look_up_motion.relative = Vector2(0.0, 1000.0)
	instance._input(look_up_motion)
	if instance.camera_pitch > instance.min_camera_pitch + 0.01:
		push_error("Camera pitch should clamp to the expanded upward aiming range")
		quit(1)
		return
	var look_down_motion := InputEventMouseMotion.new()
	look_down_motion.relative = Vector2(0.0, -1000.0)
	instance._input(look_down_motion)
	if instance.camera_pitch < instance.max_camera_pitch - 0.01:
		push_error("Camera pitch should clamp to the expanded downward aiming range")
		quit(1)
		return

	instance.projectile_in_flight = false
	instance.orbit_yaw = 0.4
	instance.camera_pitch = -0.12
	instance._update_camera_transform()
	var viewport_center := root.get_visible_rect().size * 0.5
	var ray_origin: Vector3 = camera.project_ray_origin(viewport_center)
	var ray_direction: Vector3 = camera.project_ray_normal(viewport_center)
	var aimed_voxel: Vector3i = voxel_world.get_first_solid_on_ray(ray_origin, ray_direction)
	var crosshair_world_point := Vector3(aimed_voxel) + Vector3(0.5, 0.5, 0.5)
	if aimed_voxel.x < 0:
		crosshair_world_point = ray_origin + ray_direction * instance.aim_fallback_distance
	var muzzle_position: Vector3 = active_player.position + Vector3.UP * 1.3
	instance._fire_at_screen_center(4.0)
	var aimed_projectile: Node = instance.get_child(instance.get_child_count() - 1)
	var expected_aim_direction := (crosshair_world_point - muzzle_position).normalized()
	var actual_aim_direction: Vector3 = aimed_projectile.velocity.normalized()
	if actual_aim_direction.dot(expected_aim_direction) < 0.999:
		push_error("Projectile should travel from muzzle to the crosshair world point")
		quit(1)
		return
	aimed_projectile.queue_free()
	instance.projectile_in_flight = false

	instance._spawn_projectile(active_player.position + Vector3.UP * 1.3, Vector3.FORWARD, 4.0)
	var forward_projectile: Node = instance.get_child(instance.get_child_count() - 1)
	if absf(forward_projectile.velocity.y) > 0.01:
		push_error("Forward aim should not receive artificial vertical projectile boost")
		quit(1)
		return
	forward_projectile.queue_free()
	instance.projectile_in_flight = false

	instance._spawn_projectile(active_player.position + Vector3.UP * 1.3, (Vector3.FORWARD + Vector3.UP).normalized(), 4.0)
	var upward_projectile: Node = instance.get_child(instance.get_child_count() - 1)
	if upward_projectile.velocity.y <= 0.0:
		push_error("Upward aim should produce upward projectile velocity")
		quit(1)
		return
	upward_projectile.queue_free()

	print("Debug scene smoke passed with %d visible mesh chunks" % mesh_chunk_count)
	quit(0)
