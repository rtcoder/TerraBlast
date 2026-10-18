extends RefCounted
## Owns local control/recording, never network authority. Scene owns presentation.
const Replay = preload("res://scripts/core/replay/match_replay.gd")
const Planner = preload("res://scripts/core/bots/bot_planner.gd")
var scene: Node
var options := {"mode": "hotseat", "difficulty": "normal", "human_team": 1}
var recorder: RefCounted
var bot: RefCounted
var bot_key := ""
var playback: RefCounted
var live_runner: RefCounted
var live_velocities := {}
func _init(owner_scene: Node) -> void:
	scene = owner_scene
	new_recording()
func new_recording() -> void:
	bot = null
	recorder = Replay.new()
	recorder.capture(scene.runner)
func is_bot_turn() -> bool:
	var workflows = scene.get("workflows")
	if workflows != null and workflows.training.active: return false
	if scene.remote_mode or playback != null or options.mode != "solo" or scene.runner.state.status != "playing":
		return false
	var active = scene.runner.state.get_active_player()
	return active != null and active.team_id != options.human_team
func update_bot() -> void:
	if scene.local_paused or scene.menu_open or scene.projectile_in_flight or playback != null:
		return
	if not is_bot_turn():
		bot = null
		return
	var state = scene.runner.state
	var key := "%d/%d/%d" % [state.generation, state.turn_id, state.revision]
	if bot != null and key != bot_key:
		bot = null
	if bot == null:
		bot_key = key
		bot = Planner.new()
		bot.begin(scene.runner, options.difficulty)
	bot.step(2)
	if not bot.finished:
		return
	var command = bot.command
	bot = null
	if command != null:
		var result: Dictionary = recorder.submit(scene.runner, command)
		if result.ok:
			scene._play_result(result)
	else:
		# Exhausted inventory cannot act; expire this turn through recorded authority.
		recorder.tick(scene.runner, scene.runner.state.time_remaining)
func can_archive() -> bool:
	var workflows = scene.get("workflows")
	if workflows != null and workflows.training.active: return false
	return not scene.remote_mode and not scene.projectile_in_flight and playback == null
