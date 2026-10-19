extends RefCounted
const Event = preload("res://scripts/core/competition/competition_event.gd")
const Config = preload("res://scripts/core/competition/competition_config.gd")
const Store = preload("res://scripts/core/competition/competition_store.gd")
const Session = preload("res://scripts/core/replay/session_store.gd")
var scene: Node
var path: String
var event := Event.new()
var panel: PanelContainer
var team_label: Label
var return_button: Button
var fixture_runner: RefCounted
var fixture_token := {}
var live := {}
var dirty := false
var _internal_launch := false
var _revision := 0
var _focus = preload("res://scripts/client/ui/panel_focus_controller.gd").new()
func _init(owner_scene: Node, save_path: String = Store.DEFAULT_PATH) -> void:
	scene = owner_scene
	path = save_path
	event.create(Config.defaults())
func setup() -> void:
	panel = preload("res://scripts/client/competition/competition_panel.gd").new()
	scene.get_node("Hud").add_child(panel)
	panel.create_requested.connect(create)
	panel.rename_requested.connect(rename_entrant)
	panel.play_requested.connect(launch)
	panel.save_requested.connect(save)
	panel.resume_requested.connect(func():
		if not live.is_empty() or event.snapshot().frozen:
			_confirm("resume","Replace current competition with the saved version?",{})
		else: resume())
	panel.correction_requested.connect(func(id,winner): _confirm("correct","Replace the result of "+id+"?",{"id":id,"winner":winner}))
	panel.abandon_requested.connect(func(): _confirm("abandon","Abandon the current attempt? No result will be awarded.",{}))
	panel.exit_requested.connect(func():
		if not live.is_empty(): _confirm("exit","Return to your original match? Any unfinished fixture will be abandoned.",{})
		else: close())
	panel.close_requested.connect(close)
	panel.copy_report_requested.connect(func():
		DisplayServer.clipboard_set(event.report())
		panel.set_status("Competition report copied"))
	panel.confirmed.connect(_confirmed)
	team_label = Label.new()
	team_label.name = "CompetitionTeams"
	team_label.position = Vector2(30,240)
	team_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scene.get_node("Hud").add_child(team_label)
	return_button = Button.new()
	return_button.name = "BackToCompetition"
	return_button.text = "Back to competition"
	return_button.position = Vector2(30,275)
	scene.get_node("Hud").add_child(return_button)
	return_button.pressed.connect(open)
	team_label.hide()
	return_button.hide()
	_refresh()
func _workshop_active() -> bool:
	var workshop = scene.get("workshop")
	return workshop!=null and workshop.is_active()
func _unavailable() -> String:
	if _workshop_active(): return "Close Arena Workshop before opening competition"
	if scene.remote_mode: return "Competition is available only offline"
	if scene.session.playback!=null: return "Return from replay before opening competition"
	if scene.projectile_in_flight: return "Wait for the projectile to finish"
	if scene.workflows!=null and scene.workflows.training.active: return "Exit training before opening competition"
	return ""
func _failure(reason: String) -> Dictionary:
	if panel!=null: panel.set_status(reason,true)
	return Config.failure(reason)
func open() -> bool:
	var reason := _unavailable()
	if not reason.is_empty(): _failure(reason); return false
	scene._close_overlays()
	_refresh()
	panel.show()
	panel.move_to_front()
	panel.fit(scene.get_viewport().get_visible_rect().size,scene.preferences.hud_scale)
	_focus.open(panel)
	scene._refresh_menu_state()
	return true
func close() -> void:
	if panel!=null:
		panel.hide()
		_focus.close(panel)
	scene._refresh_menu_state()
func close_overlays() -> void:
	if panel!=null:
		panel.hide()
		panel.confirm_box.hide()
		_focus.close(panel)
func overlays_open() -> bool: return panel!=null and panel.visible
func blocks_external_action() -> bool: return not live.is_empty() and not _internal_launch
func is_active() -> bool: return blocks_external_action()
func is_internal_launch() -> bool: return _internal_launch
func _refresh() -> void:
	if panel==null: return
	panel.refresh({"snapshot":event.snapshot(),"fixtures":event.fixtures(),"ready":event.ready_ids(),"standings":event.standings(),"champion":event.champion(),"complete":event.is_complete(),"report":event.report(),"dirty":dirty})
	if dirty: panel.set_status("Unsaved competition changes")
func _changed() -> void:
	_revision += 1
	dirty = true
	_refresh()
func create(config: Dictionary) -> Dictionary:
	if not event.snapshot().active.is_empty(): return _failure("Abandon or finish the current match before replacing competition")
	var checked := Config.validate(config)
	if not checked.ok: return _failure(checked.reason)
	if event.snapshot().frozen:
		_confirm("create","Replace this competition with a new draft?",{"config":checked.config})
		return {"ok":true,"confirmation":true}
	var result := event.update_draft(checked.config)
	if result.ok:
		_changed()
		panel.show_tab("Schedule")
	else: _failure(result.reason)
	return result
func rename_entrant(id: String, name: String) -> Dictionary:
	var result := event.rename_entrant(id,name)
	if result.ok:
		_changed()
		_update_labels()
	else: _failure(result.reason)
	return result
func _capture_live() -> void:
	if not live.is_empty(): return
	live = {"runner":scene.runner,"recorder":scene.session.recorder,"options":scene.session.options.duplicate(true),"velocities":scene.player_velocities.duplicate(true),"series":scene.workflows.series,"series_config":scene.workflows.series_config.duplicate(true),"match_epoch":scene.workflows.match_epoch,"handoff":scene.workflows.handoff}
	scene.workflows.series = preload("res://scripts/client/session/match_series.gd").new()
	scene.workflows.series_config = {}
	scene.workflows.handoff = false
func launch(id: String) -> Dictionary:
	var reason := _unavailable()
	if not reason.is_empty(): return _failure(reason)
	if not event.ready_ids().has(id): return _failure("This match is not ready")
	# Persist the ready event first: failed preflight never replaces the live runner.
	var preflight := Store.save(path,event)
	if not preflight.ok: return _failure(preflight.reason)
	var candidate := Event.new()
	candidate.restore(event.snapshot())
	var launched := candidate.launch(id)
	if not launched.ok: return _failure(launched.reason)
	_capture_live()
	_internal_launch = true
	var cfg: Dictionary = launched.config
	var started: bool = scene.start_local_match(launched.fixture.map,cfg.count,cfg.preset,"hotseat","normal",1)
	_internal_launch = false
	if not started:
		if fixture_runner==null: return_to_live()
		return _failure("The selected fixture could not be created")
	event = candidate
	fixture_runner = scene.runner
	fixture_token = launched.token
	_changed()
	_update_labels()
	panel.hide()
	return_button.hide()
	close_overlays()
	scene._refresh_menu_state()
	var saved := save()
	if not saved.ok: scene._session_message("Fixture started; competition remains unsaved: "+saved.reason)
	return {"ok":true,"token":fixture_token.duplicate(),"saved":saved.ok}
func _snapshot_match() -> Dictionary:
	var active: Dictionary = event.snapshot().active
	if active.is_empty(): return {"ok":true,"match":{}}
	if fixture_runner==null or fixture_runner!=scene.runner or active!=fixture_token: return Config.failure("Active fixture is not attached to the current match")
	var encoded := Session.encode(scene.runner,scene.session.options,scene.player_velocities)
	if not encoded.ok: return encoded
	return {"ok":true,"match":{"token":fixture_token.duplicate(),"payload":encoded.payload}}
func save() -> Dictionary:
	var reason := _unavailable()
	if not reason.is_empty(): return _failure(reason)
	var match_result := _snapshot_match()
	if not match_result.ok: return _failure(match_result.reason)
	var result := Store.save(path,event,match_result.match)
	if result.ok:
		dirty = false
		panel.set_status("Competition saved")
	else:
		dirty = true
		_failure(result.reason)
	return result
func resume() -> Dictionary:
	var reason := _unavailable()
	if not reason.is_empty(): return _failure(reason)
	var loaded := Store.load(path)
	if not loaded.ok: return _failure(loaded.reason)
	# No mutation, including live-context capture, precedes complete file validation.
	var reopen_panel: bool = panel.visible
	if not loaded.match.is_empty():
		_capture_live()
		_internal_launch = true
		scene._replace_local_runner(loaded.match.runner)
		_internal_launch = false
		scene.session.options = loaded.match.options
		scene.player_velocities = loaded.match.velocities
		scene.session.new_recording()
		scene.workflows.on_started()
		fixture_runner = scene.runner
		fixture_token = loaded.match.token
	else:
		# A draft has no runner of its own. Restore the retained live match before
		# dropping the old fixture identity; do not overwrite the file being resumed.
		if not live.is_empty(): return_to_live(false)
		fixture_runner = null
		fixture_token = {}
	event = loaded.event
	_revision += 1
	dirty = false
	panel.apply_configuration(event.snapshot().config)
	_refresh()
	panel.show_tab("Schedule")
	if reopen_panel: panel.show()
	scene._refresh_menu_state()
	panel.set_status("Saved competition verified and resumed")
	_update_labels()
	return {"ok":true}
func _update_labels() -> void:
	if team_label==null: return
	if fixture_runner==null or fixture_runner!=scene.runner:
		team_label.hide()
		return
	var id: String = fixture_token.get("fixture_id","")
	var fixture := event.fixture_by_id(id)
	if fixture.is_empty(): return
	team_label.text = "A / Blue / Team 1: %s\nB / Red / Team 2: %s" % [event.name_for(fixture.a),event.name_for(fixture.b)]
	team_label.size.x = maxf(200,scene.get_viewport().get_visible_rect().size.x-60)
	team_label.visible = not scene.menu_open
func update(_delta: float) -> void:
	if panel==null: return
	if panel.visible: panel.fit(scene.get_viewport().get_visible_rect().size,scene.preferences.hud_scale)
	_update_labels()
	if fixture_runner==null or fixture_runner!=scene.runner or scene.remote_mode or scene.session.playback!=null or scene.projectile_in_flight: return
	if scene.runner.state.status=="ended":
		if not event.snapshot().active.is_empty():
			var result := event.record(fixture_token,scene.runner.state.winner_team)
			if result.ok:
				_changed()
				var saved := save()
				if not saved.ok: scene._session_message("Result recorded; save failed: "+saved.reason)
		return_button.visible = not panel.visible
	else: return_button.hide()
func abandon_active() -> Dictionary:
	if scene.projectile_in_flight: return _failure("Wait for the projectile to finish")
	var result := event.abandon(event.snapshot().active)
	if result.ok:
		fixture_runner = null
		fixture_token = {}
		return_button.hide()
		team_label.hide()
		_changed()
		save()
		return_to_live()
		open()
	else: _failure(result.reason)
	return result
func return_to_live(persist_abandon := true) -> Dictionary:
	if scene.projectile_in_flight: return _failure("Wait for the projectile to finish")
	if live.is_empty(): close(); return {"ok":true}
	if not event.snapshot().active.is_empty():
		var abandoned := event.abandon(event.snapshot().active)
		if not abandoned.ok: return abandoned
		_changed()
		if persist_abandon: save()
	var previous := live
	_internal_launch = true
	scene._replace_local_runner(previous.runner)
	_internal_launch = false
	scene.session.options = previous.options
	scene.player_velocities = previous.velocities
	scene.session.recorder = previous.recorder
	scene.workflows.series = previous.series
	scene.workflows.series_config = previous.series_config
	scene.workflows.match_epoch = previous.match_epoch
	scene.workflows.handoff = previous.handoff
	scene.workflows.last_live_runner = previous.runner
	scene.workflows.last_turn = "%s/%s" % [previous.runner.state.generation,previous.runner.state.turn_id]
	live = {}
	fixture_runner = null
	fixture_token = {}
	team_label.hide()
	return_button.hide()
	scene._close_overlays()
	return {"ok":true}
func _confirm(action: String, text: String, payload: Dictionary) -> void:
	var token := payload.duplicate(true)
	token.revision = _revision
	panel.present_confirmation(action,text,token)
func _confirmed(action: String, payload: Dictionary) -> void:
	if payload.get("revision",-1)!=_revision: _failure("Competition changed; request the action again"); return
	match action:
		"create":
			var result := event.create(payload.config)
			if result.ok:
				fixture_runner = null
				fixture_token = {}
				_changed()
				panel.show_tab("Schedule")
			else: _failure(result.reason)
		"correct":
			var result := event.correct(payload.id,payload.winner)
			if result.ok: _changed()
			else: _failure(result.reason)
		"abandon": abandon_active()
		"exit": return_to_live()
		"resume": resume()
