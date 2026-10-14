extends Node3D

const DebugProjectile := preload("res://scripts/client/debug/debug_projectile.gd")
const PlayerActionCommand := preload("res://scripts/core/turns/player_action_command.gd")
const PlayerState := preload("res://scripts/core/rules/player_state.gd")
const MatchFactory := preload("res://scripts/core/rules/match_factory.gd")
const Simulation := preload("res://scripts/core/projectiles/projectile_simulation.gd")
const TurnController := preload("res://scripts/core/turns/turn_controller.gd")

@onready var voxel_world: Node3D = $VoxelWorld
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var camera_pivot: Node3D = $CameraPivot
@onready var hud_label: Label = $Hud/StatusLabel
@onready var power_bar: ProgressBar = $Hud/PowerBar

var effects: Node3D
var backend_menu: CanvasLayer
var menu_open := false
var network: Node
var network_status := ""
var remote_mode := false
var runner: RefCounted
var rules: Resource
var selected_weapon_id := 1
var active_projectile: Node3D
var pending_result: Dictionary = {}

var orbit_yaw := -0.7
var camera_pitch := -0.32
var min_camera_pitch := -1.05
var max_camera_pitch := 0.45
var camera_distance := 11.0
var camera_height := 3.4
var camera_side_offset := 0.8
var camera_ground_clearance := 0.35
var camera_ground_probe_steps := 32
var camera_focus_position := Vector3.ZERO
var camera_visual_yaw := orbit_yaw
var camera_transition_initialized := false
var camera_focus_transition_speed := 2.8
var camera_yaw_transition_speed := 3.5
var move_speed := 8.0
var jump_speed := 8.5
var player_gravity := 22.0
var player_velocities: Dictionary = {}
var player_walk_phases: Dictionary = {}
var players: Array = []
var player_nodes: Dictionary = {}
var turn_controller: RefCounted
var projectile_in_flight := false
var is_aiming := false
var trajectory_preview: MeshInstance3D
var is_charging_shot := false
var mouse_look_enabled := true
var shot_charge := 0.0
var min_shot_power := 0.25
var max_shot_power := 4.0
var max_charge_time := 1.4
var aim_fallback_distance := 80.0

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	remote_mode = GameConfig.mode == "client"
	_setup_players()
	if remote_mode:
		_connect_network(GameConfig.argument("--host", "127.0.0.1"))
	_setup_trajectory_preview()
	effects = load("res://scripts/client/vfx/match_effects.gd").new()
	effects.name = "MatchEffects"
	add_child(effects)
	_update_camera_transform()
	_update_power_bar()
	_update_hud()
	backend_menu = load("res://scripts/client/backend/backend_menu.gd").new()
	add_child(backend_menu)
	backend_menu.menu_visibility_changed.connect(func(open: bool):
		menu_open = open
		_cancel_aim()
		mouse_look_enabled = not open
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED)
	)
	backend_menu.connect_game.connect(func(host: String):
		remote_mode = true
		if is_instance_valid(network):
			network.close()
			network.queue_free()
		_connect_network(host)
	)

func _physics_process(delta: float) -> void:
	if not remote_mode and not projectile_in_flight:
		var events: Array = runner.tick(delta)
		if not events.is_empty():
			effects.play_events(events)
			_cancel_aim()
			_face_camera_toward_enemy()
	_update_hud()
	_update_shot_charge(delta)
	_update_active_player_movement(delta)
	if not projectile_in_flight:
		_update_player_nodes()
		_update_camera_transition(delta)
		_update_camera_transform()
	_update_trajectory_preview()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F2:
		backend_menu.toggle(not menu_open)
		get_viewport().set_input_as_handled()
		return
	if menu_open:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if not is_aiming and Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
					Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
					mouse_look_enabled = true
					return
				mouse_look_enabled = true
				_start_charging_shot()
			else:
				_release_charged_shot()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			is_aiming = event.pressed and not projectile_in_flight and not turn_controller.has_winner()
			if is_aiming:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
				mouse_look_enabled = true
			else:
				_cancel_aim()
			_update_hud()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = maxf(6.0, camera_distance - 1.0)
			_update_camera_transform()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = minf(18.0, camera_distance + 1.0)
			_update_camera_transform()

	if event is InputEventMouseMotion and mouse_look_enabled:
		orbit_yaw -= event.relative.x * 0.006
		camera_visual_yaw = orbit_yaw
		camera_pitch = clampf(camera_pitch - event.relative.y * 0.004, min_camera_pitch, max_camera_pitch)
		_update_camera_transform()

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_1, KEY_2, KEY_3] and not projectile_in_flight:
			selected_weapon_id = event.keycode - KEY_1 + 1
			_cancel_aim()
		elif event.keycode == KEY_R:
			restart_match()
		elif event.keycode == KEY_SPACE:
			_try_jump_active_player()
		elif event.keycode == KEY_ESCAPE:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			mouse_look_enabled = false
			_cancel_aim()

func _start_charging_shot() -> void:
	if not _can_control() or not is_aiming or projectile_in_flight or turn_controller.has_winner():
		return
	is_charging_shot = true
	shot_charge = 0.0
	_update_power_bar()

func _release_charged_shot() -> void:
	if not is_charging_shot:
		return
	is_charging_shot = false
	var charged_power := _get_current_shot_power()
	_update_power_bar()
	_fire_at_screen_center(charged_power)

func _update_shot_charge(delta: float) -> void:
	if not is_charging_shot:
		return
	shot_charge = minf(max_charge_time, shot_charge + delta)
	_update_power_bar()

func _get_current_shot_power() -> float:
	var charge_ratio := clampf(shot_charge / max_charge_time, 0.0, 1.0)
	return lerpf(min_shot_power, max_shot_power, charge_ratio)

func _update_power_bar() -> void:
	if power_bar == null:
		return
	if is_charging_shot:
		power_bar.value = inverse_lerp(min_shot_power, max_shot_power, _get_current_shot_power()) * 100.0
	else:
		power_bar.value = 0.0

func _fire_at_screen_center(shot_power: float = 1.0) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	_fire_at_mouse(viewport_size * 0.5, shot_power)

func _fire_at_mouse(screen_position: Vector2, shot_power: float = 1.0) -> void:
	if not _can_control():
		return
	if projectile_in_flight or turn_controller.has_winner():
		return

	var active_player: Variant = turn_controller.get_active_player()
	var muzzle_position: Vector3 = active_player.position + Vector3.UP * 1.3
	var aim_point := _get_crosshair_world_point(screen_position)
	var aim_direction := aim_point - muzzle_position
	if aim_direction.length_squared() <= 0.001:
		return

	var command: RefCounted = PlayerActionCommand.new()
	command.player_id = active_player.player_id
	command.turn_id = turn_controller.turn_id
	command.generation = turn_controller.generation
	command.weapon_id = selected_weapon_id
	command.aim_direction = aim_direction.normalized()
	command.shot_power = shot_power
	if remote_mode:
		network.send_command(command)
		_cancel_aim()
		return
	var result: Dictionary = runner.submit(command)
	if not result.ok:
		return
	_play_result(result)

func _get_crosshair_world_point(screen_position: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	if direction.length_squared() <= 0.001:
		return origin

	var normalized_direction := direction.normalized()
	var aimed_voxel: Vector3i = voxel_world.get_first_solid_on_ray(origin, normalized_direction)
	if aimed_voxel.x >= 0:
		return Vector3(aimed_voxel) + Vector3(0.5, 0.5, 0.5)
	return origin + normalized_direction * aim_fallback_distance

func _play_result(result: Dictionary) -> void:
	projectile_in_flight = true
	pending_result = result
	_cancel_aim()
	active_projectile = DebugProjectile.new()
	add_child(active_projectile)
	active_projectile.play_path(result.path, rules.projectile_step)
	active_projectile.finished.connect(_finish_playback)

func _finish_playback() -> void:
	effects.play_events(pending_result.get("events", []))
	voxel_world.refresh_deltas(pending_result.get("deltas", []))
	pending_result = {}
	active_projectile = null
	projectile_in_flight = false
	for id in player_velocities:
		player_velocities[id] = Vector3.ZERO
	_update_player_nodes()
	_face_camera_toward_enemy()
	_update_hud()

func _setup_players() -> void:
	runner = MatchFactory.create_match(2 if remote_mode else 10)
	rules = runner.rules
	move_speed = rules.move_speed
	jump_speed = rules.jump_speed
	player_gravity = rules.player_gravity
	min_shot_power = rules.min_shot_power
	max_shot_power = rules.max_shot_power
	max_charge_time = rules.max_charge_time
	voxel_world.world = runner.world
	voxel_world.material_configs = runner.materials
	_bind_players()

func _bind_players() -> void:
	players = runner.state.players
	turn_controller = runner.state
	for node in player_nodes.values():
		node.queue_free()
	player_nodes.clear()
	player_velocities.clear()
	player_walk_phases.clear()
	for player in players:
		player_velocities[player.player_id] = Vector3.ZERO
		player_walk_phases[player.player_id] = 0.0
		var color := Color(0.15, 0.36, 1.0) if player.team_id == 1 else Color(1.0, 0.18, 0.12)
		var marker := _create_player_marker(color)
		add_child(marker)
		player_nodes[player.player_id] = marker
	_face_camera_toward_enemy()
	_update_player_nodes()

func restart_match() -> void:
	if remote_mode:
		network.restart_match()
		return
	if is_instance_valid(active_projectile):
		active_projectile.queue_free()
	active_projectile = null
	projectile_in_flight = false
	pending_result = {}
	runner.reset()
	selected_weapon_id = 1
	_bind_players()
	_cancel_aim()
	voxel_world._mark_all_chunks_dirty()
	voxel_world.rebuild_dirty_chunks()

func _create_player_marker(color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "PlayerMarker"

	var body_material := _player_material(color)
	var skin_material := _player_material(Color(0.95, 0.76, 0.54))
	var dark_material := _player_material(color.darkened(0.22))

	_add_box_part(root, "Body", Vector3(0.72, 0.95, 0.42), Vector3(0.0, 1.15, 0.0), body_material)
	_add_box_part(root, "Head", Vector3(0.58, 0.58, 0.58), Vector3(0.0, 1.95, 0.0), skin_material)
	_add_box_part(root, "LeftArm", Vector3(0.26, 0.82, 0.30), Vector3(-0.58, 1.13, 0.0), dark_material)
	_add_box_part(root, "RightArm", Vector3(0.26, 0.82, 0.30), Vector3(0.58, 1.13, 0.0), dark_material)
	_add_box_part(root, "LeftLeg", Vector3(0.30, 0.82, 0.34), Vector3(-0.20, 0.42, 0.0), body_material)
	_add_box_part(root, "RightLeg", Vector3(0.30, 0.82, 0.34), Vector3(0.20, 0.42, 0.0), body_material)

	var active_ring := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.56
	ring.outer_radius = 0.66
	active_ring.mesh = ring
	active_ring.name = "ActiveRing"
	active_ring.rotation_degrees.x = 90.0
	var ring_material := StandardMaterial3D.new()
	ring_material.albedo_color = Color(1.0, 0.9, 0.2)
	ring_material.emission_enabled = true
	ring_material.emission = Color(1.0, 0.82, 0.08)
	active_ring.material_override = ring_material
	root.add_child(active_ring)
	return root

func _add_box_part(parent: Node3D, part_name: String, size: Vector3, position: Vector3, material: Material) -> void:
	var part := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	part.name = part_name
	part.mesh = mesh
	part.position = position
	part.material_override = material
	parent.add_child(part)

func _player_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	return material

func _update_player_nodes() -> void:
	var active_player: Variant = turn_controller.get_active_player()
	for player: Variant in players:
		var marker: Node3D = player_nodes[player.player_id]
		marker.position = player.position
		marker.visible = player.is_alive
		if active_player != null and player.player_id == active_player.player_id:
			marker.rotation.y = orbit_yaw
		else:
			marker.rotation.y = player.rotation.get_euler().y
		_update_player_limb_animation(player, marker)
		var active_ring: MeshInstance3D = marker.get_node("ActiveRing")
		active_ring.visible = active_player != null and player.player_id == active_player.player_id

func _update_player_limb_animation(player: Variant, marker: Node3D) -> void:
	var velocity: Vector3 = player_velocities.get(player.player_id, Vector3.ZERO)
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var move_amount := clampf(horizontal_speed / move_speed, 0.0, 1.0)
	var phase: float = player_walk_phases.get(player.player_id, 0.0)
	var swing := sin(phase) * 0.62 * move_amount

	_set_part_rotation(marker, "LeftArm", Vector3(swing, 0.0, 0.0))
	_set_part_rotation(marker, "RightArm", Vector3(-swing, 0.0, 0.0))
	_set_part_rotation(marker, "LeftLeg", Vector3(-swing, 0.0, 0.0))
	_set_part_rotation(marker, "RightLeg", Vector3(swing, 0.0, 0.0))

func _set_part_rotation(marker: Node3D, part_name: String, rotation: Vector3) -> void:
	var part: Node3D = marker.get_node(part_name)
	part.rotation = rotation

func _update_hud() -> void:
	var active_player: Variant = turn_controller.get_active_player()
	var status := ""
	if turn_controller.has_winner():
		status = _winner_status_text()
	elif active_player != null:
		status = "Turn %d: %s" % [turn_controller.turn_id + 1, active_player.display_name]
	status += "\n%s   %s" % [_team_status_text(1, "Blue"), _team_status_text(2, "Red")]
	var weapon: Resource = runner.weapons[selected_weapon_id]
	var ammo: int = runner.state.inventory[active_player.player_id][selected_weapon_id] if active_player != null else 0
	status += "\n%s | Ammo: %s | %.0fs | 1-3 weapon / R restart / F2 multiplayer" % [weapon.display_name, "unlimited" if ammo < 0 else str(ammo), runner.state.time_remaining]
	status += "\n%s" % ("Projectile in flight" if projectile_in_flight else ("Aiming" if is_aiming else "Camera mode"))
	status += "\nHold RMB aim + LMB charge / release fire   WASD move   Esc cancel"
	if remote_mode:
		status += "\n" + network_status
	hud_label.text = status

func _team_status_text(team_id: int, label: String) -> String:
	var living_count := 0
	var total_health := 0
	for player: Variant in players:
		if player.team_id != team_id:
			continue
		if player.is_alive:
			living_count += 1
		total_health += player.health
	return "%s %d/5 HP %d" % [label, living_count, total_health]

func _winner_status_text() -> String:
	var living_teams := {}
	for player: Variant in players:
		if player.is_alive:
			living_teams[player.team_id] = true
	if living_teams.size() != 1:
		return "Draw"
	var team_id: int = living_teams.keys()[0]
	return "Winner: Blue" if team_id == 1 else "Winner: Red"

func _update_active_player_movement(delta: float) -> void:
	if menu_open:
		return
	if remote_mode:
		if _can_control() and not projectile_in_flight:
			network.move_player(_get_move_input(), orbit_yaw)
		return
	if turn_controller == null or projectile_in_flight or turn_controller.has_winner():
		return

	var active_player: Variant = turn_controller.get_active_player()
	if active_player == null or not active_player.is_alive:
		return

	active_player.rotation = Basis(Vector3.UP, orbit_yaw)

	var input_vector := _get_move_input()
	var forward := Vector3(sin(orbit_yaw), 0.0, cos(orbit_yaw)).normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var move_direction := (forward * input_vector.y + right * input_vector.x)
	if move_direction.length_squared() > 0.001:
		move_direction = move_direction.normalized()

	var velocity: Vector3 = player_velocities.get(active_player.player_id, Vector3.ZERO)
	velocity.x = move_direction.x * move_speed
	velocity.z = move_direction.z * move_speed
	velocity.y -= player_gravity * delta

	active_player.position += velocity * delta
	active_player.position.x = clampf(active_player.position.x, 1.0, float(voxel_world.world_size.x - 2))
	active_player.position.z = clampf(active_player.position.z, 1.0, float(voxel_world.world_size.z - 2))

	var ground_y: float = voxel_world.get_surface_y(floori(active_player.position.x), floori(active_player.position.z))
	if active_player.position.y <= ground_y:
		active_player.position.y = ground_y
		velocity.y = 0.0

	player_velocities[active_player.player_id] = velocity
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if horizontal_speed > 0.05:
		var phase: float = player_walk_phases.get(active_player.player_id, 0.0)
		player_walk_phases[active_player.player_id] = phase + delta * 9.0 * clampf(horizontal_speed / move_speed, 0.25, 1.0)

func _try_jump_active_player() -> void:
	if remote_mode:
		if _can_control() and not projectile_in_flight:
			network.move_player(_get_move_input(), orbit_yaw, true)
		return
	if turn_controller == null or projectile_in_flight or turn_controller.has_winner():
		return

	var active_player: Variant = turn_controller.get_active_player()
	if active_player == null:
		return

	var ground_y: float = voxel_world.get_surface_y(floori(active_player.position.x), floori(active_player.position.z))
	if active_player.position.y > ground_y + 0.05:
		return

	var velocity: Vector3 = player_velocities.get(active_player.player_id, Vector3.ZERO)
	velocity.y = jump_speed
	player_velocities[active_player.player_id] = velocity

func _get_move_input() -> Vector2:
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

func _face_camera_toward_enemy() -> void:
	var active_player: Variant = turn_controller.get_active_player()
	if active_player == null:
		return

	var target := Vector3.ZERO
	var target_count := 0
	for player: Variant in players:
		if player.team_id != active_player.team_id and player.is_alive:
			target += player.position
			target_count += 1

	if target_count == 0:
		return

	target /= float(target_count)
	var to_target: Vector3 = target - active_player.position
	orbit_yaw = atan2(to_target.x, to_target.z)

func _update_camera_transform() -> void:
	var active_player: Variant = turn_controller.get_active_player()
	if active_player == null:
		return

	var target: Vector3 = active_player.position + Vector3.UP * camera_height
	_ensure_camera_transition_initialized(target)
	target = camera_focus_position
	var forward := Vector3(sin(camera_visual_yaw), 0.0, cos(camera_visual_yaw)).normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var camera_position: Vector3 = target - forward * camera_distance + right * camera_side_offset
	camera_position.y += sin(-camera_pitch) * camera_distance
	camera_position = _get_ground_limited_camera_position(target, camera_position)

	camera_pivot.position = target
	camera_pivot.rotation = Vector3.ZERO
	camera.global_position = camera_position
	camera.look_at(target + forward * 8.0 + Vector3.UP * camera_pitch * 8.0, Vector3.UP)

func _get_ground_limited_camera_position(target: Vector3, ideal_position: Vector3) -> Vector3:
	for step in range(camera_ground_probe_steps + 1):
		var t := 1.0 - (float(step) / float(camera_ground_probe_steps))
		var candidate := target.lerp(ideal_position, t)
		if _is_camera_above_ground(candidate):
			return candidate
	return target

func _is_camera_above_ground(position: Vector3) -> bool:
	var ground_y: float = voxel_world.get_surface_y(floori(position.x), floori(position.z))
	return position.y >= ground_y + camera_ground_clearance

func _update_camera_transition(delta: float) -> void:
	var active_player: Variant = turn_controller.get_active_player()
	if active_player == null:
		return

	var target: Vector3 = active_player.position + Vector3.UP * camera_height
	_ensure_camera_transition_initialized(target)
	var focus_weight := clampf(1.0 - exp(-camera_focus_transition_speed * delta), 0.0, 1.0)
	var yaw_weight := clampf(1.0 - exp(-camera_yaw_transition_speed * delta), 0.0, 1.0)
	camera_focus_position = camera_focus_position.lerp(target, focus_weight)
	camera_visual_yaw = lerp_angle(camera_visual_yaw, orbit_yaw, yaw_weight)

func _ensure_camera_transition_initialized(target: Vector3) -> void:
	if camera_transition_initialized:
		return
	camera_focus_position = target
	camera_visual_yaw = orbit_yaw
	camera_transition_initialized = true

func _cancel_aim() -> void:
	is_aiming = false
	is_charging_shot = false
	shot_charge = 0.0
	_update_power_bar()
	if trajectory_preview != null:
		trajectory_preview.hide()
	_update_hud()

func _get_trajectory_points() -> PackedVector3Array:
	var player: Variant = turn_controller.get_active_player()
	if player == null:
		return PackedVector3Array()
	var origin: Vector3 = player.position + Vector3.UP * 1.3
	var target := _get_crosshair_world_point(get_viewport().get_visible_rect().size * 0.5)
	var result := Simulation.simulate(runner.world, origin, target - origin, _get_current_shot_power(), runner.weapons[selected_weapon_id], rules, runner.materials)
	return result.path

func _setup_trajectory_preview() -> void:
	trajectory_preview = MeshInstance3D.new()
	trajectory_preview.name = "TrajectoryPreview"
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.85, 0.15)
	trajectory_preview.material_override = material
	trajectory_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(trajectory_preview)
	trajectory_preview.hide()

func _update_trajectory_preview() -> void:
	trajectory_preview.visible = is_aiming and not projectile_in_flight and not turn_controller.has_winner()
	if not trajectory_preview.visible:
		return
	var points := _get_trajectory_points()
	if points.size() < 2:
		trajectory_preview.hide()
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point in points:
		mesh.surface_add_vertex(point)
	mesh.surface_end()
	trajectory_preview.mesh = mesh


func _can_control() -> bool:
	if menu_open:
		return false
	if not remote_mode:
		return true
	var active = turn_controller.get_active_player()
	return network != null and network.ready_for_match and active != null and active.player_id == network.player_id

func _connect_network(host: String) -> void:
	network = load("res://scripts/networking/transport/match_client.gd").new()
	add_child(network)
	network.status_changed.connect(func(message: String): network_status = message)
	network.synchronized.connect(_sync_network)
	network.result_received.connect(func(result: Dictionary):
		runner = network.runner
		players = runner.state.players
		turn_controller = runner.state
		_play_result(result)
	)
	network.connect_to_server(host, int(GameConfig.argument("--port", "19170")))

func _sync_network() -> void:
	var replaced: bool = runner != network.runner
	var previous_turn: int = turn_controller.turn_id
	runner = network.runner
	voxel_world.world = runner.world
	if replaced:
		if is_instance_valid(active_projectile):
			active_projectile.queue_free()
		active_projectile = null
		pending_result = {}
		projectile_in_flight = false
		_bind_players()
		voxel_world._mark_all_chunks_dirty()
		voxel_world.rebuild_dirty_chunks()
	else:
		players = runner.state.players
		turn_controller = runner.state
	if previous_turn != turn_controller.turn_id:
		_cancel_aim()
		_face_camera_toward_enemy()
