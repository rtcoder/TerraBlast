extends RefCounted
const DEFAULT_PATH := "user://connection_profiles.json"
const MAX_BYTES := 65536
const MAX_PROFILES := 20
var path: String
var _profiles: Array = []
var _last := {}
func _init(value: String = DEFAULT_PATH) -> void: path = value
static func result(ok: bool, reason := "") -> Dictionary: return {"ok":ok,"reason":reason}
static func clean(value: Variant, minimum: int, maximum: int) -> bool:
	if not value is String or value.length()<minimum or value.length()>maximum or value.strip_edges()!=value: return false
	for i in value.length():
		if value.unicode_at(i)<32 or (value.unicode_at(i)>=127 and value.unicode_at(i)<=159): return false
	return true
static func valid_host(value: Variant) -> bool:
	if not clean(value,1,253): return false
	if value.is_valid_ip_address(): return true
	if value.contains(":") or value.begins_with(".") or value.ends_with("."): return false
	for part in value.split("."):
		if part.is_empty() or part.length()>63 or part.begins_with("-") or part.ends_with("-"): return false
		for c in part.to_lower():
			if c not in "abcdefghijklmnopqrstuvwxyz0123456789-": return false
	return true
static func valid_url(value: Variant) -> bool:
	if not clean(value,8,2048): return false
	if not value.begins_with("http://") and not value.begins_with("https://"): return false
	var authority: String = value.substr(value.find("://")+3).trim_suffix("/")
	if authority.contains("/") or authority.contains("?") or authority.contains("#") or authority.contains("@"): return false
	var hostname := authority
	var port_string := ""
	if authority.begins_with("["):
		var end := authority.find("]")
		if end<0: return false
		hostname=authority.substr(1,end-1)
		var tail:=authority.substr(end+1)
		if not tail.is_empty():
			if not tail.begins_with(":"): return false
			port_string=tail.substr(1)
	elif authority.contains(":"):
		if authority.count(":")!=1: return false
		hostname=authority.get_slice(":",0); port_string=authority.get_slice(":",1)
	if authority.ends_with(":"): return false
	return valid_host(hostname) and (port_string.is_empty() or (port_string.is_valid_int() and int(port_string)>=1 and int(port_string)<=65535))
static func valid_endpoint(value: Variant) -> bool:
	return value is Dictionary and value.size()==3 and valid_host(value.get("host")) and (value.get("port") is int or value.get("port") is float) and is_finite(float(value.port)) and value.port==int(value.port) and value.port>=1 and value.port<=65535 and valid_url(value.get("backend_url"))
static func valid_id(value: Variant) -> bool:
	if not value is String or value.length()!=32: return false
	for c in value:
		if c not in "0123456789abcdef": return false
	return true
func list_profiles() -> Array: return _profiles.duplicate(true)
func last_success() -> Dictionary: return _last.duplicate(true)
func add_profile(title: String, host: String, port: int, backend_url: String) -> Dictionary:
	if _profiles.size()>=MAX_PROFILES: return result(false,"profile_limit")
	var id:=Crypto.new().generate_random_bytes(16).hex_encode()
	var row:={"id":id,"title":title,"host":host,"port":port,"backend_url":backend_url.trim_suffix("/")}
	if not _valid_row(row): return result(false,"invalid_profile")
	_profiles.append(row)
	return {"ok":true,"id":id,"reason":""}
static func _valid_row(row: Variant) -> bool:
	return row is Dictionary and row.size()==5 and valid_id(row.get("id")) and clean(row.get("title"),1,48) and valid_endpoint({"host":row.get("host"),"port":row.get("port"),"backend_url":row.get("backend_url")})
func update_profile(id: String, fields: Dictionary) -> Dictionary:
	for i in _profiles.size():
		if _profiles[i].id==id:
			var next: Dictionary=_profiles[i].duplicate()
			for key in fields:
				if key not in ["title","host","port","backend_url"]: return result(false,"invalid_field")
				next[key]=fields[key]
			if not _valid_row(next): return result(false,"invalid_profile")
			_profiles[i]=next
			return result(true)
	return result(false,"unknown_profile")
func remove_profile(id: String) -> Dictionary:
	for i in _profiles.size():
		if _profiles[i].id==id: _profiles.remove_at(i); return result(true)
	return result(false,"unknown_profile")
func remember_success(host: String, port: int, backend_url: String) -> Dictionary:
	var next:={"host":host,"port":port,"backend_url":backend_url}
	if not valid_endpoint(next): return result(false,"invalid_endpoint")
	_last=next
	return result(true)
func load_from(value: String = "") -> Dictionary:
	var file:=FileAccess.open(path if value.is_empty() else value,FileAccess.READ)
	if file==null: return result(false,"open_failed")
	if file.get_length()>MAX_BYTES: file.close(); return result(false,"file_too_large")
	var text:=file.get_as_text(); file.close()
	var data: Variant=JSON.parse_string(text)
	if not data is Dictionary or data.size()!=3 or data.get("version")!=1 or not data.get("profiles") is Array or not data.get("last_success") is Dictionary or data.profiles.size()>MAX_PROFILES: return result(false,"invalid_document")
	var used:={}
	for row in data.profiles:
		if not _valid_row(row) or used.has(row.id): return result(false,"invalid_profile")
		used[row.id]=true
	if not data.last_success.is_empty() and not valid_endpoint(data.last_success): return result(false,"invalid_last_success")
	_profiles=data.profiles.duplicate(true); _last=data.last_success.duplicate(true)
	return result(true)
func save_to(value: String = "") -> Dictionary:
	var target:=path if value.is_empty() else value
	return atomic_write(target,JSON.stringify({"version":1,"profiles":_profiles,"last_success":_last}))
static func atomic_write(target: String, content: String) -> Dictionary:
	var temp:=target+".tmp-"+Crypto.new().generate_random_bytes(8).hex_encode()
	var file:=FileAccess.open(temp,FileAccess.WRITE)
	if file==null: return result(false,"write_failed")
	file.store_string(content); file.flush()
	var error:=file.get_error(); file.close()
	if error==OK: error=DirAccess.rename_absolute(temp,target)
	if error!=OK: DirAccess.remove_absolute(temp)
	return result(error==OK,"" if error==OK else "write_failed")
