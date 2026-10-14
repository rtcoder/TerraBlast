class_name WeaponCatalog
extends RefCounted

static func load_all() -> Dictionary:
	var result := {}
	for code in ["bazooka", "grenade", "drill_missile"]:
		var weapon = load("res://assets/config/weapons/%s.tres" % code)
		if weapon != null and weapon.validate():
			result[weapon.id] = weapon
	return result
