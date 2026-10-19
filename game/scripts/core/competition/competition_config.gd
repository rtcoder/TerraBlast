extends RefCounted
const Registry = preload("res://scripts/core/maps/map_registry.gd")
static func failure(reason: String) -> Dictionary: return {"ok":false,"reason":reason}
static func keys(value: Variant, expected: Array) -> bool:
	if not value is Dictionary or value.size()!=expected.size(): return false
	for key in expected:
		if not value.has(key): return false
	return true
static func integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)==floor(float(value)) and value>=low and value<=high
static func text(value: Variant, maximum: int) -> bool:
	if not value is String or value.strip_edges().is_empty() or value.length()>maximum: return false
	for character in value:
		var code: int = character.unicode_at(0)
		if code<32 or (code>=127 and code<=159): return false
	return true
static func defaults() -> Dictionary:
	return {"title":"Local competition","format":"league","entrants":[{"id":"entrant_1","name":"Team A","seed":0},{"id":"entrant_2","name":"Team B","seed":1}],"maps":["two_islands"],"count":2,"preset":"quick"}
static func validate(value: Variant) -> Dictionary:
	if not keys(value,["title","format","entrants","maps","count","preset"]): return failure("Invalid competition configuration fields")
	if not text(value.title,64) or value.format not in ["league","double_league","knockout"] or value.preset not in ["classic","quick","training"]: return failure("Invalid title, format or rules preset")
	if not integer(value.count,2,10) or int(value.count)%2!=0: return failure("Choose 2, 4, 6, 8 or 10 characters for equal teams")
	if not value.entrants is Array or value.entrants.size()<2 or value.entrants.size()>8: return failure("Choose 2–8 participants")
	var ids := {}
	var names := {}
	var entrants := []
	for index in value.entrants.size():
		var row: Variant = value.entrants[index]
		if not keys(row,["id","name","seed"]) or not row.id is String or not text(row.name,32) or not integer(row.seed,0,7) or int(row.seed)!=index: return failure("Invalid participant name or seeding")
		if row.id not in ["entrant_1","entrant_2","entrant_3","entrant_4","entrant_5","entrant_6","entrant_7","entrant_8"] or ids.has(row.id): return failure("Duplicate or invalid participant identity")
		var normalized: String = row.name.strip_edges().to_lower()
		if names.has(normalized): return failure("Participant names must be unique")
		ids[row.id] = true
		names[normalized] = true
		entrants.append({"id":row.id,"name":row.name.strip_edges(),"seed":index})
	if not value.maps is Array or value.maps.is_empty() or value.maps.size()>9: return failure("Choose 1–9 arenas")
	var maps := []
	for id in value.maps:
		if not id is String or maps.has(id) or not Registry.PATHS.has(id): return failure("Unknown or duplicate arena")
		if not Registry.describe(id).get("supported_player_counts",[]).has(int(value.count)): return failure("Arena does not support this character count: "+id)
		maps.append(id)
	return {"ok":true,"config":{"title":value.title.strip_edges(),"format":value.format,"entrants":entrants,"maps":maps,"count":int(value.count),"preset":value.preset}}
static func preview(config: Dictionary) -> Dictionary:
	var n: int = config.entrants.size()
	if config.format=="knockout":
		var slots := 2
		var rounds := 1
		while slots<n:
			slots *= 2
			rounds += 1
		return {"rounds":rounds,"fixtures":n-1,"byes":slots-n}
	var legs := 2 if config.format=="double_league" else 1
	return {"rounds":(n-1 if n%2==0 else n)*legs,"fixtures":n*(n-1)/2*legs,"byes":n*legs if n%2 else 0}
