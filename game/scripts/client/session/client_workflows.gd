extends RefCounted
const Store = preload("res://scripts/core/replay/session_store.gd")
const Lessons = preload("res://scripts/core/training/training_lessons.gd")
var scene: Node
var training = preload("res://scripts/core/training/training_session.gd").new()
var coach = preload("res://scripts/core/training/training_coach.gd").new()
var progress = preload("res://scripts/core/training/training_progress.gd").new()
var series = preload("res://scripts/client/session/match_series.gd").new()
var autosave = preload("res://scripts/client/session/local_autosave.gd").new()
var confirmation: PanelContainer
var training_panel: PanelContainer
var captions: Label
var weapon_hud: Label
var control_label: Label
var crosshair: Control
var focus = preload("res://scripts/client/ui/panel_focus_controller.gd").new()
var live := {}
var handoff := false
var last_turn := ""
var training_result_shown := false
var saved_lesson := ""
var training_notice := ""
var progress_path := "user://training_progress.cfg"
var series_config := {}
var match_epoch := 0
var markers: Array[Node3D] = []
var marker_count := 0
var last_overlay: Control
var last_live_runner: RefCounted
func _init(owner_scene: Node):
	scene = owner_scene
	last_live_runner = scene.runner
func setup() -> void:
	progress.load_from(progress_path)
	confirmation = preload("res://scripts/client/ui/confirmation_panel.gd").new()
	scene.get_node("Hud").add_child(confirmation)
	confirmation.confirmed.connect(_confirm)
	confirmation.cancelled.connect(func(): scene._refresh_menu_state())
	training_panel = preload("res://scripts/client/ui/training_panel.gd").new()
	scene.get_node("Hud").add_child(training_panel)
	training_panel.setup(Lessons.list(),progress)
	training_panel.lesson_requested.connect(begin_training)
	training_panel.retry_requested.connect(func(): retry_training(false))
	training_panel.last_retry_requested.connect(func(): retry_training(true))
	training_panel.continue_requested.connect(continue_training)
	training_panel.exit_requested.connect(exit_training)
	training_panel.coach_requested.connect(func():
		if training.active: coach.begin(scene.runner))
	training_panel.demonstrate_requested.connect(demonstrate)
	training_panel.assistance_changed.connect(func(value):
		training.assistance = "none" if training.lesson_id == "blind_accuracy" else value)
	training_panel.next_requested.connect(func():
		if training.phase != "complete": return
		var ids := Lessons.LESSONS.keys()
		var index := ids.find(training.lesson_id)+1
		if index < ids.size(): begin_training(ids[index]))
	training_panel.reset_progress_requested.connect(func():
		confirmation.present("Reset training progress?","Completed lessons will be cleared.",{"action":"reset_progress"})
		scene._refresh_menu_state())
	scene.match_panels.training_requested.connect(open_training)
	scene.match_panels.autosave_requested.connect(continue_autosave)
	scene.match_panels.next_round_requested.connect(next_round)
	scene.match_panels.handoff_ready.connect(func(): handoff = false; scene._close_overlays())
	captions = preload("res://scripts/client/ui/event_captions.gd").new()
	captions.position = Vector2(30,110)
	scene.get_node("Hud").add_child(captions)
	weapon_hud = preload("res://scripts/client/ui/weapon_hud.gd").new()
	weapon_hud.position = Vector2(30,185)
	scene.get_node("Hud").add_child(weapon_hud)
	control_label = Label.new()
	control_label.position = Vector2(30,210)
	scene.get_node("Hud").add_child(control_label)
	scene.get_node("Hud/Crosshair").hide()
	crosshair = preload("res://scripts/client/ui/crosshair.gd").new()
	scene.get_node("Hud").add_child(crosshair)
	last_turn = _turn_key()
	scene.settings_panel.sound_preview_requested.connect(func(): scene.effects.preview_cue())
func overlays_open() -> bool:
	return confirmation != null and (confirmation.visible or training_panel.visible or handoff)
func refresh_visibility() -> void:
	if weapon_hud != null: weapon_hud.visible = not scene.menu_open
	if control_label != null: control_label.visible = not scene.menu_open
	if crosshair != null: crosshair.visible = not scene.menu_open

func close_overlays() -> void:
	if confirmation != null: confirmation.hide()
	if training_panel != null: training_panel.hide()
func blocked() -> bool:
	return handoff or (training.active and training.phase != "armed")
func _turn_key() -> String: return "%s/%s" % [scene.runner.state.generation,scene.runner.state.turn_id]
func request(action: String, config := {}) -> void:
	if scene.remote_mode:
		if action == "restart": scene.restart_match()
		return
	if scene.session.playback != null or training.active: return
	var active = scene.runner.state.get_active_player()
	var token := {"action":action,"generation":scene.runner.state.generation,"turn":scene.runner.state.turn_id,"player":active.player_id if active != null else "","config":config}
	confirmation.present("Confirm " + action.replace("_"," "),"Current player: " + (active.display_name if active != null else "none") + "\nThis changes the current match.",token)
	scene._refresh_menu_state()
func _confirm(token: Dictionary) -> void:
	if token.action == "reset_progress":
		progress.reset()
		training_notice = "Progress reset" if progress.save_to(progress_path) == OK else "Reset in memory; save failed"
		training_panel.status.text = training_notice
		scene._refresh_menu_state()
		return
	if scene.remote_mode or scene.session.playback != null or training.active or token.generation != scene.runner.state.generation or token.turn != scene.runner.state.turn_id:
		scene._refresh_menu_state()
		return
	var active = scene.runner.state.get_active_player()
	if token.player != (active.player_id if active != null else ""):
		scene._refresh_menu_state()
		return
	match token.action:
		"restart": scene.restart_match(); match_epoch += 1
		"surrender": scene._surrender()
		"new_match":
			var config: Dictionary = token.config
			if scene.match_panels.profiles.validate(config).ok:
				if scene.start_local_match(config.map,config.count,config.preset,config.mode,config.difficulty,config.human_team):
					series.start([1,3,5][scene.match_panels.series_select.selected])
					series_config = config.duplicate()
					scene.match_panels.profiles.set_last(config)
					if scene.match_panels.profiles.save_to() != OK: scene._session_message("Match started; configuration save failed")
	scene._refresh_menu_state()
func next_round() -> void:
	if scene.remote_mode or training.active or scene.session.playback != null or not series.next_round() or series_config.is_empty() or scene.runner.state.status != "ended": return
	var cfg := series_config
	scene.start_local_match(cfg.map,cfg.count,cfg.preset,cfg.mode,cfg.difficulty,cfg.human_team)
func on_started() -> void:
	last_live_runner = scene.runner
	match_epoch += 1
	handoff = false
	last_turn = _turn_key()
	captions.clear()
func continue_autosave() -> void:
	if scene.remote_mode or scene.projectile_in_flight or scene.session.playback != null or training.active: return
	var result: Dictionary = autosave.latest_valid()
	if not result.ok:
		scene._session_message(result.reason)
		return
	scene._replace_local_runner(result.runner)
	scene.session.options = result.options
	scene.player_velocities = result.velocities
	series.reset()
	on_started()
	scene._close_overlays()
	scene._session_message("Autosave restored; damaged newer slots skipped: %s" % result.skipped)
func open_training() -> void:
	if scene.remote_mode or scene.session.playback != null or scene.projectile_in_flight: return
	scene._close_overlays()
	training_panel.show()
	scene._refresh_menu_state()
func begin_training(id: String) -> void:
	if scene.remote_mode or scene.session.playback != null or scene.projectile_in_flight: return
	var snapshot: Dictionary
	if live.is_empty(): snapshot = Store.encode(scene.runner,scene.session.options,scene.player_velocities)
	else: snapshot = Store.encode(live.runner,live.options,live.velocities)
	if not snapshot.ok: training_panel.status.text = snapshot.reason; return
	var result: Dictionary = training.begin(id,snapshot.payload)
	if not result.ok: training_panel.status.text = result.reason; return
	if live.is_empty():
		live = {"runner":scene.runner,"options":scene.session.options.duplicate(),"velocities":scene.player_velocities.duplicate(),"recorder":scene.session.recorder,"handoff":handoff}
	saved_lesson = ""
	training_notice = ""
	_clear_markers()
	_apply_training(result)
func _apply_training(result: Dictionary) -> void:
	handoff = false
	coach.cancel()
	scene._replace_local_runner(result.runner)
	scene.session.options = result.options
	scene.player_velocities = result.velocities
	training_result_shown = false
	training.arm()
	scene._close_overlays()
	last_turn = _turn_key()
func retry_training(last: bool) -> void:
	if not training.active or scene.projectile_in_flight: return
	var result: Dictionary = training.retry_attempt() if last else training.retry_lesson()
	if result.ok:
		if not last: _clear_markers()
		_apply_training(result)
	else: training_panel.status.text = result.reason
func continue_training() -> void:
	if not training.active: return
	if training.phase == "complete":
		training_panel.status.text = "Lesson completed. Choose Next lesson or Retry lesson."
		return
	if training.lesson_id == "ammo_budget" and training.summary().attempts >= 3:
		training_panel.status.text = "Attempt limit reached. Retry lesson."
		return
	if training.phase == "result": retry_training(true)
	else:
		training.arm()
		scene._close_overlays()
func exit_training() -> void:
	if scene.projectile_in_flight: return
	coach.cancel()
	training.exit()
	_clear_markers()
	if not live.is_empty():
		scene._replace_local_runner(live.runner)
		scene.session.options = live.options
		scene.player_velocities = live.velocities
		scene.session.recorder = live.recorder
		handoff = live.get("handoff",false)
		live.clear()
	last_turn = _turn_key()
	scene._close_overlays()
func before_shot(command: RefCounted, demonstration := false) -> bool:
	if not training.active: return true
	var result := Store.encode(scene.runner,scene.session.options,scene.player_velocities)
	return result.ok and training.before_shot(result.payload,command,demonstration)
func after_shot(command: RefCounted, result: Dictionary) -> void:
	if not training.active: return
	if not result.ok: training.cancel_pending(); return
	training.after_shot(command,result)
	training_result_shown = false
	coach.cancel()
func demonstrate() -> void:
	if not training.active or scene.projectile_in_flight: return
	var hint: Dictionary = coach.suggestion()
	if not hint.ok: training_panel.hint.text = hint.reason; return
	training.arm()
	if not before_shot(hint.command,true): return
	var result: Dictionary = scene.session.recorder.submit(scene.runner,hint.command)
	after_shot(hint.command,result)
	if result.ok:
		scene._close_overlays()
		scene._play_result(result)
func consume(events: Array) -> void:
	captions.consume(events,"%s/%s/%s" % [scene.runner.state.generation,scene.runner.state.revision,scene.runner.state.turn_id])
func update(delta: float) -> void:
	if confirmation == null: return
	if not scene.remote_mode and scene.session.playback == null and not training.active and scene.runner != last_live_runner:
		series.reset()
		handoff = false
		last_live_runner = scene.runner
		last_turn = _turn_key()
	captions.enabled = scene.preferences.captions
	captions.tick(delta)
	crosshair.position = scene.get_viewport().get_visible_rect().size * 0.5
	crosshair.visible = not scene.menu_open
	crosshair.configure(scene.preferences.crosshair_size,scene.preferences.crosshair_contrast or scene.preferences.high_contrast)
	scene.get_node("Hud/Crosshair").visible = false
	var player = scene.runner.state.get_active_player()
	var ammo: int = scene.runner.state.inventory.get(player.player_id,{}).get(scene.selected_weapon_id,0) if player != null else 0
	weapon_hud.update_state(player,scene.runner.weapons[scene.selected_weapon_id],ammo,scene.shot_charge/maxf(0.01,scene.max_charge_time))
	var state := preload("res://scripts/client/ui/control_status.gd").describe({"ended":scene.runner.state.status != "playing","projectile":scene.projectile_in_flight,"menu":scene.menu_open,"bot":scene.session.is_bot_turn(),"training_waiting":training.active and training.phase != "armed","no_ammo":ammo == 0,"remote_blocked":scene.remote_mode and not scene._can_control()})
	control_label.text = state.reason
	if training.active and training.phase == "armed":
		control_label.text = Lessons.LESSONS[training.lesson_id] + " " + training.wind_description(scene.runner.rules.wind)
	control_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	control_label.size.x = minf(640,scene.get_viewport().get_visible_rect().size.x-60)
	weapon_hud.visible = not scene.menu_open
	control_label.visible = not scene.menu_open
	training.tick(delta,scene.local_paused or scene.projectile_in_flight)
	coach.step()
	if training.active:
		if training_panel.visible:
			training_panel.update_state(training.summary(),coach.suggestion())
			if not training_notice.is_empty(): training_panel.status.text += "\n" + training_notice
			training_panel.status.text += "\n" + training.wind_description(scene.runner.rules.wind)
			training_panel.assistance_select.select(["full","partial","none"].find(training.assistance))
		if training.phase in ["result","complete"] and not scene.projectile_in_flight and not training_result_shown:
			training_result_shown = true
			if training.phase == "complete" and saved_lesson != training.lesson_id:
				progress.complete(training.lesson_id)
				saved_lesson = training.lesson_id
				if progress.save_to(progress_path) != OK: training_notice = "Lesson completed for this session; progress save failed"
			_mark_latest()
			open_training()
	elif not scene.remote_mode and scene.session.playback == null and not scene.projectile_in_flight:
		var key := _turn_key()
		if key != last_turn:
			last_turn = key
			if scene.preferences.autosave and scene.runner.state.status == "playing":
				var result: Dictionary = autosave.save(scene.runner,scene.session.options,scene.player_velocities)
				if not result.ok: scene._session_message("Autosave failed: " + result.reason)
			if scene.preferences.hotseat_handoff and scene.session.options.mode == "hotseat" and scene.runner.state.status == "playing":
				handoff = true
				scene._close_overlays()
				scene.match_panels.handoff_panel.get_meta("box").get_child(0).text = "Pass control to " + scene.runner.state.get_active_player().display_name
				scene.match_panels.handoff_panel.show()
				scene._refresh_menu_state()
		if scene.runner.state.status == "ended" and series.active:
			series.record_result(match_epoch,scene.runner.state.winner_team)
			scene.match_panels.end_label.text += "\nSeries A %s : %s B%s" % [series.scores[1],series.scores[2]," — complete" if series.completed else ""]
	for child in scene.match_panels.end_panel.get_meta("box").get_children():
		if child is Button and child.text == "Next round in series":
			child.disabled = scene.remote_mode or not series.next_round() or scene.runner.state.status != "ended"
	_update_focus()
func _update_focus() -> void:
	var current: Control = null
	if confirmation.visible: current = confirmation
	elif training_panel.visible: current = training_panel
	elif scene.settings_panel.visible: current = scene.settings_panel
	else:
		for panel in scene.match_panels.panels:
			if panel.visible: current = panel; break
	if current != last_overlay:
		if last_overlay != null: focus.close(last_overlay)
		last_overlay = current
		if current != null: focus.open(current)
func _mark_latest() -> void:
	var entries: Array = training.attempts.entries()
	if entries.is_empty() or marker_count == entries.size(): return
	marker_count = entries.size()
	var marker := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.3
	mesh.height = 0.6
	marker.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.YELLOW
	marker.material_override = material
	scene.add_child(marker)
	marker.position = entries.back().impact
	markers.append(marker)
	while markers.size() > 10: markers.pop_front().queue_free()
func _clear_markers() -> void:
	for marker in markers:
		if is_instance_valid(marker): marker.queue_free()
	markers.clear()
	marker_count = 0
