extends SceneTree
const Replay = preload("res://scripts/core/replay/match_replay.gd")
const Library = preload("res://scripts/core/storage/local_archive_library.gd")
var failures := 0
var checks := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	if "--studio-visual" in OS.get_cmdline_user_args():
		await visual_smoke()
		return
	if not FileAccess.file_exists("res://scripts/client/session/replay_studio.gd"):
		check(false,"S13 Replay Studio UI must exist")
		quit(1)
		return
	root.size = Vector2i(800,600)
	var scene = load("res://scenes/debug/VoxelDebug.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_physics_process(false)
	var tmp := "/private/tmp" if OS.get_name() == "macOS" else "/tmp"
	var folder := tmp.path_join("terrablast-studio-ui-%s" % OS.get_process_id())
	scene.archive_ui.preferences.path = folder.path_join("library-preferences.json")
	scene.library = Library.new(folder.path_join("library"))
	var studio = scene.get("replay_studio")
	if studio == null:
		studio = load("res://scripts/client/session/replay_studio.gd").new(scene,folder.path_join("notes"))
		studio.setup()
	else: studio.notes_path = folder.path_join("notes")
	var runner = load("res://scripts/core/rules/match_factory.gd").from_definition(load("res://scripts/core/workshop/workshop_document.gd").new().snapshot(),2)
	var rec := Replay.new()
	rec.capture(runner)
	for index in 8: rec.tick(runner,0.1)
	var saved: Dictionary = scene.library.save_replay("Source replay",rec,runner)
	var second: Dictionary = scene.library.save_replay("Second replay",rec,runner)
	var live = scene.runner
	var live_hash: String = Replay.state_hash(live)
	scene.player_velocities.blue_1 = Vector3(0.25,1.5,-0.25)
	check(scene._inspect_recording(rec),"S50 open inspector")
	studio.on_opened()
	studio.note_title.text = "Zażółć bookmark"
	studio.note_body.text = "Pełny opis\nUnicode GĘŚLĄ"
	studio.note_category.select(3)
	studio.buttons.note_add.pressed.emit()
	check(studio.notebook.list().size() == 1 and studio.note_list.item_count == 1 and studio.notebook.list()[0].index == 0,"S13 add current bookmark through UI")
	check(studio.note_list.get_item_tooltip(0).contains("GĘŚLĄ"),"S49 Unicode full note tooltip")
	scene.archive_ui.seek_index(3)
	studio.note_title.text = "Middle"
	studio.buttons.note_add.pressed.emit()
	studio.note_list.select(0)
	studio.note_list.item_selected.emit(0)
	check(scene.session.playback.index == 0,"S14 choose bookmark navigates")
	studio.buttons.note_next.pressed.emit()
	check(scene.session.playback.index == 3,"S14 next bookmark navigates")
	studio.buttons.note_next.pressed.emit()
	check(scene.session.playback.index == 3,"S14 edge next cursor unchanged")
	studio.note_title.text = "Edited"
	studio.buttons.note_edit.pressed.emit()
	check(studio.notebook.list()[1].title == "Edited","S15 real note editor")
	studio.buttons.note_delete.pressed.emit()
	check(studio.notebook.list().size() == 1,"S15 delete selected note")

	# Navigation must use the visible note set; a hidden row must never become an edit target.
	var hidden: Dictionary = studio.notebook.add(5,"Hidden note","keep me","note")
	studio.refresh_notes()
	studio.note_filter.select(4)
	studio.note_filter.item_selected.emit(4)
	studio.note_list.select(0)
	studio.note_list.item_selected.emit(0)
	studio.buttons.note_next.pressed.emit()
	studio.note_title.text = "Visible edited"
	studio.buttons.note_edit.pressed.emit()
	var hidden_unchanged := false
	for row in studio.notebook.list():
		if row.id == hidden.id: hidden_unchanged = row.title == "Hidden note" and row.body == "keep me"
	check(scene.session.playback.index == 0 and hidden_unchanged,"S14 filtered navigation cannot select or overwrite hidden note")
	studio.note_filter.select(0)
	studio.note_filter.item_selected.emit(0)
	for index in studio.note_list.item_count:
		if studio.note_list.get_item_metadata(index).id == hidden.id: studio.note_list.select(index); studio.note_list.item_selected.emit(index)
	studio.note_filter.select(4)
	studio.note_filter.item_selected.emit(4)
	var hidden_snapshot: Dictionary = studio.notebook.encode()
	studio.note_title.text = "Accidental hidden overwrite"
	studio.buttons.note_edit.pressed.emit()
	check(studio.notebook.encode() == hidden_snapshot,"S15 filter hides selection and clears edit target")
	studio.notebook.remove(hidden.id)
	studio.note_filter.select(0)
	studio.refresh_notes()
	studio._persist_notes()
	scene.archive_ui.seek_index(3)
	studio.buttons.clip_start.pressed.emit()
	scene.archive_ui.seek_index(6)
	studio.buttons.clip_end.pressed.emit()
	check(studio.clip_start == 3 and studio.clip_end == 6,"S16 UI range markers")
	studio.buttons.clip_build.pressed.emit()
	check(studio.clip_job != null and not studio.clip_job.finished,"S24 clip job starts from UI")
	for frame in 10: studio.update(0.016)
	check(studio.clip_job.finished and studio.clip_job.error.is_empty() and studio.clip_status.text.contains("ready"),"S24 UI clip progress completion")

	studio.open_dialog("clip_export")
	scene.archive_ui.seek_index(7)
	studio.buttons.clip_end.pressed.emit()
	check(studio.clip_job == null,"S24 changing clip markers invalidates finished old range")
	var stale_clip_path := folder.path_join("stale-range.json")
	studio.file_selected(stale_clip_path)
	check(not FileAccess.file_exists(stale_clip_path),"S47 stale range dialog cannot export previous clip")
	studio.buttons.clip_build.pressed.emit()
	for frame in 10: studio.update(0.016)
	check(studio.clip_job.result_recorder.data.actions.size() == 4,"S24 rebuilt clip matches changed marker range")
	scene.archive_ui.seek_index(6)
	studio.buttons.clip_end.pressed.emit()
	studio.buttons.clip_build.pressed.emit()
	for frame in 10: studio.update(0.016)
	studio.clip_title.text = "UI clip"
	studio.buttons.clip_library.pressed.emit()
	check(scene.library.list_entries("replay").entries.size() == 3,"S22 clip saved independent library entry")
	var output := folder.path_join("clip.json")
	studio.open_dialog("clip_export")
	studio.file_selected(output)
	check(FileAccess.file_exists(output),"S21 UI clip archive export")
	studio.buttons.clip_build.pressed.emit()
	studio.buttons.clip_cancel.pressed.emit()
	check(studio.clip_job.finished and studio.clip_job.error == "cancelled","S20 UI cancel clip")
	studio.open_dialog("notes_export")
	studio.closing_replay()
	studio.file_selected(folder.path_join("stale.json"))
	check(not FileAccess.file_exists(folder.path_join("stale.json")) and studio.clip_job == null,"S47 stale source dialog and job cancelled")
	studio.on_opened()
	check(studio.notebook.list().size() == 1,"S10 notes persisted and restored")
	studio.open_dialog("notes_export")
	check(studio.file_dialog.visible and scene.local_paused,"S48 dialog modal and local paused")
	studio.cancel_dialog()
	check(not studio.file_dialog.visible,"S48 cancel restores inspector")
	scene._return_from_replay()
	check(scene.runner == live and Replay.state_hash(live) == live_hash and scene.player_velocities.blue_1 == Vector3(0.25,1.5,-0.25),"S50 live hash and velocity preserved")
	scene._toggle_library()
	studio.refresh_bundle_list()
	check(studio.bundle_list.select_mode == ItemList.SELECT_MULTI and scene.library_panel.entries.select_mode == ItemList.SELECT_SINGLE,"S42 separate multiselect library list")
	studio.pin_replay(saved.id)
	check(studio.compare_replay(second.id).ok and studio.comparison.get("ok",false),"S32 pinned two replay comparison")
	var selected_ids: Array = []
	for index in studio.bundle_list.item_count:
		studio.bundle_list.select(index,false)
		selected_ids.append(studio.bundle_list.get_item_metadata(index))
	var bundle_path := folder.path_join("portable.zip")
	studio.open_dialog("bundle_export")
	studio.file_selected(bundle_path)
	check(FileAccess.file_exists(bundle_path),"S43 actual ZIP export dialog callback")
	studio.open_dialog("bundle_import")
	studio.file_selected(bundle_path)
	check(studio.bundle_confirmation.visible and scene.library.list_entries().entries.size() == 3,"S43 preview before import")
	studio.bundle_confirmation.confirmed.emit()
	check(scene.library.list_entries().entries.size() == 6,"S43 confirmed import new entries")
	var old_notes: int = studio.notebook.list().size()
	scene.remote_mode = true
	studio.buttons.note_add.pressed.emit()
	studio.open_dialog("bundle_import")
	check(not studio.file_dialog.visible and studio.notebook.list().size() == old_notes,"S50 online operations blocked")
	scene.remote_mode = false
	scene.preferences.hud_scale = 1.25
	scene._apply_client_preferences()
	await process_frame
	await process_frame
	check(scene.library_panel.scroll.get_v_scroll_bar().max_value > scene.library_panel.scroll.size.y and studio.bundle_list.is_inside_tree(),"S49 800x600 HUD125 scrolling exposes studio controls")
	studio.closing_replay()
	scene.queue_free()
	await process_frame
	# Remove only files from the isolated test directory.
	cleanup(folder)
	print("Replay studio integration: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
func cleanup(path: String) -> void:
	for file in DirAccess.get_files_at(path): DirAccess.remove_absolute(path.path_join(file))
	for folder in DirAccess.get_directories_at(path): cleanup(path.path_join(folder))
	DirAccess.remove_absolute(path)

func visual_smoke() -> void:
	root.size = Vector2i(800,600)
	var scene = load("res://scenes/debug/VoxelDebug.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_physics_process(false)
	scene.preferences.hud_scale = 1.25
	scene._apply_client_preferences()
	var runner = load("res://scripts/core/rules/match_factory.gd").from_definition(load("res://scripts/core/workshop/workshop_document.gd").new().snapshot(),2)
	var recorder := Replay.new()
	recorder.capture(runner)
	for index in 8: recorder.tick(runner,0.1)
	scene._inspect_recording(recorder)
	scene.set_physics_process(true)
	var studio = scene.replay_studio
	studio.notes_path = ("/private/tmp" if OS.get_name() == "macOS" else "/tmp").path_join("terrablast-studio-visual-%d" % OS.get_process_id())
	studio.note_title.text = "Zażółć gęślą — sprawdź osłonę"
	studio.note_body.text = "Bezpieczny punkt przed strzałem.
Pełny opis i kategoria pozostają w osobnym notatniku."
	studio.buttons.note_add.pressed.emit()
	await process_frame
	await process_frame
	var scroll: ScrollContainer = scene.match_panels.replay_panel.get_child(0)
	scroll.ensure_control_visible(studio.inspector_tabs)
	await create_timer(45).timeout
	scene._return_from_replay()
	scene.queue_free()
	await process_frame
	cleanup(studio.notes_path)
	quit(0)
