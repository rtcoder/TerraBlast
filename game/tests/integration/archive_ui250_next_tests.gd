extends SceneTree
var failures := 0
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	check(ResourceLoader.exists("res://scripts/client/session/archive_workflows.gd"),"Archive UI coordinator exists")
	if failures: quit(1)
	else: call_deferred("run")
func run() -> void:
	root.size = Vector2i(800,600)
	var scene = load("res://scenes/debug/VoxelDebug.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_physics_process(false)
	var temporary_root := "/private/tmp" if OS.get_name()=="macOS" else "/tmp"
	var base := temporary_root.path_join("archive-ui250-%d" % OS.get_process_id())
	var library = load("res://scripts/core/storage/local_archive_library.gd").new(base)
	scene.library = library
	var ui = scene.archive_ui
	ui.preferences = load("res://scripts/client/session/library_preferences.gd").new(base + "-prefs.json")
	# Scene startup may have read real preferences; isolate the controls as well as storage.
	ui._restore_controls = true
	ui.search.text = ""
	ui.sort_select.select(0)
	scene.library_panel.filter.select(0)
	ui.favorites_only.set_pressed_no_signal(false)
	ui._restore_controls = false
	var factory = load("res://scripts/core/rules/match_factory.gd")
	var runner = factory.create_match(2,"res://maps/ballistics_range.toml")
	var recorder = load("res://scripts/core/replay/match_replay.gd").new()
	recorder.capture(runner)
	for i in range(70): recorder.tick(runner,0.01)
	for unused in range(2):
		var command = load("res://scripts/core/turns/player_action_command.gd").new()
		command.player_id = runner.state.get_active_player().player_id
		command.turn_id = runner.state.turn_id
		command.generation = runner.state.generation
		command.weapon_id = 1
		command.aim_direction = Vector3.UP
		command.shot_power = 1
		check(recorder.submit(runner,command).ok,"Recorded shot fixture")
		recorder.tick(runner,0.01)
	var saved: Dictionary = library.save_replay("Żółć replay " + "ą".repeat(36),recorder,runner)
	var checkpoint: Dictionary = library.save_session("Checkpoint",runner,scene.session.options)
	check(saved.ok and checkpoint.ok,"UI fixtures saved")
	scene._toggle_library()
	check(ui.page_size==20 and scene.library_panel.visible,"Library page size20")
	ui.search.text = "żółć"
	ui.search.text_changed.emit(ui.search.text)
	check(scene.library_panel.entries.item_count==1,"Search UI filters Unicode")
	scene.library_panel.entries.select(0)
	scene.library_panel.entries.item_selected.emit(0)
	check(ui.details.text.contains(saved.id) and ui.details.text.contains("UTC"),"Visible entry details")
	ui.toggle_favorite()
	check(ui.preferences.favorites.has(saved.id),"Favorite toggled independently")
	ui.search.text = ""
	ui.search.text_changed.emit("")
	ui.favorites_only.button_pressed = true
	check(scene.library_panel.entries.item_count==1,"Favorites filter")
	ui.favorites_only.button_pressed = false
	ui.show_diagnostics()
	check(ui.diagnostics_status.text.contains("2"),"Diagnostics count")
	var live = scene.runner
	var hash_before: String = load("res://scripts/core/replay/match_replay.gd").state_hash(live)
	check(scene._library_load(saved.id),"Open named replay")
	ui.begin_analysis()
	ui.update(0.016)
	check(ui.analyzer.index==32,"UI analysis budget32")
	var current_job = ui.analyzer
	ui.begin_analysis()
	check(ui.analyzer==current_job and ui.analyzer.index==32,"Double Analyze cannot replace running job")
	check(ui.operation_buttons[0].disabled and not ui.cancel_analysis_button.disabled,"Analysis disables operations but enables Cancel")
	ui.cancel_analysis()
	check(ui.analyzer.cancelled,"Cancel analysis")
	ui.begin_analysis()
	for i in range(4): ui.update(0.016)
	check(ui.report.get("ok",false) and ui.statistics.text.contains("Shots"),"Completed replay statistics")
	check(ui.shots.item_count==2 and ui.turns.item_count==3,"Shot and turn tables populated")
	ui.shots.select(0)
	ui.shots.item_selected.emit(0)
	check(scene.session.playback.index==71 and ui.action_label.text.contains("Bazooka"),"Shot row seeks exact action and description")
	ui.seek_index(scene.session.playback.action_count)
	var key := InputEventKey.new()
	key.keycode = KEY_LEFT
	key.ctrl_pressed = true
	key.pressed = true
	check(ui.handle_input(key) and scene.session.playback.index==73,"Keyboard previous shot")
	ui.seek_index(0)
	ui.next_turn()
	check(scene.session.playback.index==71,"Next turn seeks exact boundary")
	for kind in ["json","players","shots"]:
		ui.open_report_export(kind)
		ui.file_selected(base+"-"+kind+(".json" if kind=="json" else ".csv"))
		check(not ui.busy,"Report export releases guard")
		check(FileAccess.file_exists(base+"-"+kind+(".json" if kind=="json" else ".csv")),"Report export created "+kind)
	check(load("res://scripts/core/replay/match_replay.gd").state_hash(live)==hash_before,"Analysis preserves live state")
	if DisplayServer.get_name() != "headless":
		scene.preferences.hud_scale = 1.25
		scene._apply_client_preferences()
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(temporary_root.path_join("archive-ui250-inspector.png"))
		ui.shots.get_parent().current_tab = 1
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(temporary_root.path_join("archive-ui250-shots.png"))
	ui.seek_index(12)
	check(scene.session.playback.index==12,"Inspector indexed seek")
	ui.loop_toggle.button_pressed = true
	ui.seek_index(scene.session.playback.action_count)
	ui.update(0.016)
	check(scene.session.playback.finished,"Manual EOF seek never loops")
	ui.seek_index(0)
	scene.session.playback.set_playing(true)
	scene._advance_replay(2)
	check(scene.session.playback.index==0 and scene.session.playback.playing,"Natural playback EOF loops")
	ui.seek_index(15)
	scene._return_from_replay()
	check(scene.runner==live,"Return restores same live runner")
	check(scene._library_load(saved.id) and scene.session.playback.index==15,"Fingerprint guarded cursor resume")
	ui.seek_index(-1)
	check(ui.analysis_status.text.contains("seek"),"Seek error visible")
	scene._return_from_replay()
	scene._toggle_library()
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(temporary_root.path_join("archive-ui250-library.png"))
	ui.open_import()
	check(ui.busy and ui.file_dialog.visible and ui.operation_buttons[0].disabled,"Import dialog acquires busy guard")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(temporary_root.path_join("archive-ui250-dialog.png"))
	ui.open_import()
	ui.cancel_dialog()
	check(not ui.busy and not ui.file_dialog.visible,"Import cancellation releases busy guard")
	ui.export_kind = "raw"
	ui.export_id = saved.id
	ui.busy = true
	ui.file_selected(base + "-export.json")
	check(FileAccess.file_exists(base + "-export.json") and not ui.busy,"Raw export through coordinator")
	ui.busy = true
	ui.file_selected(base + "-export.json")
	check(ui.overwrite.visible and ui.busy,"Existing file requires explicit overwrite confirmation")
	ui.cancel_dialog()
	check(not ui.overwrite.visible and not ui.busy,"Overwrite cancellation safe")
	var exported_before := FileAccess.get_file_as_string(base+"-export.json")
	ui.overwrite.confirmed.emit()
	check(FileAccess.get_file_as_string(base+"-export.json")==exported_before,"Late overwrite callback after cancellation does nothing")
	ui.busy = true
	ui.file_selected(ui.preferences.path)
	check(ui.overwrite.visible,"Preferences replacement still requires confirmation")
	ui.overwrite.confirmed.emit()
	check(not ui.busy and scene.library_panel.status.text.contains("outside the archive library"),"Export cannot overwrite library preferences")
	ui.open_import()
	scene.library_panel.hide()
	ui.file_selected(base+"-export.json")
	check(not ui.busy and library.query({}).total==2,"Closing library cancels pending import and ignores late selection")
	scene.library_panel.show()
	ui.open_import()
	scene.remote_mode = true
	ui.file_selected(base+"-export.json")
	check(not ui.busy and library.query({}).total==2,"Remote transition rejects pending import callback")
	scene.remote_mode = false
	ui.import_kind.select(1)
	scene.library_panel.title_input.text = "Imported replay"
	ui.open_import()
	ui.file_selected(base+"-export.json")
	check(library.query({"query":"Imported replay"}).total==1,"Selected JSON import reaches verified library")
	ui.export_id = "../bad"
	ui.export_kind = "raw"
	ui.busy = true
	ui.file_selected(base+"-invalid.json")
	check(scene.library_panel.status.text.contains("Choose an archive entry"),"Raw export error explained")
	check(scene.library_panel.error_message("entry_limit").contains("100 entries") and scene.library_panel.error_message("invalid_title").contains("1–48"),"Capacity and title errors actionable")
	var invalid_id := "f".repeat(32)
	var file := FileAccess.open(base.path_join(invalid_id + ".json"),FileAccess.WRITE)
	file.store_string("broken")
	file.close()
	ui.show_diagnostics()
	check(ui.invalid_entries.item_count==1,"Corrupt entries shown")
	ui.invalid_entries.select(0)
	ui.confirm_corrupt_delete()
	check(ui.corrupt_confirmation.visible and FileAccess.file_exists(base.path_join(invalid_id+".json")),"Corrupt delete deferred until explicit confirmation")
	ui.corrupt_confirmation.confirmed.emit()
	check(not FileAccess.file_exists(base.path_join(invalid_id+".json")),"Confirmed corrupt deletion")
	scene.remote_mode = true
	ui.open_import()
	check(not ui.busy,"Remote import guarded")
	scene.remote_mode = false
	ui.cancel_dialog()
	ui.search.text = "Checkpoint"
	ui.search.text_changed.emit(ui.search.text)
	check(scene.library_panel.entries.item_count==1,"Checkpoint selected for preview and comparison")
	scene.library_panel.entries.select(0)
	ui.preview_selected()
	check(ui.details.text.contains("Turn") and ui.details.text.contains("Fingerprint:"),"Checkpoint preview displays validated summary")
	ui.pin_checkpoint()
	scene.library_panel.title_input.text = "Checkpoint copy"
	ui.duplicate_selected()
	check(library.query({"query":"Checkpoint"}).total==2,"Duplicate creates distinct checkpoint entry")
	for row in scene.library_panel.entries.item_count:
		if scene.library_panel.entries.get_item_metadata(row).id!=checkpoint.id:
			scene.library_panel.entries.select(row)
	ui.compare_selected()
	check(ui.details.text.contains("Same terrain: true") and ui.details.text.contains("Same state: true"),"Duplicate compares identically with pinned checkpoint")
	ui.show_diagnostics()
	check(ui.diagnostics_status.text.contains("Duplicate payload groups: 1"),"Diagnostics identifies duplicate checkpoint payload")
	ui.preferences.remember(saved.id,"0".repeat(64),12)
	check(scene._library_load(saved.id) and scene.session.playback.index==0,"Changed fingerprint ignores stale replay cursor")
	scene._return_from_replay()
	scene._toggle_library()
	for i in range(21):
		check(library.save_session("Page %02d" % i,runner,scene.session.options).ok,"Pagination fixture")
	ui.search.text = ""
	ui.search.text_changed.emit("")
	ui.sort_select.select(2)
	ui.sort_select.item_selected.emit(2)
	check(scene.library_panel.entries.item_count==20 and not ui.next_page.disabled,"First page limits to20")
	scene.library_panel.entries.select(1)
	var selected_id: String = scene.library_panel.selected_id()
	ui.refresh()
	check(scene.library_panel.selected_id()==selected_id,"Refresh preserves selected ID")
	ui.next_page.pressed.emit()
	check(ui.offset==20 and scene.library_panel.entries.item_count==5,"Next page shows remainder")
	var stored = load("res://scripts/client/session/library_preferences.gd").new(base+"-prefs.json")
	check(stored.load_from() and stored.filters.sort=="title" and stored.favorites.has(saved.id),"Filters and favorites persisted independently")
	for filename in DirAccess.get_files_at(base): DirAccess.remove_absolute(base.path_join(filename))
	DirAccess.remove_absolute(base)
	for suffix in ["-prefs.json","-export.json","-json.json","-players.csv","-shots.csv"]: DirAccess.remove_absolute(base+suffix)
	scene.queue_free()
	await process_frame
	print("ARCHIVE UI250: %d failures" % failures)
	quit(1 if failures else 0)
