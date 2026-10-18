class_name MaterialCatalog
extends RefCounted
const VoxelMaterial = preload("res://scripts/core/voxels/voxel_material_config.gd")
static func validate(configs: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var codes := {}
	if not configs.has(0): errors.append("Air material is required")
	for key in configs:
		var material: Variant = configs[key]
		if not key is int or not material is VoxelMaterial:
			errors.append("Material key/type invalid")
			continue
		if material.id != key or key < 0 or key > 255 or material.code.is_empty() or codes.has(material.code): errors.append("Material ID/code invalid or duplicate")
		codes[material.code] = true
		if not is_finite(material.blast_resistance) or material.blast_resistance <= 0 or material.max_health < 0 or material.max_health > 10000: errors.append("Material health/resistance invalid")
		if key == 0 and (material.code != "air" or material.is_solid or material.is_destructible or material.max_health != 0): errors.append("Air properties invalid")
		if key != 0 and (material.code == "air" or (material.is_solid and material.max_health <= 0) or (material.is_destructible and material.max_health <= 0)): errors.append("Material properties inconsistent")
	return errors
static func from_configs(configs: Array) -> Dictionary:
	var result := {}
	for material in configs:
		if not material is VoxelMaterial or result.has(material.id): return {}
		result[material.id] = material.duplicate()
	return result if validate(result).is_empty() else {}
