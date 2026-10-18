class_name TrajectorySolver
extends RefCounted
const Weapon = preload("res://scripts/core/weapons/weapon_config.gd")
const Rules = preload("res://scripts/core/rules/game_rules_config.gd")
const Simulation = preload("res://scripts/core/projectiles/projectile_simulation.gd")
const Analysis = preload("res://scripts/core/projectiles/trajectory_analysis.gd")
static func solve(world: RefCounted, origin: Vector3, target: Vector3, weapon: Resource, rules: Resource, materials: Dictionary = {}, max_candidates: int = 32) -> Dictionary:
	var best := {"ok":false,"reason":"no_completed_candidate","candidates":0,"direction":Vector3.ZERO,"power":0.0,"error":INF,"result":{}}
	if not origin.is_finite() or not target.is_finite() or not weapon is Weapon or not rules is Rules or not weapon.validate() or not rules.validate() or max_candidates < 1:
		best.reason = "invalid_input"
		return best
	max_candidates = mini(max_candidates,32)
	var base_yaw := atan2(target.x-origin.x,target.z-origin.z)
	for yaw_offset in [0.0,-0.12,0.12,0.24]:
		for pitch in [0.25,0.6,0.95,1.2]:
			for fraction in [0.4,0.85]:
				if best.candidates >= max_candidates: return best
				var yaw: float = base_yaw + yaw_offset
				var direction := Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))
				var power: float = lerpf(rules.min_shot_power,rules.max_shot_power,fraction)
				var shot := Simulation.simulate(world,origin,direction,power,weapon,rules,materials)
				best.candidates += 1
				if not Analysis.classify(shot).complete: continue
				var error: float = shot.position.distance_to(target)
				if error < best.error:
					best.ok = true
					best.reason = "selected"
					best.direction = direction
					best.power = power
					best.error = error
					best.result = shot
	return best
