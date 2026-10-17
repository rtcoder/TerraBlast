extends RefCounted
## Desktop input adapter; gameplay validation remains in MatchRunner.
static func handle(scene: Node, event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_TAB:
		scene.scoreboard.visible = event.pressed
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F2:
			if scene.session.playback != null:
				return
			var open: bool = not scene.backend_menu.panel.visible
			scene._close_overlays()
			scene.backend_menu.toggle(open)
			return
		if event.keycode == KEY_P:
			scene._toggle_pause()
			return
		if event.keycode == KEY_F5:
			scene._toggle_setup()
			return
		if event.keycode == KEY_F6:
			scene._toggle_help()
			return
		if event.keycode == KEY_F7:
			scene._toggle_lobby()
			return
		if event.keycode == KEY_F3:
			scene._toggle_settings()
			return
		if event.keycode == KEY_F1 and not scene.remote_mode:
			scene.debug_panel.visible = not scene.debug_panel.visible
			return
		if event.keycode == KEY_F4 and scene.remote_mode and scene.network != null:
			scene.network.retry_connection()
			return
	if event is InputEventKey and event.pressed and event.keycode in [KEY_BRACKETLEFT, KEY_BRACKETRIGHT]:
		scene._adjust_debug_gravity(-1.0 if event.keycode == KEY_BRACKETLEFT else 1.0)
	if scene.menu_open:
		return
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					if not scene.is_aiming and Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
						Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
						scene.mouse_look_enabled = true
						return
					scene._start_charging_shot()
				else:
					scene._release_charged_shot()
			MOUSE_BUTTON_RIGHT:
				scene.is_aiming = event.pressed and scene._can_control() and not scene.projectile_in_flight and not scene.turn_controller.has_winner()
				if scene.is_aiming:
					Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
					scene.mouse_look_enabled = true
				else:
					scene._cancel_aim()
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					scene.camera_distance = clampf(scene.camera_distance + (-1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0), 6.0, 18.0)
					scene._update_camera_transform()
	if event is InputEventMouseMotion and scene.mouse_look_enabled:
		scene.orbit_yaw -= event.relative.x * 0.006 * scene.preferences.sensitivity
		scene.camera_visual_yaw = scene.orbit_yaw
		var sign_y := -1.0 if scene.preferences.invert_y else 1.0
		scene.camera_pitch = clampf(scene.camera_pitch - event.relative.y * 0.004 * scene.preferences.sensitivity * sign_y, scene.min_camera_pitch, scene.max_camera_pitch)
		scene._update_camera_transform()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_1, KEY_2, KEY_3]:
			scene._select_weapon(event.keycode - KEY_1 + 1)
		elif event.keycode == KEY_R:
			scene.restart_match()
		elif event.keycode == KEY_SPACE:
			scene._try_jump_active_player()
		elif event.keycode == KEY_ESCAPE:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			scene.mouse_look_enabled = false
			scene._cancel_aim()

static func move_axis() -> Vector2:
	var input_vector := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input_vector.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_vector.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input_vector.y += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_vector.y -= 1.0
	return input_vector.normalized() if input_vector.length_squared() > 1.0 else input_vector

