extends Node3D

const DebugProjectile := preload("res://scripts/client/debug/debug_projectile.gd")
const PlayerActionCommand := preload("res://scripts/core/turns/player_action_command.gd")
const PlayerState := preload("res://scripts/core/rules/player_state.gd")
const MatchFactory := preload("res://scripts/core/rules/match_factory.gd")
const PlayerMotion := preload("res://scripts/core/rules/player_motion.gd")
const Simulation := preload("res://scripts/core/projectiles/projectile_simulation.gd")
const TurnController := preload("res://scripts/core/turns/turn_controller.gd")

@onready var voxel_world: Node3D = $VoxelWorld
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var camera_pivot: Node3D = $CameraPivot
@onready var hud_label: Label = $Hud/StatusLabel
@onready var power_bar: ProgressBar = $Hud/PowerBar

var archive_ui: RefCounted
var workflows: RefCounted
var bindings: RefCounted
var library: RefCounted
var library_panel: PanelContainer
var lobby_panel: PanelContainer
var shown_lobby_generation := -1
var last_lobby_started := false
var session: RefCounted
var end_presented_key := ""
var local_paused := false
var match_panels: Control
var turn_banner: Label
var turn_banner_count := 0
var banner_remaining := 0.0
var last_shot_label: Label
var preferences: RefCounted
var settings_panel: PanelContainer
var scoreboard: Label
var debug_panel: Label
var aim_indicator: MeshInstance3D
var weapon_by_player: Dictionary = {}
var selection_player := ""
var observed_turn := -1
var observed_generation := -1
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
	preferences = preload("res://scripts/client/settings/client_settings.gd").new()
	preferences.load_from()
	preferences.apply()
	bindings = preload("res://scripts/client/input/input_bindings.gd").new()
	bindings.load_settings()
	library = preload("res://scripts/core/storage/local_archive_library.gd").new()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	remote_mode = GameConfig.mode == "client"
	_setup_players()
	session = preload("res://scripts/client/session/local_session.gd").new(self)
	if remote_mode:
		_connect_network(GameConfig.argument("--host", "127.0.0.1"))
	_setup_client_panels()
	_setup_trajectory_preview()
	effects = load("res://scripts/client/vfx/match_effects.gd").new()
	effects.name = "MatchEffects"
	add_child(effects)
	_update_camera_transform()
	_update_power_bar()
	_update_hud()
	backend_menu = load("res://scripts/client/backend/backend_menu.gd").new()
	add_child(backend_menu)
	backend_menu.retry_requested.connect(func():
		if remote_mode and network != null: network.retry_connection())
	backend_menu.menu_visibility_changed.connect(func(_open: bool): _refresh_menu_state())
	workflows = preload("res://scripts/client/session/client_workflows.gd").new(self)
	workflows.setup()
	archive_ui = preload("res://scripts/client/session/archive_workflows.gd").new(self)
	archive_ui.setup()
	_apply_client_preferences()
	backend_menu.connect_game.connect(func(host: String):
		_begin_network_connection(host, backend_menu.selected_port())
	)

func _physics_process(delta: float) -> void:
	_advance_replay(delta)
	if archive_ui != null: archive_ui.update(delta)
	if not remote_mode and not projectile_in_flight and not local_paused and session.playback == null and runner.state.status == "playing" and (workflows == null or not workflows.training.active):
		var events: Array = session.recorder.tick(runner, delta)
		if not events.is_empty():
			effects.play_events(events)
			if workflows != null: workflows.consume(events)
			_cancel_aim()
			_face_camera_toward_enemy()
	session.update_bot()
	_sync_selected_weapon()
	if not projectile_in_flight and (observed_turn != turn_controller.turn_id or observed_generation != turn_controller.generation):
		_cancel_aim()
		observed_turn = turn_controller.turn_id
		observed_generation = turn_controller.generation
		_show_turn_banner()
	_update_scoreboard()
	_update_debug_panel()
	_update_match_panels(delta)
	_update_hud()
	_update_shot_charge(delta)
	_update_active_player_movement(delta)
	if not projectile_in_flight:
		_update_player_nodes()
		_update_camera_transition(delta)
		_update_camera_transform()
	_update_trajectory_preview()
	if workflows != null: workflows.update(delta)

func _input(event: InputEvent) -> void:
	if archive_ui != null and archive_ui.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	preload("res://scripts/client/input/desktop_input.gd").handle(self, event)

func _start_charging_shot() -> void:
	if not _can_control() or not is_aiming or projectile_in_flight or turn_controller.has_winner():
		return
	is_charging_shot = true
	if workflows != null: workflows.training.observe_intent("charge")
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
	if workflows != null and not workflows.before_shot(command): return
	var result: Dictionary = session.recorder.submit(runner, command)
	if workflows != null: workflows.after_shot(command,result)
	if not result.ok:
		return
	_play_result(result)

func _get_crosshair_world_point(screen_position: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	if direction.length_squared() <= 0.001:
		return origin

	var normalized_direction := direction.normalized()
	var aimed_voxel: Vector3i = preload("res://scripts/core/voxels/voxel_raycast.gd").first_solid(runner.world, origin, normalized_direction, runner.materials)
	if aimed_voxel.x >= 0:
		return Vector3(aimed_voxel) + Vector3(0.5, 0.5, 0.5)
	return origin + normalized_direction * aim_fallback_distance

func _play_result(result: Dictionary) -> void:
	projectile_in_flight = true
	pending_result = result
	_cancel_aim()
	if result.path.is_empty():
		_finish_playback()
		return
	active_projectile = DebugProjectile.new()
	add_child(active_projectile)
	active_projectile.play_path(result.path, rules.projectile_step)
	active_projectile.finished.connect(_finish_playback)

func _finish_playback() -> void:
	effects.play_events(pending_result.get("events", []))
	if workflows != null: workflows.consume(pending_result.get("events",[]))
	voxel_world.refresh_deltas(pending_result.get("deltas", []))
	pending_result = {}
	if is_instance_valid(active_projectile):
		active_projectile.queue_free()
	active_projectile = null
	projectile_in_flight = false
	for id in player_velocities:
		player_velocities[id] = Vector3.ZERO
	_update_player_nodes()
	_face_camera_toward_enemy()
	_update_hud()

func _setup_players() -> void:
	runner = MatchFactory.create_match(2 if remote_mode else int(GameConfig.argument("--players", "10")), GameConfig.map_path(), GameConfig.argument("--preset", "classic"))
	rules = runner.rules
	move_speed = rules.move_speed
	jump_speed = rules.jump_speed
	player_gravity = rules.player_gravity
	min_shot_power = rules.min_shot_power
	max_shot_power = rules.max_shot_power
	max_charge_time = rules.max_charge_time
	voxel_world.set_world(runner.world, runner.materials)
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
		var color := preload("res://scripts/client/ui/team_visual_scheme.gd").color(player.team_id,preferences.team_palette)
		var marker := _create_player_marker(color)
		add_child(marker)
		player_nodes[player.player_id] = marker
	_face_camera_toward_enemy()
	_update_player_nodes()

func restart_match() -> void:
	if session.playback != null:
		return
	if _uses_ready_lobby():
		_vote_rematch()
		return
	end_presented_key = ""
	effects.clear()
	_close_overlays()
	if remote_mode:
		network.restart_match()
		return
	if is_instance_valid(active_projectile):
		active_projectile.queue_free()
	active_projectile = null
	projectile_in_flight = false
	pending_result = {}
	runner.reset()
	session.new_recording()
	selected_weapon_id = 1
	weapon_by_player.clear()
	selection_player = ""
	_bind_players()
	_cancel_aim()
	voxel_world._mark_all_chunks_dirty()
	voxel_world.rebuild_dirty_chunks()
	last_shot_label.text = ""
	_update_match_panels(0.0)

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
	var label := Label3D.new()
	label.name = "HealthLabel"
	label.position = Vector3(0, 2.65, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 28
	label.outline_size = 6
	label.pixel_size = 0.007
	root.add_child(label)
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
		var health_label: Label3D = marker.get_node("HealthLabel")
		health_label.text = "[%s] %s  HP %d%s" % [preload("res://scripts/client/ui/team_visual_scheme.gd").label(player.team_id), player.display_name, player.health, " •" if player == active_player else ""]
		health_label.modulate = preload("res://scripts/client/ui/team_visual_scheme.gd").color(player.team_id,preferences.team_palette)
		marker.get_node("Body").material_override.albedo_color = health_label.modulate
		marker.get_node("LeftArm").material_override.albedo_color = health_label.modulate.darkened(0.22)
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
	if runner.state.status == "ended":
		status = _winner_status_text()
	elif active_player != null:
		status = "Turn %d: %s" % [turn_controller.turn_id + 1, active_player.display_name]
	status += "\n%s   %s" % [_team_status_text(1, "Blue"), _team_status_text(2, "Red")]
	var weapon: Resource = runner.weapons[selected_weapon_id]
	var ammo: int = runner.state.inventory[active_player.player_id][selected_weapon_id] if active_player != null else 0
	status += "\n%s | Ammo: %s | %.0fs | 1–3 weapon | R restart | P menu | F6 help" % [weapon.display_name, "unlimited" if ammo < 0 else str(ammo), runner.state.time_remaining]
	status += "\n%s" % ("Projectile in flight" if projectile_in_flight else ("Aiming" if is_aiming else "Camera mode"))
	status += "\nHold RMB aim + LMB charge / release fire   %s%s%s%s move   Esc cancel" % [bindings.label("move_forward"),bindings.label("move_left"),bindings.label("move_back"),bindings.label("move_right")]
	if remote_mode:
		status += "\n" + network_status + " | F4 retry | F7 lobby"
		if network != null:
			status += "\n" + preload("res://scripts/client/ui/lobby_panel.gd").waiting_text(network.lobby_state,network.match_phase,network.ready_for_match)
		if network != null:
			status += " | %s | %d%% | RTT %.0f ms" % [network.match_phase, int(100.0 * network.snapshot_progress.completed / maxi(1, network.snapshot_progress.total)), network.latency_ms]
	if not remote_mode:
		status += "\nReplay inspection" if session.playback != null else ("\nSolo / %s%s" % [session.options.difficulty, " — Bot thinking" if session.is_bot_turn() else " — Your team"] if session.options.mode == "solo" else "\nLocal hotseat")
	if not remote_mode and not session.recorder.recording_error.is_empty():
		status += "\nRecording stopped: " + session.recorder.recording_error
	hud_label.text = status
	hud_label.visible = not menu_open

func _team_status_text(team_id: int, label: String) -> String:
	var living_count := 0
	var team_count := 0
	var total_health := 0
	for player: Variant in players:
		if player.team_id != team_id:
			continue
		team_count += 1
		if player.is_alive:
			living_count += 1
		total_health += player.health
	return "%s %d/%d HP %d" % [label, living_count, team_count, total_health]

func _winner_status_text() -> String:
	if runner.state.status == "ended" and runner.state.winner_team == 0:
		return "Draw"
	var living_teams := {}
	for player: Variant in players:
		if player.is_alive:
			living_teams[player.team_id] = true
	if living_teams.size() != 1:
		return "Draw"
	var team_id: int = living_teams.keys()[0]
	return "Winner: Blue" if team_id == 1 else "Winner: Red"

func _update_active_player_movement(delta: float) -> void:
	if not _can_control():
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

	var velocity: Vector3 = session.recorder.move(runner, player_velocities.get(active_player.player_id, Vector3.ZERO), _get_move_input(), orbit_yaw, false, delta)
	player_velocities[active_player.player_id] = velocity
	if workflows != null:
		workflows.training.observe_motion(active_player.position,velocity,PlayerMotion.blocked(runner.world,active_player.position+Vector3.DOWN*0.05,runner.materials),false)
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if horizontal_speed > 0.05:
		var phase: float = player_walk_phases.get(active_player.player_id, 0.0)
		player_walk_phases[active_player.player_id] = phase + delta * 9.0 * clampf(horizontal_speed / move_speed, 0.25, 1.0)

func _try_jump_active_player() -> void:
	if not _can_control():
		return
	if remote_mode:
		if _can_control() and not projectile_in_flight:
			network.move_player(_get_move_input(), orbit_yaw, true)
		return
	if turn_controller == null or projectile_in_flight or turn_controller.has_winner():
		return

	var active_player: Variant = turn_controller.get_active_player()
	if active_player == null:
		return

	if not PlayerMotion.blocked(runner.world, active_player.position + Vector3.DOWN * 0.05, runner.materials):
		return

	var velocity: Vector3 = player_velocities.get(active_player.player_id, Vector3.ZERO)
	velocity.y = jump_speed
	if workflows != null: workflows.training.observe_motion(active_player.position,velocity,true,true)
	player_velocities[active_player.player_id] = velocity

func _get_move_input() -> Vector2:
	return preload("res://scripts/client/input/desktop_input.gd").move_axis(bindings)

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
	if preferences.reduced_motion:
		camera_focus_position = target
		camera_visual_yaw = orbit_yaw
		return
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
	if workflows != null and is_charging_shot: workflows.training.observe_intent("cancel")
	is_aiming = false
	is_charging_shot = false
	shot_charge = 0.0
	_update_power_bar()
	if trajectory_preview != null:
		trajectory_preview.hide()
	if aim_indicator != null:
		aim_indicator.hide()
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
	aim_indicator.visible = _can_control() and is_aiming and not projectile_in_flight
	trajectory_preview.visible = aim_indicator.visible and preferences.show_trajectory
	if workflows != null and workflows.training.active:
		trajectory_preview.visible = aim_indicator.visible and workflows.training.assistance != "none"
	if not aim_indicator.visible:
		return
	var points := _get_trajectory_points()
	if workflows != null and workflows.training.active and workflows.training.assistance == "partial":
		points = points.slice(0,maxi(2,points.size()/3))
	if points.size() < 2:
		trajectory_preview.hide()
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point in points:
		mesh.surface_add_vertex(point)
	mesh.surface_end()
	trajectory_preview.mesh = mesh
	var player = turn_controller.get_active_player()
	var color := Color(0.2, 0.5, 1.0) if player.team_id == 1 else Color(1.0, 0.25, 0.15)
	trajectory_preview.material_override.albedo_color = color
	aim_indicator.material_override.albedo_color = color
	var direction: Vector3 = (points[1] - points[0]).normalized()
	var arrow := ImmediateMesh.new()
	arrow.surface_begin(Mesh.PRIMITIVE_LINES)
	arrow.surface_add_vertex(points[0])
	arrow.surface_add_vertex(points[0] + direction * 3.0)
	arrow.surface_end()
	aim_indicator.mesh = arrow


func _can_control() -> bool:
	if workflows != null and workflows.blocked(): return false
	if menu_open or local_paused or runner.state.status != "playing" or session.playback != null or session.is_bot_turn():
		return false
	if not remote_mode:
		return true
	var active = turn_controller.get_active_player()
	return network != null and network.ready_for_match and network.match_phase == "playing" and active != null and active.player_id == network.player_id

func _connect_network(host: String, port: int = -1) -> void:
	network = load("res://scripts/networking/transport/match_client.gd").new()
	var source = network
	add_child(source)
	source.status_changed.connect(func(message: String):
		if network != source or not remote_mode:
			return
		network_status = message
		if backend_menu != null: backend_menu.present_game_connection(source.status_snapshot())
		if lobby_panel != null: lobby_panel.present_connection(source.status_snapshot())
		if lobby_panel != null:
			lobby_panel.feedback.text = message
			_present_lobby()
	)
	source.synchronized.connect(func():
		if network == source and remote_mode:
			_sync_network()
			if backend_menu != null and not source.get_meta("recorded_connection",false):
				source.set_meta("recorded_connection",true)
				backend_menu.record_connection_success(source.last_host,source.last_port)
	)
	if source.has_signal("metrics_changed"):
		source.metrics_changed.connect(func():
			if network == source and remote_mode:
				if backend_menu != null: backend_menu.present_game_connection(source.status_snapshot())
				if lobby_panel != null: lobby_panel.present_connection(source.status_snapshot()))
	source.rejected.connect(func(reason):
		if network == source and remote_mode and lobby_panel != null: lobby_panel.operation_rejected(reason))
	source.snapshot_progress_changed.connect(func(_completed,_total):
		if network == source and remote_mode:
			if backend_menu != null: backend_menu.present_game_connection(source.status_snapshot())
			if lobby_panel != null: lobby_panel.present_connection(source.status_snapshot()))
	source.lobby_changed.connect(func():
		if network == source and remote_mode:
			_on_lobby_changed()
	)
	source.result_received.connect(func(result: Dictionary):
		if network != source or not remote_mode:
			return
		runner = source.runner
		players = runner.state.players
		turn_controller = runner.state
		_play_result(result)
	)
	source.connect_to_server(host, int(GameConfig.argument("--port", "19170")) if port < 0 else port)

func _sync_network() -> void:
	if not remote_mode or network == null:
		return
	var replaced: bool = runner != network.runner
	var previous_turn: int = turn_controller.turn_id
	runner = network.runner
	rules = runner.rules
	_sync_rule_controls()
	if replaced:
		voxel_world.set_world(runner.world, runner.materials)
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

	_on_lobby_changed()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready():
		scoreboard.hide()
		if not remote_mode and session != null and session.playback == null and not menu_open:
			match_panels.pause_panel.show()
			_refresh_menu_state()
		_cancel_aim()
		mouse_look_enabled = false
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _select_weapon(id: int) -> void:
	if projectile_in_flight or not _can_control() or not runner.weapons.has(id):
		return
	var player = turn_controller.get_active_player()
	if player == null:
		return
	weapon_by_player[player.player_id] = id
	selection_player = player.player_id
	selected_weapon_id = id
	_cancel_aim()

func _sync_selected_weapon() -> void:
	var player = turn_controller.get_active_player()
	if player != null and selection_player != player.player_id:
		selection_player = player.player_id
		selected_weapon_id = weapon_by_player.get(selection_player, 1)
		_cancel_aim()

func _setup_client_panels() -> void:
	lobby_panel = preload("res://scripts/client/ui/lobby_panel.gd").new()
	$Hud.add_child(lobby_panel)
	lobby_panel.close_requested.connect(_close_overlays)
	lobby_panel.retry_requested.connect(func():
		if remote_mode and network != null: network.retry_connection())
	lobby_panel.disconnect_requested.connect(_disconnect_to_local)
	lobby_panel.ready_requested.connect(func(value: bool):
		if remote_mode and network != null: network.set_ready(value)
	)
	lobby_panel.name_requested.connect(func(value: String):
		if remote_mode and network != null: network.set_display_name(value)
	)
	lobby_panel.rematch_requested.connect(func(value: bool):
		if remote_mode and network != null: network.vote_rematch(value)
	)
	settings_panel = preload("res://scripts/client/ui/settings_panel.gd").new()
	$Hud.add_child(settings_panel)
	settings_panel.setup(preferences, bindings)
	settings_panel.closed.connect(_toggle_settings)
	settings_panel.preferences_changed.connect(_apply_client_preferences)
	match_panels = preload("res://scripts/client/ui/match_panels.gd").new()
	$Hud.add_child(match_panels)
	match_panels.resume_requested.connect(_close_overlays)
	match_panels.close_requested.connect(_close_overlays)
	match_panels.setup_requested.connect(func(_map_name: String, _count: int, _preset: String):
		if workflows != null: workflows.request("new_match",match_panels.current_configuration())
	)
	match_panels.restart_requested.connect(request_restart)
	match_panels.surrender_requested.connect(func():
		if remote_mode: _surrender()
		elif workflows != null: workflows.request("surrender"))
	match_panels.save_requested.connect(func(): _save_session())
	match_panels.load_requested.connect(func(): _load_session())
	match_panels.export_requested.connect(func(): _save_replay())
	match_panels.replay_requested.connect(func(): _open_replay())
	match_panels.step_requested.connect(_step_replay)
	match_panels.rewind_requested.connect(_rewind_replay)
	match_panels.return_requested.connect(_return_from_replay)
	match_panels.library_requested.connect(_toggle_library)
	match_panels.play_requested.connect(_toggle_replay_playing)
	match_panels.speed_requested.connect(func(value):
		if session.playback != null: session.playback.set_speed(value)
	)
	match_panels.seek_requested.connect(_seek_replay_time)
	match_panels.next_shot_requested.connect(_next_replay_shot)
	match_panels.scrub_requested.connect(_scrub_replay)
	library_panel = preload("res://scripts/client/ui/library_panel.gd").new()
	$Hud.add_child(library_panel)
	library_panel.close_requested.connect(_close_overlays)
	library_panel.refresh_requested.connect(_refresh_library)
	library_panel.save_requested.connect(_library_save)
	library_panel.load_requested.connect(_library_load)
	library_panel.rename_requested.connect(_library_rename)
	library_panel.delete_requested.connect(_library_delete)
	library_panel.import_requested.connect(_library_import)
	turn_banner = Label.new()
	turn_banner.position = Vector2(30, 160)
	turn_banner.add_theme_color_override("font_color", Color(1,0.9,0.4))
	$Hud.add_child(turn_banner)
	last_shot_label = Label.new()
	last_shot_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	last_shot_label.offset_left = 70
	last_shot_label.offset_top = -35
	$Hud.add_child(last_shot_label)
	scoreboard = Label.new()
	scoreboard.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	scoreboard.offset_left = -560
	scoreboard.offset_right = -20
	scoreboard.offset_top = 210
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.025, 0.04, 0.08, 0.94)
	background.content_margin_left = 12
	background.content_margin_right = 12
	background.content_margin_top = 10
	background.content_margin_bottom = 10
	scoreboard.add_theme_stylebox_override("normal", background)
	scoreboard.add_theme_color_override("font_shadow_color", Color.BLACK)
	scoreboard.add_theme_constant_override("shadow_offset_x", 2)
	scoreboard.add_theme_constant_override("shadow_offset_y", 2)
	$Hud.add_child(scoreboard)
	scoreboard.hide()
	debug_panel = Label.new()
	debug_panel.position = Vector2(30, 300)
	$Hud.add_child(debug_panel)
	debug_panel.hide()
	aim_indicator = MeshInstance3D.new()
	aim_indicator.name = "AimDirection"
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	aim_indicator.material_override = material
	add_child(aim_indicator)
	aim_indicator.hide()

func _toggle_settings() -> void:
	var open: bool = not settings_panel.visible
	_close_overlays()
	settings_panel.visible = open
	_refresh_menu_state()

func _update_scoreboard() -> void:
	var rows := PackedStringArray(["SCOREBOARD — Shots / Hits / Damage / Kills"])
	for player in players:
		var stats: Dictionary = runner.statistics.get(player.player_id, {})
		rows.append("%s%s | HP %d | %d / %d / %d / %d%s" % [player.display_name, " ACTIVE" if player == turn_controller.get_active_player() else "", player.health, stats.get("shots",0), stats.get("hits",0), stats.get("damage",0), stats.get("kills",0), " OUT" if not player.is_alive else ""])
	scoreboard.text = "\n".join(rows)

func _update_debug_panel() -> void:
	if remote_mode:
		debug_panel.hide()
	if not debug_panel.visible:
		return
	var weapon: Resource = runner.weapons[selected_weapon_id]
	debug_panel.text = "LOCAL DEBUG — F1 | [ / ] gravity\nGravity %.1f × %.2f | %s\nBlast %.1f / terrain %d / player %d\nTurn %d | dirty %d / rebuilt %d / meshes %d" % [rules.base_gravity, weapon.gravity_scale, weapon.code, weapon.explosion_radius, weapon.terrain_damage, weapon.player_damage, turn_controller.turn_id, voxel_world.last_dirty_chunk_count, voxel_world.last_rebuilt_chunk_count, voxel_world.total_mesh_count]

func _adjust_debug_gravity(amount: float) -> void:
	if remote_mode or not debug_panel.visible or projectile_in_flight or session.playback != null:
		return
	rules.base_gravity = clampf(rules.base_gravity + amount, 1.0, 100.0)
	session.new_recording() # Debug rule edits begin a new reproducible recording.
	_cancel_aim()
	_update_debug_panel()

func _sync_rule_controls() -> void:
	move_speed = rules.move_speed
	jump_speed = rules.jump_speed
	player_gravity = rules.player_gravity
	min_shot_power = rules.min_shot_power
	max_shot_power = rules.max_shot_power
	max_charge_time = rules.max_charge_time

func _refresh_menu_state() -> void:
	menu_open = (workflows != null and workflows.overlays_open()) or library_panel.visible or lobby_panel.visible or settings_panel.visible or match_panels.any_open() or (backend_menu != null and backend_menu.panel.visible)
	local_paused = menu_open and not remote_mode
	if workflows != null: workflows.refresh_visibility()
	if menu_open:
		turn_banner.hide()
	if is_instance_valid(active_projectile):
		active_projectile.set_physics_process(not local_paused)
	_cancel_aim()
	mouse_look_enabled = not menu_open
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if menu_open else Input.MOUSE_MODE_CAPTURED)

func _close_overlays() -> void:
	if workflows != null: workflows.close_overlays()
	if session.playback != null: session.playback.set_playing(false)
	library_panel.hide()
	lobby_panel.hide()
	settings_panel.hide()
	match_panels.hide_panels()
	if workflows != null and workflows.handoff: match_panels.handoff_panel.show()
	if backend_menu != null:
		backend_menu.toggle(false)
	_refresh_menu_state()

func _toggle_pause() -> void:
	if session.playback != null:
		_close_overlays()
		match_panels.replay_panel.show()
		_refresh_menu_state()
		return
	var open: bool = not match_panels.pause_panel.visible
	_close_overlays()
	match_panels.pause_panel.visible = open
	_refresh_menu_state()

func _toggle_setup() -> void:
	if remote_mode or session.playback != null:
		return
	var open: bool = not match_panels.setup_panel.visible
	_close_overlays()
	match_panels.setup_panel.visible = open
	_refresh_menu_state()

func _toggle_help() -> void:
	var open: bool = not match_panels.help_panel.visible
	_close_overlays()
	match_panels.help_panel.visible = open
	_refresh_menu_state()

func start_local_match(map_name: String, count: int, preset: String, mode := "hotseat", difficulty := "normal", human_team: int = 1) -> bool:
	if human_team not in [1,2]: return false
	if workflows != null and workflows.training.active: return false
	if mode not in ["hotseat", "solo"] or difficulty not in ["easy", "normal"] or session.playback != null:
		return false
	if remote_mode or not GameConfig.MAPS.has(map_name) or count < 2 or count > 10 or preset not in ["classic", "quick", "training"]:
		return false
	var replacement = MatchFactory.create_match(count, GameConfig.MAPS[map_name], preset)
	if replacement == null:
		return false
	if is_instance_valid(active_projectile):
		active_projectile.queue_free()
	active_projectile = null
	projectile_in_flight = false
	pending_result = {}
	end_presented_key = ""
	effects.clear()
	runner = replacement
	session.options = {"mode": mode, "difficulty": difficulty, "human_team": human_team}
	session.new_recording()
	rules = runner.rules
	_sync_rule_controls()
	weapon_by_player.clear()
	selection_player = ""
	selected_weapon_id = 1
	observed_turn = -1
	observed_generation = -1
	camera_transition_initialized = false
	voxel_world.set_world(runner.world, runner.materials)
	_bind_players()
	_close_overlays()
	last_shot_label.text = ""
	_update_hud()
	if workflows != null: workflows.on_started()
	return true

func _surrender() -> void:
	if session.playback != null or session.is_bot_turn():
		return
	if projectile_in_flight or runner.state.status != "playing":
		return
	if remote_mode:
		if network != null and network.ready_for_match:
			network.surrender()
	else:
		var player = turn_controller.get_active_player()
		if player != null:
			var result: Dictionary = session.recorder.surrender(runner, player.player_id)
			if result.ok:
				_update_player_nodes()
	_close_overlays()
	_update_match_panels(0.0)

func _show_turn_banner() -> void:
	if projectile_in_flight or runner.state.status != "playing":
		return
	var active = turn_controller.get_active_player()
	if active == null:
		return
	turn_banner.text = "Turn %d — %s / Team %d" % [turn_controller.turn_id + 1, active.display_name, active.team_id]
	turn_banner_count += 1
	banner_remaining = 2.5
	turn_banner.show()

func _update_match_panels(delta: float) -> void:
	banner_remaining = maxf(0.0, banner_remaining - delta)
	turn_banner.visible = banner_remaining > 0 and not menu_open and not projectile_in_flight
	if not projectile_in_flight and not runner.history.is_empty():
		var shot: Dictionary = runner.history.back()
		last_shot_label.text = "Last shot: %s | weapon %d | damage %d | destroyed voxels %d" % [shot.player_id, shot.weapon_id, shot.damage, shot.terrain_destroyed]
	elif runner.history.is_empty():
		last_shot_label.text = ""
	if runner.state.status == "playing":
		end_presented_key = ""
	if runner.state.status == "ended" and not projectile_in_flight and session.playback == null:
		var key := "%d/%d/%d" % [runner.state.generation, runner.state.revision, runner.state.winner_team]
		if end_presented_key != key:
			end_presented_key = key
			_close_overlays()
			match_panels.end_panel.show()
			_refresh_menu_state()
		_update_scoreboard()
		match_panels.end_label.text = _winner_status_text() + "\n" + scoreboard.text
		if _uses_ready_lobby():
			var own: Dictionary = _own_lobby_slot()
			match_panels.restart_button.text = "Cancel rematch vote" if own.get("rematch",false) else "Vote rematch"
			match_panels.restart_button.disabled = not network.ready_for_match
			match_panels.end_label.text += "\n" + _rematch_status()
		else:
			match_panels.restart_button.text = "Restart"
			match_panels.restart_button.disabled = remote_mode and (network == null or network.player_id != "blue_1")

func _apply_client_preferences() -> void:
	if effects != null: effects.configure_preferences(preferences)
	var text_size := roundi(20 * preferences.hud_scale)
	hud_label.add_theme_font_size_override("font_size", text_size)
	scoreboard.add_theme_font_size_override("font_size", roundi(15 * preferences.hud_scale))
	turn_banner.add_theme_font_size_override("font_size", text_size)
	last_shot_label.add_theme_font_size_override("font_size", roundi(16 * preferences.hud_scale))
	match_panels.update_bindings(bindings)
	for panel in [settings_panel, match_panels, lobby_panel, library_panel]:
		_scale_panel(panel, roundi(16 * preferences.hud_scale))
	if workflows != null:
		_scale_panel(workflows.training_panel,roundi(16 * preferences.hud_scale))
		_scale_panel(workflows.confirmation,roundi(16 * preferences.hud_scale))
	var contrast: bool = preferences.high_contrast
	if not $Hud/Crosshair.has_node("OutlineHorizontal"):
		for data in [["OutlineHorizontal", Vector2(2,15), Vector2(32,6)], ["OutlineVertical", Vector2(15,2), Vector2(6,32)]]:
			var outline := ColorRect.new()
			outline.name = data[0]
			outline.position = data[1]
			outline.size = data[2]
			outline.color = Color.BLACK
			outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
			$Hud/Crosshair.add_child(outline)
			$Hud/Crosshair.move_child(outline, 0)
	$Hud/Crosshair/OutlineHorizontal.visible = contrast
	$Hud/Crosshair/OutlineVertical.visible = contrast
	for part in [$Hud/Crosshair/Horizontal, $Hud/Crosshair/Vertical]:
		part.color = Color(1.0, 0.95, 0.1, 1) if contrast else Color(1,1,1,0.9)

func _scale_panel(node: Node, size: int) -> void:
	if node is Control:
		node.add_theme_font_size_override("font_size", size)
	for child in node.get_children():
		_scale_panel(child, size)

func _session_message(message: String) -> void:
	match_panels.session_status.text = message

func _save_session(path := "user://last_session.json") -> bool:
	if not session.can_archive():
		_session_message("Save is available in a local match between shots.")
		return false
	var error: Error = preload("res://scripts/core/replay/session_store.gd").save(path, runner, session.options, player_velocities)
	_session_message("Game saved: " + path if error == OK else "Save failed: " + error_string(error))
	return error == OK

func _load_session(path := "user://last_session.json") -> bool:
	if not session.can_archive():
		_session_message("Load is available in a local match between shots.")
		return false
	var loaded: Dictionary = preload("res://scripts/core/replay/session_store.gd").load(path)
	if not loaded.ok:
		_session_message("Load failed: " + loaded.reason)
		return false
	session.options = loaded.options
	_replace_local_runner(loaded.runner)
	player_velocities = loaded.velocities
	session.new_recording()
	_close_overlays()
	return true

func _save_replay(path := "user://last_replay.json") -> bool:
	if not session.can_archive():
		_session_message("Export is available in a local match between shots.")
		return false
	var error: Error = preload("res://scripts/core/replay/replay_archive.gd").save(path, session.recorder, runner)
	_session_message("Replay saved: " + path if error == OK else "Export failed: " + error_string(error) + " " + session.recorder.recording_error)
	return error == OK

func _open_replay(path := "user://last_replay.json") -> bool:
	if not session.can_archive():
		_session_message("Replay inspection is available locally between shots.")
		return false
	var loaded: Dictionary = preload("res://scripts/core/replay/replay_archive.gd").load_verified(path)
	if not loaded.ok:
		_session_message("Replay failed: " + loaded.reason)
		return false
	return _inspect_recording(loaded.recorder)

func _inspect_recording(recorder: RefCounted) -> bool:
	var playback = preload("res://scripts/core/replay/replay_playback.gd").new()
	if not playback.load_recording(recorder):
		_session_message("Replay could not be initialized.")
		return false
	session.live_runner = runner
	session.live_velocities = player_velocities.duplicate()
	session.playback = playback
	session.bot = null
	_replace_local_runner(playback.runner)
	_close_overlays()
	match_panels.replay_panel.show()
	match_panels.replay_speed.select(2)
	_refresh_menu_state()
	_update_replay_status()
	if archive_ui != null: archive_ui.on_opened()
	return true

func _step_replay() -> void:
	if session.playback == null or session.playback.finished:
		return
	session.playback.set_playing(false)
	var result: Dictionary = session.playback.step()
	if not result.ok:
		match_panels.replay_status.text = "Invalid replay action"
		return
	# Inspector displays the authoritative result immediately, without advancing live time.
	if result.has("result"):
		voxel_world.refresh_deltas(result.result.get("deltas", []))
	_update_player_nodes()
	_update_hud()
	_update_scoreboard()
	_update_replay_status()

func _rewind_replay() -> void:
	if session.playback != null and session.playback.seek(0):
		_replace_local_runner(session.playback.runner)
		_update_replay_status()

func _update_replay_status() -> void:
	var playback = session.playback
	match_panels.replay_status.text = "Action %d / %d — %.2f / %.2f s%s" % [playback.index, playback.action_count, playback.elapsed_time, playback.duration, " — Finished" if playback.finished else ""]
	match_panels.play_button.text = "Pause" if playback.playing else "Play"
	match_panels.play_button.disabled = playback.finished
	match_panels.replay_seek.max_value = maxf(0.01,playback.duration)
	if not match_panels.replay_dragging:
		match_panels.replay_seek.set_value_no_signal(playback.elapsed_time)

func _return_from_replay() -> void:
	if session.playback == null:
		return
	if archive_ui != null: archive_ui.closing_replay()
	var live: RefCounted = session.live_runner
	session.playback = null
	session.live_runner = null
	_replace_local_runner(live)
	player_velocities = session.live_velocities
	session.live_velocities = {}
	_close_overlays()

func _replace_local_runner(replacement: RefCounted) -> void:
	_cancel_aim()
	if is_instance_valid(active_projectile):
		active_projectile.queue_free()
	active_projectile = null
	projectile_in_flight = false
	pending_result = {}
	effects.clear()
	session.bot = null
	runner = replacement
	rules = runner.rules
	_sync_rule_controls()
	weapon_by_player.clear()
	selection_player = ""
	selected_weapon_id = 1
	observed_turn = -1
	observed_generation = -1
	end_presented_key = ""
	camera_transition_initialized = false
	voxel_world.set_world(runner.world, runner.materials)
	_bind_players()
	_update_hud()
	_update_scoreboard()

func _begin_network_connection(host: String, port: int) -> void:
	if (workflows != null and workflows.training.active) or session.playback != null or port < 1 or port > 65535 or host.strip_edges().is_empty():
		return
	var previous = network
	network = null
	if is_instance_valid(previous):
		previous.set_process(false)
		previous.leave()
		previous.queue_free()
	if is_instance_valid(active_projectile):
		active_projectile.queue_free()
	active_projectile = null
	projectile_in_flight = false
	pending_result = {}
	effects.clear()
	session.bot = null
	shown_lobby_generation = -1
	last_lobby_started = false
	remote_mode = true
	_close_overlays()
	_connect_network(host.strip_edges(), port)

func _disconnect_to_local() -> void:
	var previous = network
	network = null
	remote_mode = false
	if is_instance_valid(previous):
		previous.set_process(false)
		previous.leave()
		previous.queue_free()
	network_status = ""
	lobby_panel.feedback.text = ""
	shown_lobby_generation = -1
	last_lobby_started = false
	session.playback = null
	session.live_runner = null
	session.live_velocities = {}
	session.options = {"mode":"hotseat","difficulty":"normal","human_team":1}
	_replace_local_runner(MatchFactory.create_match(10))
	session.new_recording()
	_close_overlays()

func _uses_ready_lobby() -> bool:
	return remote_mode and network != null and network.lobby_state.get("require_ready",false)

func _own_lobby_slot() -> Dictionary:
	if network != null:
		for row in network.lobby_state.get("roster",[]):
			if row.id == network.player_id:
				return row
	return {}

func _rematch_status() -> String:
	var votes := 0
	for row in network.lobby_state.get("roster",[]):
		votes += int(row.rematch)
	return "Rematch votes: %d / %d — full connected roster required" % [votes,network.lobby_state.get("capacity",0)]

func _vote_rematch() -> void:
	if _uses_ready_lobby() and network.ready_for_match and network.match_phase == "ended":
		network.vote_rematch(not _own_lobby_slot().get("rematch",false))

func _present_lobby() -> void:
	if lobby_panel != null and network != null:
		lobby_panel.present(network.lobby_state,network.player_id,network.match_phase,network.ready_for_match)

func _on_lobby_changed() -> void:
	if lobby_panel == null or network == null or not remote_mode:
		return
	_present_lobby()
	var state: Dictionary = network.lobby_state
	if state.is_empty() or not network.ready_for_match or state.generation != runner.state.generation:
		return
	var started: bool = state.started
	if not started and shown_lobby_generation != int(state.generation):
		shown_lobby_generation = int(state.generation)
		end_presented_key = ""
		_close_overlays()
		lobby_panel.show()
		_refresh_menu_state()
	elif started and not last_lobby_started and lobby_panel.visible:
		_close_overlays()
	last_lobby_started = started

func _toggle_lobby() -> void:
	if not remote_mode or network == null or session.playback != null:
		return
	var open := not lobby_panel.visible
	_close_overlays()
	_present_lobby()
	lobby_panel.visible = open
	_refresh_menu_state()

func _toggle_library() -> void:
	if remote_mode or session.playback != null or (workflows != null and workflows.training.active): return
	var opening := not library_panel.visible
	_close_overlays()
	library_panel.visible = opening
	if opening: _refresh_library()
	_refresh_menu_state()

func _refresh_library() -> void:
	if archive_ui != null:
		archive_ui.refresh()
		return
	library_panel.present(library.list_entries(library_panel.selected_kind()))

func _library_feedback(result: Dictionary, message: String) -> void:
	if result.ok: _refresh_library()
	library_panel.status.text = message if result.ok else library_panel.error_message(str(result.get("reason","Operation failed")))

func _library_save(kind: String, title: String) -> void:
	if archive_ui != null and archive_ui.busy: return
	if not session.can_archive():
		library_panel.status.text = "Available locally between shots."
		return
	var result: Dictionary = library.save_session(title,runner,session.options,player_velocities) if kind == "session" else library.save_replay(title,session.recorder,runner)
	_library_feedback(result,"Saved: " + title)

func _library_load(id: String) -> bool:
	if archive_ui != null and archive_ui.busy: return false
	if not session.can_archive(): return false
	var result: Dictionary = library.load_entry(id)
	if not result.ok:
		_library_feedback(result,"")
		return false
	if result.kind == "replay":
		var opened := _inspect_recording(result.recorder)
		if opened and archive_ui != null: archive_ui.opened_entry(id)
		return opened
	session.options = result.options
	_replace_local_runner(result.runner)
	player_velocities = result.velocities
	session.new_recording()
	_close_overlays()
	return true

func _library_rename(id: String, title: String) -> void:
	if archive_ui != null and archive_ui.busy: return
	if not session.can_archive(): return
	_library_feedback(library.rename_entry(id,title),"Renamed: " + title)

func _library_delete(id: String) -> void:
	if archive_ui != null and archive_ui.busy: return
	if not session.can_archive(): return
	_library_feedback(library.delete_entry(id),"Entry deleted.")

func _library_import(kind: String, title: String) -> void:
	if archive_ui != null and archive_ui.busy: return
	if not session.can_archive(): return
	var path := "user://last_session.json" if kind == "session" else "user://last_replay.json"
	_library_feedback(library.import_file(kind,path,title),"Imported: " + title)

func _toggle_replay_playing() -> void:
	if session.playback == null: return
	session.playback.set_playing(not session.playback.playing)
	_update_replay_status()

func _advance_replay(delta: float) -> void:
	if session == null or session.playback == null: return
	if not match_panels.replay_panel.visible:
		session.playback.set_playing(false)
		return
	if not session.playback.playing: return
	var result: Dictionary = session.playback.advance(delta)
	if not result.ok:
		match_panels.replay_status.text = str(result.get("reason","Playback failed"))
		return
	for action in result.results:
		if action.has("result"): voxel_world.refresh_deltas(action.result.get("deltas",[]))
	if archive_ui != null: archive_ui.on_playback_advanced(result.changed)
	if result.changed:
		_update_player_nodes()
		_update_scoreboard()
	_update_replay_status()

func _seek_replay_time(value: float) -> void:
	if session.playback == null: return
	if session.playback.seek_time(value):
		_replace_local_runner(session.playback.runner)
		_update_replay_status()
	else:
		match_panels.replay_status.text = "Seek failed: " + session.playback.last_error

func _next_replay_shot() -> void:
	if session.playback != null and session.playback.next_shot():
		_replace_local_runner(session.playback.runner)
		_update_replay_status()

func _scrub_replay(direction: int) -> void:
	if session.playback == null: return
	var target := clampi(session.playback.index + direction,0,session.playback.action_count)
	if session.playback.seek(target):
		_replace_local_runner(session.playback.runner)
		_update_replay_status()

func request_restart() -> void:
	if workflows != null: workflows.request("restart")
	else: restart_match()

func _toggle_aim_intent(pressed: bool) -> void:
	if preferences.aim_mode == "toggle":
		if not pressed: return
		if is_aiming:
			_cancel_aim()
			return
	is_aiming = pressed and _can_control() and not projectile_in_flight and not turn_controller.has_winner()
	if is_aiming:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		mouse_look_enabled = true
		if workflows != null: workflows.training.observe_intent("aim")
	else: _cancel_aim()

func _charge_click_intent(pressed: bool) -> void:
	if preferences.charge_mode == "click":
		if pressed:
			if is_charging_shot: _release_charged_shot()
			else: _start_charging_shot()
	elif pressed: _start_charging_shot()
	else: _release_charged_shot()
