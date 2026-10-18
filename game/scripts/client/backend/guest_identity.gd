extends RefCounted
const Profiles=preload("res://scripts/client/backend/connection_profiles.gd")
static func valid(value: Variant) -> bool: return Profiles.clean(value,10,128)
static func load_or_create(path: String = "user://guest_id.txt") -> Dictionary:
	var file:=FileAccess.open(path,FileAccess.READ)
	if file!=null:
		if file.get_length()<=512:
			var value:=file.get_as_text().strip_edges()
			file.close()
			if valid(value): return {"ok":true,"reason":"","id":value}
		else: file.close()
	var id:=Crypto.new().generate_random_bytes(16).hex_encode()
	var saved:=Profiles.atomic_write(path,id)
	saved["id"]=id if saved.ok else ""
	return saved
