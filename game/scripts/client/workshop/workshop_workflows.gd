extends RefCounted
## Retains the original live match throughout editing and disposable local playtests.
const Factory = preload("res://scripts/core/rules/match_factory.gd")
const CONTEXT_FIELDS := ["player_velocities","player_walk_phases","weapon_by_player","selection_player","selected_weapon_id","end_presented_key","orbit_yaw","camera_pitch","camera_distance","camera_focus_position","camera_visual_yaw","camera_transition_initialized","mouse_look_enabled","local_paused","menu_open"]
var scene: Node
var document = preload("res://scripts/core/workshop/workshop_document.gd").new()
var window: Window
var return_panel: PanelContainer
var return_button: Button
var restart_button: Button
var _active := false
var _playing := false
var _live := {}
var _last_reason := ""
var _test_count := 2
var _test_definition: RefCounted
func _init(owner_scene: Node) -> void: scene = owner_scene
func setup() -> void:
	window = preload("res://scripts/client/workshop/workshop_window.gd").new()
	scene.add_child(window)
	window.setup(document)
	window.playtest_requested.connect(start_playtest)
	window.exit_requested.connect(_finish_close)
	return_panel = PanelContainer.new()
	return_panel.name = "WorkshopPlaytestControls"
	return_panel.position = Vector2(20,280)
	var row := HBoxContainer.new()
	return_panel.add_child(row)
	var label := Label.new()
	label.text = "LOCAL ARENA PLAYTEST"
	row.add_child(label)
	return_button = Button.new()
	return_button.text = "Return to Workshop"
	return_button.pressed.connect(return_to_editor)
	row.add_child(return_button)
	restart_button = Button.new()
	restart_button.text = "Restart test"
	restart_button.pressed.connect(restart_playtest)
	row.add_child(restart_button)
	scene.get_node("Hud").add_child(return_panel)
	return_panel.hide()
func is_active() -> bool: return _active
func is_playtesting() -> bool: return _active and _playing
func overlays_open() -> bool: return _active and not _playing
func blocks_persistence() -> bool: return _active
func blocked_reason() -> String: return _last_reason
func _entry_reason() -> String:
	if scene.remote_mode: return "Arena Workshop is available only in a local match"
	if scene.projectile_in_flight: return "Wait until the current shot finishes"
	if scene.session.playback != null: return "Return from replay before opening Workshop"
	var competition = scene.get("competition")
	if competition != null and competition.is_active(): return "Finish the competition before opening Workshop"
	if scene.workflows != null and scene.workflows.training.active: return "Return from training before opening Workshop"
	return ""
func open() -> bool:
	if _active:
		if _playing: return_to_editor()
		else: window.present()
		return true
	_last_reason = _entry_reason()
	if not _last_reason.is_empty():
		scene._session_message(_last_reason)
		return false
	_live = {"runner":scene.runner,"recorder":scene.session.recorder,"options":scene.session.options.duplicate(true),"bot":scene.session.bot,"bot_key":scene.session.bot_key,"handoff":scene.workflows.handoff,"mouse":Input.mouse_mode,"fields":{},"panels":[]}
	for key in CONTEXT_FIELDS:
		var value: Variant = scene.get(key)
		_live.fields[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	# Opening from an existing menu preserves that menu on final return.
	_collect_visible_panels(scene.get_node("Hud"),_live.panels)
	if scene.backend_menu != null and scene.backend_menu.panel.visible: _live.panels.append(weakref(scene.backend_menu.panel))
	# Handoff belongs to the retained match, never to a disposable playtest.
	scene.workflows.handoff = false
	scene._close_overlays()
	scene._cancel_aim()
	_active = true
	_playing = false
	scene.session.bot = null
	window.present()
	scene._refresh_menu_state()
	# Also works when instantiated independently before the scene hook is attached.
	scene.local_paused = true
	scene.menu_open = true
	scene.mouse_look_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	return true
func _collect_visible_panels(node: Node, result: Array) -> void:
	for child in node.get_children():
		if child is PanelContainer and child.visible:
			result.append(weakref(child))
		else: _collect_visible_panels(child,result)
func start_playtest(count: int) -> bool:
	if not _active or _playing: return false
	var validation: Dictionary = document.validate()
	if not validation.ok or count not in validation.supported_counts:
		window.set_notice("Fix validation errors and choose a supported player count")
		window.refresh()
		return false
	var candidate := Factory.from_definition(document.snapshot(),count,"classic","classic")
	if candidate == null:
		window.set_notice("Cannot create playtest from this arena")
		return false
	_test_count = count
	_test_definition = document.snapshot()
	window.hide()
	_playing = true
	scene._replace_local_runner(candidate)
	scene.session.options = {"mode":"hotseat","difficulty":"normal","human_team":1}
	scene.session.new_recording()
	scene._close_overlays()
	return_panel.show()
	scene._refresh_menu_state()
	scene.local_paused = false
	scene.menu_open = false
	scene.mouse_look_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	return true
func restart_playtest() -> bool:
	if not is_playtesting() or _test_definition == null: return false
	var candidate := Factory.from_definition(_test_definition,_test_count,"classic","classic")
	if candidate == null: return false
	scene._replace_local_runner(candidate)
	scene.session.new_recording()
	scene._close_overlays()
	return_panel.show()
	return true
func _restore_live() -> void:
	if _live.is_empty(): return
	scene._replace_local_runner(_live.runner)
	scene.session.recorder = _live.recorder
	scene.session.options = _live.options.duplicate(true)
	scene.session.bot = _live.bot
	scene.session.bot_key = _live.bot_key
	for key in _live.fields:
		var value: Variant = _live.fields[key]
		scene.set(key,value.duplicate(true) if value is Dictionary or value is Array else value)
	scene._update_camera_transform()
	scene._update_hud()
func return_to_editor() -> void:
	if not is_playtesting(): return
	_playing = false
	return_panel.hide()
	_restore_live()
	window.present()
	scene._refresh_menu_state()
	scene.local_paused = true
	scene.menu_open = true
	scene.mouse_look_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
func close() -> bool:
	if not _active: return true
	if _playing: return_to_editor()
	if document.is_dirty():
		window.request_action("close")
		return false
	window.hide()
	_finish_close()
	return true
func _finish_close() -> void:
	if not _active: return
	window.hide()
	return_panel.hide()
	_active = false
	_playing = false
	_restore_live()
	scene.workflows.handoff = _live.handoff
	for reference in _live.get("panels",[]):
		var panel = reference.get_ref()
		if is_instance_valid(panel): panel.show()
	scene._refresh_menu_state()
	for key in ["local_paused","menu_open","mouse_look_enabled"]: scene.set(key,_live.fields[key])
	Input.mouse_mode = _live.mouse
	_live.clear()
	_test_definition = null
func shutdown() -> void:
	_active = false
	_playing = false
	_live.clear()
	_test_definition = null
	if is_instance_valid(window): window.queue_free()
	if is_instance_valid(return_panel): return_panel.queue_free()
