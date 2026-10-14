class_name GameRulesConfig
extends Resource

@export var turn_time := 45.0
@export var min_shot_power := 0.25
@export var max_shot_power := 4.0
@export var base_gravity := 18.0
@export var projectile_step := 1.0 / 30.0
@export var default_explosion_radius := 5
@export var max_projectile_lifetime := 6.0
@export var sweep_step := 0.2
@export var move_speed := 8.0
@export var jump_speed := 8.5
@export var player_gravity := 22.0
@export var max_charge_time := 1.4
@export var starting_health := 100

func validate() -> bool:
	for value in [turn_time, min_shot_power, max_shot_power, base_gravity, projectile_step, max_projectile_lifetime, sweep_step, move_speed, jump_speed, player_gravity, max_charge_time]:
		if not is_finite(value) or value <= 0.0:
			return false
	return min_shot_power <= max_shot_power and is_equal_approx(projectile_step, 1.0 / 30.0) and default_explosion_radius >= 0 and starting_health > 0
