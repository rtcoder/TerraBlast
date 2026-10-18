class_name MapSerializer
extends RefCounted
const Validator = preload("res://scripts/core/maps/map_validator.gd")
static func to_dictionary(definition: RefCounted) -> Dictionary:
	return {"id":definition.id,"name":definition.display_name,"size":[definition.size.x,definition.size.y,definition.size.z],"theme":definition.theme,"spawns":definition.spawns.duplicate(true),"boxes":definition.boxes.duplicate(true),"carves":definition.carves.duplicate(true)}
static func to_toml(definition: RefCounted) -> Dictionary:
	var errors: Array[String] = Validator.validate_definition(definition)
	if not errors.is_empty(): return {"ok":false,"text":"","reason":"; ".join(errors)}
	var data := to_dictionary(definition)
	var lines := PackedStringArray()
	for key in ["id","name","size","theme"]: lines.append(key + " = " + JSON.stringify(data[key]))
	for section in ["spawns","boxes","carves"]:
		for entry in data[section]:
			lines.append("\n[[" + section + "]]")
			var keys: Array = entry.keys()
			keys.sort()
			for key in keys: lines.append(str(key) + " = " + JSON.stringify(entry[key],"",true,true))
	return {"ok":true,"text":"\n".join(lines) + "\n"}
