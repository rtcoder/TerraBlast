extends Node3D

const DebugProjectile := preload("res://scripts/client/debug/debug_projectile.gd")
const PlayerActionCommand := preload("res://scripts/core/turns/player_action_command.gd")
const PlayerState := preload("res://scripts/core/rules/player_state.gd")
const TurnController := preload("res://scripts/core/turns/turn_controller.gd")

@onready var voxel_world: Node3D = $VoxelWorld
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var camera_pivot: Node3D = $CameraPivot
@onready var hud_label: Label = $Hud/StatusLabel
@onready var power_bar: ProgressBar = $Hud/PowerBar

var orbit_yaw := -0.7
var camera_pitch := -0.32
var camera_distance := 11.0
var camera_height := 3.4
var camera_side_offset := 0.8
var move_speed := 8.0
var jump_speed := 8.5
var player_gravity := 22.0
var player_velocities: Dictionary = {}
var player_walk_phases: Dictionary = {}
var players: Array = []
var player_nodes: Dictionary = {}
var turn_controller: RefCounted
var projectile_in_flight := false
var is_charging_shot := false
var mouse_look_enabled := true
var shot_charge := 0.0
var min_shot_power := 0.25
var max_shot_power := 4.0
var max_charge_time := 1.4
var min_projectile_speed := 10.0
var max_projectile_speed := 88.0

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_setup_players()
	_update_camera_transform()
	_update_power_bar()
	_update_hud()

func _physics_process(delta: float) -> void:
	_update_shot_charge(delta)
	_update_active_player_movement(delta)
	_update_player_nodes()
	_update_camera_transform()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
					Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
				mouse_look_enabled = true
				_start_charging_shot()
			else:
				_release_charged_shot()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = maxf(6.0, camera_distance - 1.0)
			_update_camera_transform()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = minf(18.0, camera_distance + 1.0)
			_update_camera_transform()

	if event is InputEventMouseMotion and mouse_look_enabled:
		orbit_yaw -= event.relative.x * 0.006
		camera_pitch = clampf(camera_pitch - event.relative.y * 0.004, -0.62, 0.08)
		_update_camera_transform()

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_try_jump_active_player()
		elif event.keycode == KEY_ESCAPE:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			mouse_look_enabled = false

func _start_charging_shot() -> void:
	if projectile_in_flight or turn_controller.has_winner():
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
	if projectile_in_flight or turn_controller.has_winner():
		return

	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	if direction.length_squared() <= 0.001:
		return

	var active_player: Variant = turn_controller.get_active_player()
	var command: RefCounted = PlayerActionCommand.new()
	command.player_id = active_player.player_id
	command.turn_id = turn_controller.turn_id
	command.weapon_id = 1
	command.aim_direction = direction.normalized()
	command.shot_power = shot_power
	var validation: Dictionary = turn_controller.validate_action(command)
	if not validation.ok:
		return

	_spawn_projectile(active_player.position + Vector3.UP * 1.3, command.aim_direction, command.shot_power)

func _spawn_projectile(from_position: Vector3, aim_direction: Vector3, shot_power: float = 1.0) -> void:
	projectile_in_flight = true
	var projectile: Node3D = DebugProjectile.new()
	add_child(projectile)
	projectile.global_position = from_position

	var charge_ratio := inverse_lerp(min_shot_power, max_shot_power, clampf(shot_power, min_shot_power, max_shot_power))
	var speed := lerpf(min_projectile_speed, max_projectile_speed, charge_ratio)
	var initial_velocity := aim_direction.normalized() * speed
	projectile.launch(initial_velocity, voxel_world)
	projectile.exploded.connect(_on_projectile_exploded)

func _on_projectile_exploded(voxel_position: Vector3i) -> void:
	_resolve_explosion(voxel_position, true)

func _resolve_explosion(voxel_position: Vector3i, should_advance_turn: bool) -> void:
	voxel_world.apply_debug_explosion(voxel_position, 5, 150)
	_apply_player_damage(Vector3(voxel_position) + Vector3(0.5, 0.5, 0.5), 5.5, 42)
	_update_player_nodes()
	projectile_in_flight = false
	if should_advance_turn and not turn_controller.has_winner():
		turn_controller.complete_turn()
		_face_camera_toward_enemy()
	shot_charge = 0.0
	is_charging_shot = false
	_update_power_bar()
	_update_hud()
	_update_camera_transform()

func _apply_player_damage(center: Vector3, radius: float, max_damage: int) -> void:
	for player: Variant in players:
		if not player.is_alive:
			continue
		var distance: float = player.position.distance_to(center)
		if distance > radius:
			continue
		var factor: float = 1.0 - (distance / radius)
		player.apply_damage(int(round(float(max_damage) * factor)))

func _setup_players() -> void:
	players = [
		_create_player("p1", "Blue", Vector2i(10, 10), Color(0.15, 0.36, 1.0)),
		_create_player("p2", "Red", Vector2i(37, 37), Color(1.0, 0.18, 0.12)),
	]
	turn_controller = TurnController.new(players)
	_face_camera_toward_enemy()
	_update_player_nodes()

func _create_player(player_id: String, display_name: String, spawn_xz: Vector2i, color: Color) -> RefCounted:
	var player: RefCounted = PlayerState.new()
	player.player_id = player_id
	player.display_name = display_name
	player.position = voxel_world.get_surface_world_position(spawn_xz.x, spawn_xz.y)
	player.health = 100
	player.is_alive = true
	player_velocities[player_id] = Vector3.ZERO
	player_walk_phases[player_id] = 0.0

	var marker := _create_player_marker(color)
	add_child(marker)
	player_nodes[player_id] = marker
	return player

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
		var living: Array = turn_controller.get_living_players()
		status = "Winner: %s" % living[0].display_name if living.size() == 1 else "Draw"
	elif active_player != null:
		status = "Turn %d: %s" % [turn_controller.turn_id + 1, active_player.display_name]
	status += "\nBlue %d   Red %d" % [players[0].health, players[1].health]
	status += "\nHold LMB charge   Release fire   WASD/Arrows move"
	hud_label.text = status

func _update_active_player_movement(delta: float) -> void:
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
		if player.player_id != active_player.player_id and player.is_alive:
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
	var forward := Vector3(sin(orbit_yaw), 0.0, cos(orbit_yaw)).normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var camera_position: Vector3 = target - forward * camera_distance + right * camera_side_offset
	camera_position.y += sin(-camera_pitch) * camera_distance

	camera_pivot.position = target
	camera_pivot.rotation = Vector3.ZERO
	camera.global_position = camera_position
	camera.look_at(target + forward * 8.0 + Vector3.UP * camera_pitch * 8.0, Vector3.UP)
