class_name WeaponConfig
extends Resource

@export var id: int = 0
@export var code: String = ""
@export var display_name: String = ""
@export var projectile_speed: float = 20.0
@export var gravity_scale: float = 1.0
@export var explosion_radius: int = 4
@export var terrain_damage: int = 100
@export var player_damage: int = 30
@export var knockback: float = 8.0
@export var max_uses_per_match: int = -1


@export var min_projectile_speed := 10.0
@export_enum("impact", "grenade", "drill") var behavior := "impact"
@export var fuse_time := 2.5
@export var bounce := 0.55
@export var drill_voxels := 4

func validate() -> bool:
	for value in [projectile_speed, min_projectile_speed, gravity_scale, fuse_time, bounce, knockback]:
		if not is_finite(value) or value < 0.0:
			return false
	return id > 0 and not code.is_empty() and projectile_speed > 0.0 and min_projectile_speed <= projectile_speed and explosion_radius >= 0 and terrain_damage >= 0 and player_damage >= 0 and max_uses_per_match >= -1 and behavior in ["impact", "grenade", "drill"] and fuse_time > 0 and bounce <= 1.0 and drill_voxels >= 0
