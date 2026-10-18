class_name WeaponCatalog
extends RefCounted
const Weapon = preload("res://scripts/core/weapons/weapon_config.gd")
const LOADOUTS := {"classic":["bazooka","grenade","drill_missile"],"artillery":["artillery_bazooka","artillery_grenade","artillery_drill"]}
static func validate_configs(configs: Array) -> Array[String]:
	var errors: Array[String] = []
	var ids := {}
	var codes := {}
	if configs.is_empty(): errors.append("Weapon catalog is empty")
	for i in range(configs.size()):
		var weapon: Variant = configs[i]
		if not weapon is Weapon:
			errors.append("Weapon %d has invalid type" % i)
			continue
		if not weapon.validate(): errors.append("Weapon %d has invalid config" % i)
		if ids.has(weapon.id) or codes.has(weapon.code): errors.append("Weapon %d duplicates ID/code" % i)
		ids[weapon.id] = true
		codes[weapon.code] = true
	return errors
static func from_configs(configs: Array) -> Dictionary:
	if not validate_configs(configs).is_empty(): return {}
	var result := {}
	for weapon in configs: result[weapon.id] = weapon.duplicate()
	return result
static func load_all() -> Dictionary:
	return load_loadout("classic")
static func load_loadout(id: String = "classic") -> Dictionary:
	if not LOADOUTS.has(id): return {}
	var configs := []
	for code in LOADOUTS[id]: configs.append(load("res://assets/config/weapons/%s.tres" % code))
	return from_configs(configs)
static func describe(config: Resource) -> Dictionary:
	if not config is Weapon or not config.validate(): return {}
	return {"id":config.id,"code":config.code,"name":config.display_name,"speed_min":config.min_projectile_speed,"speed_max":config.projectile_speed,"ammo":config.max_uses_per_match,"behavior":config.behavior,"terrain_radius":config.explosion_radius,"player_radius":config.player_damage_radius,"damage_samples":[config.damage_at_distance(0),config.damage_at_distance(config.player_damage_radius/2.0),config.damage_at_distance(config.player_damage_radius)]}
