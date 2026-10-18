extends RefCounted
const Planner = preload("res://scripts/core/bots/bot_planner.gd")
var planner: RefCounted
func begin(runner: RefCounted) -> bool:
	planner = Planner.new()
	planner.begin(runner,"normal")
	return not planner.finished
func step(budget := 2) -> void:
	if planner != null: planner.step(budget)
func suggestion() -> Dictionary:
	if planner == null: return {"ok":false,"reason":"Request a hint first"}
	if not planner.finished: return {"ok":false,"reason":"Calculating hint…"}
	var command: RefCounted = planner.command
	return {"ok":command != null,"command":command,"reason":"No current suggestion"}
func cancel() -> void: planner = null
