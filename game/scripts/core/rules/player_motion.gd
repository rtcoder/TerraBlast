class_name PlayerMotion
extends RefCounted

const RADIUS := 0.3
const HEIGHT := 1.8

static func surface(world: RefCounted, x: int, z: int) -> float:
	for y in range(world.size.y - 1, -1, -1):
		if world.get_material_id(Vector3i(x, y, z)) != 0:
			return float(y + 1)
	return -8.0

static func blocked(world: RefCounted, position: Vector3) -> bool:
	for x in range(floori(position.x - RADIUS), floori(position.x + RADIUS - 0.001) + 1):
		for y in range(floori(position.y + 0.001), floori(position.y + HEIGHT - 0.001) + 1):
			for z in range(floori(position.z - RADIUS), floori(position.z + RADIUS - 0.001) + 1):
				if world.get_material_id(Vector3i(x,y,z)) != 0:
					return true
	return false

# Sweep each axis in bounded increments; a pawn cannot tunnel through a voxel.
static func displace(world: RefCounted, player: RefCounted, velocity: Vector3, delta: float) -> Vector3:
	var steps := maxi(1, ceili(velocity.length() * delta / 0.15))
	for step in range(steps):
		for axis in [0, 2, 1]:
			var next: Vector3 = player.position
			next[axis] += velocity[axis] * delta / steps
			if axis != 1 and (next[axis] < RADIUS or next[axis] > world.size[axis] - RADIUS):
				velocity[axis] = 0
			elif blocked(world, next):
				velocity[axis] = 0
			else:
				player.position = next
	return velocity

static func move(world: RefCounted, player: RefCounted, velocity: Vector3, input: Vector2, yaw: float, jump: bool, delta: float, rules: Resource) -> Vector3:
	if not is_finite(delta) or delta <= 0 or not input.is_finite() or not is_finite(yaw) or not velocity.is_finite():
		return velocity
	delta = minf(delta, 0.3)
	if jump and blocked(world, player.position + Vector3.DOWN * 0.05):
		velocity.y = rules.jump_speed
	player.rotation = Basis(Vector3.UP, yaw)
	var forward := Vector3(sin(yaw), 0, cos(yaw))
	var direction := forward * input.y + forward.cross(Vector3.UP) * input.x
	if direction.length_squared() > 1:
		direction = direction.normalized()
	velocity.x = direction.x * rules.move_speed
	velocity.z = direction.z * rules.move_speed
	velocity.y -= rules.player_gravity * delta
	velocity = displace(world, player, velocity, delta)
	if player.position.y < -7:
		player.apply_damage(player.health)
	return velocity
