class_name ArenaGenerator
extends RefCounted

const Loader := preload("res://scripts/core/maps/map_loader.gd")
const Validator := preload("res://scripts/core/maps/map_validator.gd")
const Builder := preload("res://scripts/core/maps/map_builder.gd")
const Spawn := preload("res://scripts/core/maps/spawn_point.gd")

static func materials() -> Dictionary:
	var result := {}
	for row in [[0,"air",0,1.0,false,false], [1,"dirt",100,1.0,true,true], [2,"stone",180,2.0,true,true], [3,"metal",255,4.0,true,false]]:
		var material = load("res://scripts/core/voxels/voxel_material_config.gd").new()
		material.id = row[0]
		material.code = row[1]
		material.display_name = str(row[1]).capitalize()
		material.max_health = row[2]
		material.blast_resistance = row[3]
		material.is_solid = row[4]
		material.is_destructible = row[5]
		result[material.id] = material
	return result

static func generate(map_path: String, chunk_size: int = 16) -> Dictionary:
	return from_definition(Loader.load_from_file(map_path), chunk_size)

static func from_definition(definition: RefCounted, chunk_size: int = 16, material_configs: Dictionary = {}) -> Dictionary:
	var configs := materials() if material_configs.is_empty() else material_configs
	var errors: Array[String] = preload("res://scripts/core/voxels/material_catalog.gd").validate(configs)
	if errors.is_empty(): errors.append_array(Validator.validate_definition(definition, configs))
	var spawns: Array[Spawn] = []
	var result := {"world": null, "materials": configs, "spawns": spawns, "errors": errors}
	if chunk_size <= 0:
		errors.append("Chunk size must be positive")
	if not errors.is_empty():
		return result
	var world = load("res://scripts/core/voxels/voxel_world_data.gd").new(definition.size, chunk_size)
	Builder.apply_to_world(world, result.materials, definition)
	errors.append_array(Validator.validate(definition, world, configs))
	if not errors.is_empty():
		return result
	var slots := {}
	for spawn: Dictionary in definition.spawns:
		var team: int = spawn.team
		var slot: int = int(spawn.get("slot", slots.get(team, 0)))
		slots[team] = slot + 1
		spawns.append(Spawn.new(Vector3i(spawn.position[0], spawn.position[1], spawn.position[2]), team, slot, float(spawn.get("yaw", 0))))
	spawns.sort_custom(func(a, b): return a.slot < b.slot if a.slot != b.slot else a.team < b.team)
	result.world = world
	return result
