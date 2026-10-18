extends SceneTree
const Training = preload("res://scripts/core/training/training_session.gd")
var failures := 0
func check(value: bool,label: String) -> void:
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	check(Training.wind_description(0).contains("calm"),"Zero wind is explicitly calm")
	check(Training.wind_description(-2.5).contains("left") and Training.wind_description(-2.5).contains("2.50"),"Negative wind direction/magnitude")
	check(Training.wind_description(2.5).contains("right"),"Positive wind direction")
	var captions = load("res://scripts/client/ui/event_captions.gd").new()
	captions.enabled = true
	captions.consume([{"type":"TurnStarted"}],"0/1/1")
	captions.clear()
	captions.consume([{"type":"TurnStarted"}],"0/1/1")
	check(captions.pending.size()==1,"New match can reuse event identity after clear")
	captions.free()
	print("client_review250: %d failures" % failures)
	quit(1 if failures else 0)
