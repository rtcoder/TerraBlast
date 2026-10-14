class_name ProjectileSimulation
extends RefCounted

const MAX_SWEEP_SAMPLES := 65536

static func simulate(world: RefCounted, origin: Vector3, direction: Vector3, power: float, weapon: Resource, rules: Resource, materials: Dictionary = {}) -> Dictionary:
	var result := {"path": PackedVector3Array([origin]), "position": origin, "hit": false, "reason": "invalid", "deltas": []}
	if not origin.is_finite() or not direction.is_finite() or direction.length_squared() < 0.001 or not is_finite(power) or not rules.validate() or not weapon.validate():
		return result
	var ratio := inverse_lerp(rules.min_shot_power, rules.max_shot_power, clampf(power, rules.min_shot_power, rules.max_shot_power))
	var velocity := direction.normalized() * lerpf(weapon.min_projectile_speed, weapon.projectile_speed, ratio)
	var position := origin
	var removed := {}
	var samples := 0
	var dt: float = rules.projectile_step
	var duration: float = weapon.fuse_time if weapon.behavior == "grenade" else rules.max_projectile_lifetime
	for tick in range(ceili(duration / dt)):
		var step_dt := minf(dt, duration - tick * dt)
		velocity += Vector3.DOWN * rules.base_gravity * weapon.gravity_scale * step_dt
		var next := position + velocity * step_dt
		var distance := position.distance_to(next)
		var steps := maxi(1, ceili(distance / rules.sweep_step))
		if samples + steps > MAX_SWEEP_SAMPLES:
			result.reason = "simulation_budget"
			return result
		samples += steps
		var previous := position
		var collided := false
		for step in range(1, steps + 1):
			var point := position.lerp(next, float(step) / steps)
			var voxel := Vector3i(floori(point.x), floori(point.y), floori(point.z))
			var material_id: int = world.get_material_id(voxel)
			if material_id != 0 and not removed.has(voxel):
				var destructible: bool = materials[material_id].is_destructible if materials.has(material_id) else material_id != 3
				if weapon.behavior == "drill" and removed.size() < weapon.drill_voxels and destructible:
					removed[voxel] = true
					result.deltas.append({"position": [voxel.x, voxel.y, voxel.z], "material_id": 0, "health": 0})
				elif weapon.behavior == "grenade":
					var previous_voxel := Vector3i(floori(previous.x), floori(previous.y), floori(previous.z))
					var normal := Vector3(previous_voxel - voxel).normalized()
					if normal == Vector3.ZERO:
						normal = -velocity.normalized()
					velocity = velocity.bounce(normal) * weapon.bounce
					next = previous
					collided = true
					break
				else:
					result.path.append(point)
					result.position = point
					result.hit = true
					result.reason = "impact"
					return result
			previous = point
		position = next
		result.path.append(position)
		result.position = position
		if position.x < 0 or position.z < 0 or position.x >= world.size.x or position.z >= world.size.z or position.y < -8:
			result.reason = "miss"
			return result
		if collided and velocity.length_squared() < 0.01:
			velocity = Vector3.ZERO
	result.hit = weapon.behavior == "grenade"
	result.reason = "fuse" if result.hit else "miss"
	return result
