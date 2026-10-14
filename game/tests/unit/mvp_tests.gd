extends SceneTree
var failures := 0
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	var rules_path := "res://assets/config/game_rules.tres"
	check(ResourceLoader.exists(rules_path), "Rules resource must exist")
	if ResourceLoader.exists(rules_path):
		var rules = load(rules_path).duplicate()
		check(rules.validate(), "Default rules valid")
		rules.projectile_step = 0.0
		check(not rules.validate(), "Zero simulation step invalid")
	for code in ["bazooka", "grenade", "drill_missile"]:
		var path := "res://assets/config/weapons/%s.tres" % code
		check(ResourceLoader.exists(path), "Weapon exists: " + code)
		if ResourceLoader.exists(path):
			var weapon = load(path).duplicate()
			check(weapon.validate(), "Valid weapon: " + code)
			weapon.projectile_speed = -1.0
			check(not weapon.validate(), "Reject negative weapon speed")
	print("MVP tests: %d failures" % failures)
	quit(1 if failures else 0)
