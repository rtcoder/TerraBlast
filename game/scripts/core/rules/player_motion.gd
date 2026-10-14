class_name PlayerMotion
extends RefCounted

static func surface(world: RefCounted, x: int, z: int) -> float:
	for y in range(world.size.y - 1, -1, -1):
		if world.get_material_id(Vector3i(x, y, z)) != 0:
			return float(y + 1)
	return -8.0

static func move(world: RefCounted, player: RefCounted, velocity: Vector3, input: Vector2, yaw: float, jump: bool, delta: float, rules: Resource) -> Vector3:
	var ground := surface(world, floori(player.position.x), floori(player.position.z))
	if jump and player.position.y <= ground + 0.05:
		velocity.y = rules.jump_speed
	player.rotation = Basis(Vector3.UP, yaw)
	var forward := Vector3(sin(yaw), 0, cos(yaw))
	var direction := forward * input.y + forward.cross(Vector3.UP) * input.x
	if direction.length_squared() > 1:
		direction = direction.normalized()
	velocity.x = direction.x * rules.move_speed
	velocity.z = direction.z * rules.move_speed
	velocity.y -= rules.player_gravity * delta
	player.position += velocity * delta
	player.position.x = clampf(player.position.x, 1, world.size.x - 2)
	player.position.z = clampf(player.position.z, 1, world.size.z - 2)
	ground = surface(world, floori(player.position.x), floori(player.position.z))
	if player.position.y <= ground:
		player.position.y = ground
		velocity.y = 0
	if player.position.y < -7:
		player.apply_damage(player.health)
	return velocity
