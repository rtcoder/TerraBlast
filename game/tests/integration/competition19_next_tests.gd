extends SceneTree
const Event = preload("res://scripts/core/competition/competition_event.gd")
const Store = preload("res://scripts/core/competition/competition_store.gd")
const Config = preload("res://scripts/core/competition/competition_config.gd")
const Replay = preload("res://scripts/core/replay/match_replay.gd")
var failures := 0
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void: call_deferred("run")
func configuration(format: String) -> Dictionary:
	var cfg := Config.defaults()
	cfg.format = format
	cfg.entrants.append({"id":"entrant_3","name":"Team C","seed":2})
	return cfg
func run() -> void:
	if not FileAccess.file_exists("res://scripts/client/competition/competition_controller.gd"):
		check(false,"Competition controller and native panel not implemented")
		quit(1)
		return
	root.size = Vector2i(800,600)
	var scene = load("res://scenes/debug/VoxelDebug.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_physics_process(false)
	if scene.get("competition")==null:
		check(false,"Native scene competition hook is missing")
		scene.queue_free()
		await process_frame
		quit(1)
		return
	var directory := ("/private/tmp" if OS.get_name()=="macOS" else "/tmp").path_join("terrablast-competition-ui19-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(directory)
	var controller = scene.competition
	controller.path = directory.path_join("competition.json")
	var live = scene.runner
	var live_hash := Replay.state_hash(live)
	var recorder = scene.session.recorder
	var series = scene.workflows.series
	series.start(3)
	series.record_result(999,1)
	scene.match_panels.competition_requested.emit()
	check(controller.panel.visible and scene.local_paused,"Native menu opens competition and pauses gameplay")
	controller.panel.apply_configuration(configuration("league"))
	controller.panel.create_button.pressed.emit()
	check(controller.event.fixtures().size()==3,"Native form creates 3-team league")
	for format in ["league","knockout"]:
		if format=="knockout":
			controller.create(configuration(format))
			controller.panel.confirm_button.pressed.emit()
		var limit := 0
		while not controller.event.is_complete() and limit<8:
			var id: String = controller.event.ready_ids()[0]
			controller.panel.schedule_box.get_node("Play_"+id).pressed.emit()
			check(controller.fixture_runner==scene.runner and scene.runner!=live,"Play launches real fixture runner")
			check(scene.session.options.mode=="hotseat" and controller.team_label.text.contains("Team"),"Competition labels and actual hotseat mode")
			var active = scene.runner.state.get_active_player()
			var result: Dictionary = scene.session.recorder.surrender(scene.runner,active.player_id)
			check(result.ok,"Authoritative recorded surrender finishes actual match")
			controller.update(0)
			controller.update(0)
			check(controller.event.snapshot().results.size()==limit+1,"Ended result accepted exactly once")
			controller.return_button.pressed.emit()
			check(controller.panel.visible,"Back button opens competition hub")
			limit += 1
		check(controller.event.is_complete(),"Whole real-scene "+format+" completes")
		check(controller.panel.report.text.contains("Champion:"),"Champion and report visible")
		if not OS.get_environment("TB_COMPETITION_SCREENSHOT").is_empty():
			scene.preferences.hud_scale = 1.25
			controller.panel.show_tab("Standings" if format=="league" else "Schedule")
			controller.panel.fit(Vector2(800,600),1.25)
			controller.panel.scroll.scroll_vertical = 0
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OS.get_environment("TB_COMPETITION_SCREENSHOT").trim_suffix(".png")+"-"+format+".png")
	# A new fixture exercises live checkpointing and every destructive root guard.
	controller.create(configuration("league"))
	controller.panel.confirm_button.pressed.emit()
	controller.launch(controller.event.ready_ids()[0])
	var fixture = scene.runner
	var fixture_hash := Replay.state_hash(fixture)
	check(not scene.start_local_match("two_islands",2,"quick"),"Root blocks an unrelated new match during competition")
	scene.restart_match()
	check(scene.runner==fixture and Replay.state_hash(fixture)==fixture_hash,"Root restart guard preserves active fixture")
	check(not scene.session.can_archive(),"Root archive guard blocks active competition")
	var gravity_before: float = scene.rules.base_gravity
	scene.debug_panel.show()
	scene._adjust_debug_gravity(1.0)
	check(scene.rules.base_gravity==gravity_before,"Root debug shortcut preserves canonical competition rules")
	scene.workflows.begin_training("movement")
	check(not scene.workflows.training.active and scene.runner==fixture,"Training guard preserves competition authority")
	check(controller.save().ok,"Active fixture saves through actual adapter")
	scene.runner.state.time_remaining -= 0.25
	check(controller.resume().ok and Replay.state_hash(scene.runner)==fixture_hash,"Resume restores exact active fixture")
	check(controller.fixture_runner==scene.runner and controller.fixture_token==controller.event.snapshot().active,"Resume reconnects result identity")
	controller.open()
	check(controller.abandon_active().ok,"Abandon active attempt from hub")
	check(controller.event.snapshot().results.is_empty(),"Abandoned fixture never receives a result")
	controller.close()
	check(scene.runner==live or (controller.panel.visible and scene.local_paused),"Abandoned runner cannot resume gameplay outside a fixture")
	controller.open()
	controller.launch(controller.event.ready_ids()[0])
	var orphan_candidate = scene.runner
	var draft := Event.new()
	draft.create(Config.defaults())
	check(Store.save(controller.path,draft).ok,"Write isolated saved draft while a fixture is active")
	check(controller.resume().ok,"Resume a draft over an active fixture")
	check(Store.load(controller.path).event.snapshot()==draft.snapshot(),"Draft resume does not overwrite the file with the abandoned old event")
	controller.close()
	check(scene.runner==live and scene.runner!=orphan_candidate and not controller.is_active(),"Draft resume restores original live context before dropping fixture identity")
	check(controller.save().ok,"Save through actual adapter")
	var before: Dictionary = controller.event.snapshot()
	var file := FileAccess.open(controller.path,FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	check(not controller.resume().ok and controller.event.snapshot()==before,"Damaged resume leaves event untouched")
	check(controller.return_to_live().ok,"Return to original gameplay")
	check(scene.runner==live and Replay.state_hash(scene.runner)==live_hash,"Original live runner and hash restored")
	check(scene.session.recorder==recorder and scene.workflows.series==series and series.scores[1]==1,"Original recording and best-of preserved")
	check(not controller.is_active(),"Competition stops blocking original workflows")
	DirAccess.remove_absolute(controller.path)
	DirAccess.remove_absolute(directory)
	scene.queue_free()
	await process_frame
	print("competition19_next: ","PASS" if failures==0 else "FAIL"," failures=",failures)
	quit(0 if failures==0 else 1)
