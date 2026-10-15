class_name RulePresets
extends RefCounted

static func names() -> Array:
	return ["classic", "quick", "training"]

static func create(preset: String = "classic") -> Resource:
	if not preset in names():
		return null
	var rules = load("res://assets/config/game_rules.tres").duplicate()
	rules.preset = preset
	if preset == "quick":
		rules.turn_time = 20.0
		rules.max_turns = 30
	elif preset == "training":
		rules.starting_health = 500
	return rules if rules.validate() else null
