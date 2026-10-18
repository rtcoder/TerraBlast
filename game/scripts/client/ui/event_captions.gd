extends Label
var enabled := false
var pending: Array = []
var seen := {}
func consume(events: Array, identity: String) -> void:
	if not enabled or seen.has(identity): return
	seen[identity] = true
	if seen.size() > 100: seen.erase(seen.keys()[0])
	for event in events:
		var caption := ""
		match event.get("type",""):
			"TurnStarted": caption = "New turn"
			"PlayerDamaged": caption = "%s: −%s HP" % [event.player_id,event.amount]
			"MatchEnded": caption = "Match ended"
		if not caption.is_empty(): pending.append({"text":caption,"remaining":3.0})
	while pending.size() > 20: pending.pop_front()
func tick(delta: float) -> void:
	if not enabled: clear(); return
	for entry in pending: entry.remaining -= delta
	pending = pending.filter(func(entry): return entry.remaining > 0)
	var lines := PackedStringArray()
	for entry in pending.slice(maxi(0,pending.size()-5)): lines.append(entry.text)
	text = "\n".join(lines)
func clear() -> void:
	seen.clear()
	pending.clear()
	text = ""
