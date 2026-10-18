extends RefCounted
var best_of := 1
var active := false
var completed := false
var scores := {1:0,2:0}
var seen := {}
func start(count: int) -> bool:
	if count not in [1,3,5]: return false
	best_of = count
	active = true
	completed = false
	scores = {1:0,2:0}
	seen.clear()
	return true
func record_result(generation: int, winner: int) -> bool:
	if not active or completed or seen.has(generation) or winner not in [0,1,2]: return false
	seen[generation] = true
	if winner != 0: scores[winner] += 1
	completed = scores[1] > best_of / 2 or scores[2] > best_of / 2
	return true
func next_round() -> bool:
	return active and not completed and not seen.is_empty()
func reset() -> void:
	active = false
	completed = false
	scores = {1:0,2:0}
	seen.clear()
