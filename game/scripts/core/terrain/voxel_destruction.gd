class_name VoxelDestruction
extends RefCounted

const TerrainDeltaScript := preload("res://scripts/core/voxels/terrain_delta.gd")

var world: RefCounted
var material_configs: Dictionary = {}

func _init(initial_world: RefCounted, initial_material_configs: Dictionary) -> void:
	world = initial_world
	material_configs = initial_material_configs

func apply_explosion(center: Vector3i, radius: int, base_damage: int) -> Array:
	var deltas: Array = []
	var safe_radius: int = maxi(0, radius)
	var min_position := center - Vector3i(safe_radius, safe_radius, safe_radius)
	var max_position := center + Vector3i(safe_radius, safe_radius, safe_radius)

	for z in range(min_position.z, max_position.z + 1):
		for y in range(min_position.y, max_position.y + 1):
			for x in range(min_position.x, max_position.x + 1):
				var position := Vector3i(x, y, z)
				if not world.is_in_bounds(position):
					continue

				var distance := Vector3(position - center).length()
				if distance > float(safe_radius):
					continue

				var material_id: int = int(world.get_material_id(position))
				var material: Variant = get_material_config(material_id)
				if material == null or not material.is_destructible:
					continue

				var factor := 1.0
				if safe_radius > 0:
					factor = 1.0 - (distance / float(safe_radius))

				var resistance: float = maxf(0.01, float(material.blast_resistance))
				var damage: int = int(round(float(base_damage) * factor / resistance))
				if damage <= 0:
					continue

				var new_health: int = maxi(0, int(world.get_health(position)) - damage)
				if new_health <= 0:
					world.set_voxel(position, 0, 0)
				else:
					world.set_health(position, new_health)

				deltas.append(TerrainDeltaScript.new(position, world.get_material_id(position), world.get_health(position)))

	return deltas

func get_material_config(material_id: int) -> Variant:
	if material_configs.has(material_id):
		return material_configs[material_id]
	return null
