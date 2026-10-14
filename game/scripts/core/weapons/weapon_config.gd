class_name WeaponConfig
extends Resource

@export var id: int = 0
@export var code: String = ""
@export var display_name: String = ""
@export var projectile_speed: float = 20.0
@export var gravity_scale: float = 1.0
@export var explosion_radius: int = 4
@export var terrain_damage: int = 100
@export var player_damage_radius := 5.5
@export var player_damage_falloff := 1.0
@export var player_damage: int = 30
@export var knockback: float = 8.0
@export var max_uses_per_match: int = -1


@export var min_projectile_speed := 10.0
@export_enum("impact", "grenade", "drill") var behavior := "impact"
@export var fuse_time := 2.5
@export var bounce := 0.55
@export var drill_voxels := 4

func validate() -> bool:
	for value in [projectile_speed, min_projectile_speed, gravity_scale, fuse_time, bounce, knockback, player_damage_radius, player_damage_falloff]:
		if not is_finite(value) or value < 0.0:
			return false
	return player_damage_radius > 0 and player_damage_radius <= 32 and player_damage_falloff > 0 and player_damage_falloff <= 8 and projectile_speed <= 200 and gravity_scale <= 5 and fuse_time <= 20 and explosion_radius <= 16 and terrain_damage <= 10000 and player_damage <= 10000 and knockback <= 30 and drill_voxels <= 64 and max_uses_per_match <= 1000 and id > 0 and not code.is_empty() and projectile_speed > 0.0 and min_projectile_speed <= projectile_speed and explosion_radius >= 0 and terrain_damage >= 0 and player_damage >= 0 and max_uses_per_match >= -1 and behavior in ["impact", "grenade", "drill"] and fuse_time > 0 and bounce <= 1.0 and drill_voxels >= 0

func damage_at_distance(distance: float) -> int:
	return roundi(player_damage * pow(clampf(1.0 - distance / player_damage_radius, 0.0, 1.0), player_damage_falloff))
