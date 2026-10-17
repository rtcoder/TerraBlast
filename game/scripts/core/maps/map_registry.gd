class_name MapRegistry
extends RefCounted

const PATHS := {
	"twin_forts": "res://maps/twin_forts.toml",
	"two_islands": "res://maps/two_islands.toml",
	"canyon_bridge": "res://maps/canyon_bridge.toml",
}
const DESCRIPTIONS := {
	"twin_forts": "Two fortified positions with destructible walls and open approaches.",
	"two_islands": "Separated islands with stone cover and an exposed gap.",
	"canyon_bridge": "Two canyon rims joined by a narrow bridge, with cover at each approach.",
}

static func describe(id: String) -> Dictionary:
	if not PATHS.has(id):
		return {}
	var definition = preload("res://scripts/core/maps/map_loader.gd").load_from_file(PATHS[id])
	return {
		"id": id, "name": definition.display_name, "description": DESCRIPTIONS[id],
		"player_capacity": mini(10, definition.spawns.size()),
		"size": [definition.size.x, definition.size.y, definition.size.z],
	}
