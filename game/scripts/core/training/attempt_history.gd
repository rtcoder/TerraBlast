extends RefCounted
var _entries: Array = []
var _seen := {}
func append(attempt: Dictionary) -> bool:
	var id: String = attempt.get("event_id","")
	if id.is_empty() or _seen.has(id): return false
	_seen[id] = true
	_entries.append(attempt.duplicate(true))
	if _entries.size() > 50:
		var removed: Dictionary = _entries.pop_front()
		_seen.erase(removed.event_id)
	return true
func entries() -> Array: return _entries.duplicate(true)
func best() -> Dictionary:
	var selected := {}
	for attempt in _entries:
		if attempt.get("demonstration",false): continue
		if selected.is_empty() or attempt.get("enemy_damage",0) > selected.get("enemy_damage",0) or (attempt.get("enemy_damage",0) == selected.get("enemy_damage",0) and attempt.get("distance",INF) < selected.get("distance",INF)):
			selected = attempt
	return selected.duplicate(true)
func streak() -> int:
	var value := 0
	for attempt in _entries:
		if attempt.get("demonstration",false): continue
		value = value + 1 if attempt.get("hit",false) else 0
	return value
