class_name WeaponCatalog
extends RefCounted

static func from_configs(configs: Array) -> Dictionary:
	var result := {}
	var codes := {}
	for weapon in configs:
		if weapon == null or not weapon.validate() or result.has(weapon.id) or codes.has(weapon.code):
			return {}
		result[weapon.id] = weapon
		codes[weapon.code] = true
	return result

static func load_all() -> Dictionary:
	var configs := []
	for code in ["bazooka", "grenade", "drill_missile"]:
		configs.append(load("res://assets/config/weapons/%s.tres" % code))
	return from_configs(configs)
