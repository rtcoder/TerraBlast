class_name MapRegistry
extends RefCounted

const PATHS := {
	"ballistics_range": "res://maps/ballistics_range.toml",
	"terraced_quarry": "res://maps/terraced_quarry.toml",
	"split_pass": "res://maps/split_pass.toml",
	"bunker_court": "res://maps/bunker_court.toml",
	"ring_island": "res://maps/ring_island.toml",
	"three_lane_foundry": "res://maps/three_lane_foundry.toml",

	"twin_forts": "res://maps/twin_forts.toml",
	"two_islands": "res://maps/two_islands.toml",
	"canyon_bridge": "res://maps/canyon_bridge.toml",
}
const DESCRIPTIONS := {
	"ballistics_range": "Known distances and layered target materials for local training.",
	"terraced_quarry": "Stepped quarry terraces and mixed-height cover.",
	"split_pass": "Two separate crossings over a destructible canyon.",
	"bunker_court": "Metal bunkers with destructible entrances around a courtyard.",
	"ring_island": "Exposed island edges surround a sheltered interior.",
	"three_lane_foundry": "Three industrial lanes with destructible cross passages.",

	"twin_forts": "Two fortified positions with destructible walls and open approaches.",
	"two_islands": "Separated islands with stone cover and an exposed gap.",
	"canyon_bridge": "Two canyon rims joined by a narrow bridge, with cover at each approach.",
}

static func describe(id: String) -> Dictionary:
	if not PATHS.has(id):
		return {}
	var definition = preload("res://scripts/core/maps/map_loader.gd").load_from_file(PATHS[id])
	if definition.id != id or not preload("res://scripts/core/maps/map_validator.gd").validate_definition(definition).is_empty(): return {}
	var spawns := []
	var slots := {}
	for row in definition.spawns:
		var slot: int = row.get("slot",slots.get(row.team,0))
		slots[row.team] = slot+1
		spawns.append(preload("res://scripts/core/maps/spawn_point.gd").new(Vector3i(row.position[0],row.position[1],row.position[2]),row.team,slot,float(row.get("yaw",0))))
	var supported := []
	for count in range(2,11):
		if preload("res://scripts/core/maps/spawn_selector.gd").select(spawns,count).ok: supported.append(count)
	if supported.is_empty(): return {}
	return {
		"supported_player_counts": supported,
		"id": id, "name": definition.display_name, "description": DESCRIPTIONS[id],
		"player_capacity": supported[-1],
		"size": [definition.size.x, definition.size.y, definition.size.z],
	}
