extends SceneTree
const Replay = preload("res://scripts/core/replay/match_replay.gd")
var failures := 0
var checks := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void: call_deferred("run")
func press(window, id: String) -> void: window.buttons[id].pressed.emit()
func run() -> void:
	if "--workshop-visual" in OS.get_cmdline_user_args():
		await visual_smoke()
		return
	if not FileAccess.file_exists("res://scripts/client/workshop/workshop_workflows.gd"):
		check(false,"W36 Workshop native window/controller must exist")
		quit(1)
		return
	root.size = Vector2i(1280,720)
	var scene = load("res://scenes/debug/VoxelDebug.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_physics_process(false)
	var workflow = scene.get("workshop")
	if workflow == null:
		workflow = load("res://scripts/client/workshop/workshop_workflows.gd").new(scene)
		workflow.setup()
	var original = scene.runner
	var recorder = scene.session.recorder
	var hash_before: String = Replay.state_hash(original)
	scene.player_velocities["blue_1"] = Vector3(0.125,2.5,-0.25)
	scene.weapon_by_player["blue_1"] = 2
	scene.selected_weapon_id = 2
	scene.workflows.handoff = true
	scene.match_panels.handoff_panel.show()
	scene._refresh_menu_state()
	var mouse_before := Input.mouse_mode
	check(workflow.open(),"W44 opens local workshop")
	check(not scene.workflows.handoff and not scene.match_panels.handoff_panel.visible,"W47 pending handoff suspended throughout Workshop")
	var gravity_before: float = scene.rules.base_gravity
	scene.debug_panel.show()
	scene._adjust_debug_gravity(1.0)
	check(scene.rules.base_gravity==gravity_before,"W49 root debug shortcut cannot mutate retained live rules")
	var w = workflow.window
	var d = workflow.document
	await process_frame
	check(w.visible and w.force_native and w.tabs.get_tab_count() == 3,"W36 native window and three tabs")
	check(scene.local_paused and Replay.state_hash(original) == hash_before,"W44 editor pauses unchanged original")
	for kind in ["boxes","carves","spawns"]:
		w.choose_kind(kind)
		check(w.buttons.has("add") and w.buttons.has("apply") and w.buttons.has("duplicate") and w.buttons.has("delete"),"W36 all CRUD actions %s" % kind)
	w.choose_kind("boxes")
	w.fields.position[0].value = 5
	w.fields.position[1].value = 1
	w.fields.position[2].value = 5
	w.fields.extent[0].value = 3
	w.fields.extent[1].value = 3
	w.fields.extent[2].value = 3
	w.fields.label.text = "UI cover"
	press(w,"add")
	check(d.snapshot().boxes.size() == 2 and d.snapshot().boxes[1].position == [5,1,5],"W06 UI add box")
	w.select_entry(0)
	check(w.fields.extent[0].value == 32 and w.fields.position[0].value == 0,"W37 selection fills actual values")
	w.select_entry(1)
	check(w.fields.label.text == "UI cover" and w.preview.selection.index == 1,"W37 inspector and preview selection")
	w.fields.position[0].value = 6
	w.fields.extent[0].value = 2
	press(w,"apply")
	check(d.snapshot().boxes[1].position[0] == 6 and d.snapshot().boxes[1].size[0] == 2,"W07 UI apply transform")
	w.fields.material.select(2)
	w.fields.custom_health.button_pressed = true
	w.fields.health.value = 77
	press(w,"apply")
	check(d.snapshot().boxes[1].material == "stone" and d.validate().arena.world.get_health(Vector3i(6,1,5)) == 77,"W08 W09 UI material health")
	press(w,"duplicate")
	check(d.snapshot().boxes.size() == 3,"W11 UI duplicate box")
	press(w,"delete")
	press(w,"undo")
	check(d.snapshot().boxes.size() == 3,"W12 W21 UI delete undo")
	press(w,"redo")
	check(d.snapshot().boxes.size() == 2,"W22 UI redo")
	check(w.buttons.undo.disabled == not d.can_undo() and w.buttons.redo.disabled == not d.can_redo(),"W23 history button availability")
	w.metadata.map_name.text = "UI arena"
	w.metadata.theme.text = "ui_theme"
	w.metadata.id.text = "ui_arena"
	press(w,"metadata")
	check(d.snapshot().id == "ui_arena" and d.snapshot().display_name == "UI arena" and d.snapshot().theme == "ui_theme","W03 W04 UI metadata")
	check(w.title.contains("*"),"W24 dirty title")
	w.choose_kind("carves")
	w.fields.position[0].value = 6
	w.fields.position[1].value = 2
	w.fields.position[2].value = 5
	w.fields.radius.value = 1
	press(w,"add")
	check(d.snapshot().carves.size() == 1,"W14 UI carve")
	w.fields.radius.value = 2
	press(w,"apply")
	check(d.snapshot().carves[0].radius == 2,"W15 UI radius")
	press(w,"duplicate")
	press(w,"delete")
	check(d.snapshot().carves.size() == 1,"W16 UI duplicate/delete carve")
	w.choose_kind("spawns")
	w.fields.position[0].value = 10
	w.fields.position[1].value = 1
	w.fields.position[2].value = 10
	w.fields.team.select(0)
	w.fields.slot.value = 1
	w.fields.yaw.value = 90
	press(w,"add")
	check(d.snapshot().spawns.size() == 3 and d.snapshot().spawns[2].yaw == 90,"W17 W18 UI spawn yaw")
	w.fields.team.select(1)
	w.fields.slot.value = 1
	press(w,"apply")
	check(d.snapshot().spawns[2].team == 2,"W19 UI spawn team")
	press(w,"duplicate")
	check(not d.validate().ok,"W20 duplicate spawn error visible")
	press(w,"delete")
	press(w,"validate")
	check(w.report.text.contains("Valid"),"W31 UI validation report")
	w.layer.value = 1
	check(w.preview.layer == 1,"W39 layer control")
	check(w.preview.material_at(Vector3i(6,2,5)) == d.validate().arena.world.get_material_id(Vector3i(6,2,5)),"W38 actual voxel preview")
	w.preview.size = Vector2(500,300)
	w.preview.fit()
	check(w.preview.map_rect().size.x <= 500 and w.preview.map_rect().size.y <= 300,"W40 fit bounds")
	w.preview.set_zoom(99)
	check(w.preview.zoom <= 4,"W40 zoom bounded")
	w.preview.fit()
	var cell_point: Vector2 = w.preview.map_rect().position + Vector2(10.5,10.5)*w.preview.cell_size()
	check(w.preview.cell_at_point(cell_point) == Vector3i(10,1,10) and w.preview.cell_at_point(Vector2(-10,-10)) == null,"W41 pixel to voxel mapping")
	var revision: int = d.revision
	w.preview.cell_selected.emit(Vector3i(12,1,13))
	check(w.fields.position[0].value == 12 and w.fields.position[2].value == 13 and d.revision == revision,"W41 click fills form without mutating")
	check(w.preview.spawn_markers().size() == 3 and w.preview.spawn_markers()[0].color != w.preview.spawn_markers()[1].color,"W42 team markers")
	var previous_world = w.preview.world
	d.remove_entry("boxes",0)
	w.refresh()
	check(w.preview.stale and w.preview.world == previous_world and w.preview.status_text().contains("Stale"),"W43 retains last valid preview")
	check(not workflow.start_playtest(2) and scene.runner == original,"W34 invalid playtest retains original")
	d.undo()
	w.refresh()
	var tmp := "/private/tmp" if OS.get_name() == "macOS" else "/tmp"
	var path := tmp.path_join("terrablast-workshop-ui-%d.toml" % OS.get_process_id())
	check(w.save_path(path) and not d.is_dirty(),"W26 W27 UI save")
	d.set_metadata({"name":"Unsaved"})
	w.refresh()
	w.request_action("new")
	check(w.confirmation.visible,"W30 dirty prompt shown")
	w.resolve_pending("cancel")
	check(d.snapshot().display_name == "Unsaved" and w.visible,"W30 cancel retains edits")
	w.request_action("new")
	w.resolve_pending("save")
	check(d.snapshot().display_name == "Local Arena","W30 save then new")
	check(w.import_path(path) and d.snapshot().display_name == "Unsaved" and not d.can_undo(),"W25 import resets history")
	d.set_metadata({"name":"Dirty again"})
	var import_before: int = d.revision
	check(not w.import_path(path+".missing") and d.revision == import_before and d.is_dirty(),"W35 failed import retains draft")
	check(not w.save_path("res://maps/twin_forts.toml") and d.is_dirty(),"W29 UI protects resources")
	press(w,"save")
	check(not d.is_dirty(),"W27 save uses current path")
	var history_before: int = d.history_summary().undo
	var focus_owner = w.gui_get_focus_owner()
	if focus_owner != null: focus_owner.release_focus()
	var key := InputEventKey.new()
	key.pressed = true
	key.ctrl_pressed = true
	key.keycode = KEY_Z
	w.window_input.emit(key)
	check(d.history_summary().undo == history_before-1,"W50 Ctrl Z document undo")
	key.shift_pressed = true
	w.window_input.emit(key)
	check(d.history_summary().undo == history_before,"W50 Ctrl Shift Z document redo")
	key.shift_pressed = false
	key.keycode = KEY_S
	w.window_input.emit(key)
	check(not d.is_dirty(),"W50 Ctrl S saves current path")
	d.set_metadata({"theme":"keyboard-close"})
	w.close_requested.emit()
	check(w.confirmation.visible and w.visible,"W50 OS close uses dirty prompt")
	w.resolve_pending("cancel")
	w.save_path(path)
	check(workflow.start_playtest(2),"W45 playtest starts")
	check(not scene.workflows.handoff and not scene.workflows.blocked() and scene._can_control(),"W47 original handoff cannot block playtest controls")
	check(scene.runner != original and scene.runner.state.players.size() == 2 and not w.visible and workflow.return_panel.visible,"W45 separate runner and return control")
	check(workflow.blocks_persistence() and workflow.is_active() and workflow.is_playtesting(),"W49 active test blocks persistence")
	if scene.get("workshop") != null:
		check(not scene.session.can_archive(),"W49 session archive guard")
		check(not scene.start_local_match("twin_forts",2,"classic"),"W49 map replacement guard")
	var initial_test: String = Replay.state_hash(scene.runner)
	scene.runner.world.set_voxel(Vector3i(0,0,0),0,0)
	check(workflow.restart_playtest() and Replay.state_hash(scene.runner) == initial_test,"W48 restart from document")
	var test_runner = scene.runner
	var active = scene.runner.state.get_active_player()
	var command = load("res://scripts/core/turns/player_action_command.gd").new()
	command.player_id = active.player_id
	command.turn_id = scene.runner.state.turn_id
	command.generation = scene.runner.state.generation
	command.weapon_id = 1
	command.aim_direction = Vector3(1,0.3,1).normalized()
	command.shot_power = 1
	var shot: Dictionary = scene.session.recorder.submit(scene.runner,command)
	check(shot.ok,"W46 actual playtest shot accepted")
	if shot.ok: scene._play_result(shot)
	check(scene.projectile_in_flight,"W46 shot playback active before return")
	scene.runner.world.set_voxel(Vector3i(0,0,0),0,0)
	workflow.return_button.pressed.emit()
	check(w.visible and scene.runner == original and workflow.is_active() and not workflow.is_playtesting(),"W46 return opens editor and restores original")
	check(not scene.projectile_in_flight and scene.active_projectile == null,"W46 return cancels test projectile")
	check(d.snapshot().display_name == "Dirty again" and d.can_undo() and test_runner != scene.runner,"W46 document and undo retained")
	check(scene.session.recorder == recorder and Replay.state_hash(scene.runner) == hash_before and scene.player_velocities.blue_1 == Vector3(0.125,2.5,-0.25),"W47 exact live runner recorder velocity restored")
	check(scene.selected_weapon_id == 2 and scene.weapon_by_player.blue_1 == 2,"W47 weapon selection restored")
	check(workflow.close() and not workflow.is_active() and Input.mouse_mode == mouse_before,"W50 close restores mouse")
	check(scene.workflows.handoff and scene.match_panels.handoff_panel.visible,"W47 original pending handoff restored on final exit")
	scene.workflows.handoff = false
	scene.match_panels.handoff_panel.hide()
	for blocked in ["remote","projectile","replay","training"]:
		match blocked:
			"remote": scene.remote_mode = true
			"projectile": scene.projectile_in_flight = true
			"replay": scene.session.playback = RefCounted.new()
			"training": scene.workflows.training.active = true
		check(not workflow.open() and not workflow.blocked_reason().is_empty(),"W44 blocked entry %s" % blocked)
		scene.remote_mode = false
		scene.projectile_in_flight = false
		scene.session.playback = null
		scene.workflows.training.active = false
	DirAccess.remove_absolute(path)
	workflow.shutdown()
	scene.queue_free()
	await process_frame
	print("Workshop integration: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func visual_smoke() -> void:
	var d = load("res://scripts/core/workshop/workshop_document.gd").new()
	d.add_entry("boxes",{"position":[6,1,7],"size":[4,4,10],"material":"stone","name":"North cover"})
	d.add_entry("boxes",{"position":[20,1,15],"size":[5,3,7],"material":"metal","name":"Bunker"})
	d.add_entry("carves",{"position":[8,2,11],"shape":"sphere","radius":2})
	d.select("boxes",1)
	var w = load("res://scripts/client/workshop/workshop_window.gd").new()
	root.add_child(w)
	w.setup(d)
	w.layer.value = 1
	w.present()
	w.set_notice("Native window smoke • independent voxel slice and editable stone cover")
	await create_timer(45).timeout
	w.queue_free()
	await process_frame
	quit(0)
