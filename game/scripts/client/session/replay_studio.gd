extends RefCounted
## Notes and clip jobs bind to one playback identity. Library tools never replace authority.
const Notes = preload("res://scripts/core/replay/replay_notebook.gd")
const Clip = preload("res://scripts/core/replay/replay_clip_job.gd")
const Diff = preload("res://scripts/core/replay/replay_diff.gd")
const Archive = preload("res://scripts/core/replay/replay_archive.gd")
const Bundle = preload("res://scripts/core/storage/archive_bundle.gd")
var scene: Node
var notes_path: String
var source_path := ""
var notebook = Notes.new()
var clip_job: RefCounted
var clip_start := 0
var clip_end := 0
var comparison := {}
var buttons := {}
var note_title: LineEdit
var note_body: TextEdit
var note_category: OptionButton
var note_search: LineEdit
var note_filter: OptionButton
var note_list: ItemList
var clip_title: LineEdit
var clip_status: Label
var clip_progress: ProgressBar
var studio_status: Label
var library_status: Label
var bundle_list: ItemList
var file_dialog: FileDialog
var bundle_confirmation: ConfirmationDialog
var overwrite: ConfirmationDialog
var diff_details: TextEdit
var inspector_tabs: TabContainer
var _playback: RefCounted
var _fingerprint := ""
var _selected_note := ""
var _pinned_id := ""
var _pinned_fingerprint := ""
var _generation := 0
var _pending := {}
var _bundle_preview := {}
var _bundle_path := ""
var _previous_focus: WeakRef
func _init(owner_scene: Node, path := "user://replay_notes") -> void:
	scene = owner_scene
	notes_path = path
func setup() -> void:
	var inspector: VBoxContainer = scene.match_panels.replay_panel.get_meta("box")
	var heading := _label(inspector,"REPLAY STUDIO — notes and verified clips")
	heading.add_theme_font_size_override("font_size",18)
	inspector_tabs = TabContainer.new()
	inspector.add_child(inspector_tabs)
	var notes := VBoxContainer.new()
	notes.name = "Notes"
	inspector_tabs.add_child(notes)
	note_search = LineEdit.new()
	note_search.placeholder_text = "Search note title or body…"
	notes.add_child(note_search)
	note_search.text_changed.connect(func(_text): refresh_notes())
	note_filter = OptionButton.new()
	note_filter.add_item("All categories")
	for category in Notes.CATEGORIES: note_filter.add_item(category)
	notes.add_child(note_filter)
	note_filter.item_selected.connect(func(_index): refresh_notes())
	note_list = ItemList.new()
	note_list.custom_minimum_size.y = 95
	note_list.item_selected.connect(select_note)
	notes.add_child(note_list)
	note_title = LineEdit.new()
	note_title.placeholder_text = "Bookmark title (1–80 characters)"
	note_title.max_length = 80
	notes.add_child(note_title)
	note_body = TextEdit.new()
	note_body.placeholder_text = "Description (up to 2000 characters)"
	note_body.custom_minimum_size.y = 75
	note_body.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	notes.add_child(note_body)
	note_category = OptionButton.new()
	for category in Notes.CATEGORIES: note_category.add_item(category)
	notes.add_child(note_category)
	var note_actions := HFlowContainer.new()
	notes.add_child(note_actions)
	_button(note_actions,"note_add","Add at cursor",add_note)
	_button(note_actions,"note_edit","Apply edit",edit_note)
	_button(note_actions,"note_delete","Delete note",delete_note)
	_button(note_actions,"note_previous","Previous note",func(): navigate_note(-1))
	_button(note_actions,"note_next","Next note",func(): navigate_note(1))
	_button(note_actions,"notes_export","Export notes…",func(): open_dialog("notes_export"))
	_button(note_actions,"notes_import","Merge notes…",func(): open_dialog("notes_import"))
	var clips := VBoxContainer.new()
	clips.name = "Clips"
	inspector_tabs.add_child(clips)
	var range_actions := HFlowContainer.new()
	clips.add_child(range_actions)
	_button(range_actions,"clip_start","Set start at cursor",func():
		if _inspector_allowed(): _set_clip_boundary(true,scene.session.playback.index))
	_button(range_actions,"clip_end","Set end at cursor",func():
		if _inspector_allowed(): _set_clip_boundary(false,scene.session.playback.index))
	clip_status = _label(clips,"Set start and end to build a clip")
	clip_progress = ProgressBar.new()
	clips.add_child(clip_progress)
	clip_title = LineEdit.new()
	clip_title.placeholder_text = "Clip library title (1–48 characters)"
	clip_title.max_length = 48
	clip_title.text = "Replay clip"
	clips.add_child(clip_title)
	var clip_actions := HFlowContainer.new()
	clips.add_child(clip_actions)
	_button(clip_actions,"clip_build","Build verified clip",build_clip)
	_button(clip_actions,"clip_cancel","Cancel clip",cancel_clip)
	_button(clip_actions,"clip_export","Export clip…",func(): open_dialog("clip_export"))
	_button(clip_actions,"clip_library","Save clip in library",save_clip_to_library)
	studio_status = _label(inspector,"")
	var library_box: VBoxContainer = scene.library_panel.box
	_label(library_box,"REPLAY STUDIO — compare and portable bundles")
	var compare_actions := HFlowContainer.new()
	library_box.add_child(compare_actions)
	_button(compare_actions,"pin","Pin replay",func(): pin_replay(scene.library_panel.selected_id()))
	_button(compare_actions,"compare","Compare with pinned replay",func(): compare_replay(scene.library_panel.selected_id()))
	_button(compare_actions,"diff_export","Export comparison…",func(): open_dialog("diff_export"))
	diff_details = TextEdit.new()
	diff_details.editable = false
	diff_details.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	diff_details.custom_minimum_size.y = 100
	library_box.add_child(diff_details)
	bundle_list = ItemList.new()
	bundle_list.select_mode = ItemList.SELECT_MULTI
	bundle_list.custom_minimum_size.y = 110
	library_box.add_child(bundle_list)
	var bundle_actions := HFlowContainer.new()
	library_box.add_child(bundle_actions)
	_button(bundle_actions,"bundle_refresh","Refresh bundle selection",refresh_bundle_list)
	_button(bundle_actions,"bundle_export","Export selected ZIP…",func(): open_dialog("bundle_export"))
	_button(bundle_actions,"bundle_import","Inspect / import ZIP…",func(): open_dialog("bundle_import"))
	library_status = _label(library_box,"")
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.set("disable_overwrite_warning",true)
	file_dialog.file_selected.connect(file_selected)
	file_dialog.canceled.connect(cancel_dialog)
	scene.add_child(file_dialog)
	overwrite = ConfirmationDialog.new()
	overwrite.title = "Replace exported file?"
	overwrite.confirmed.connect(func():
		var snapshot := _pending.duplicate(true)
		_write_dialog(str(snapshot.get("path","")),true))
	overwrite.canceled.connect(cancel_dialog)
	scene.add_child(overwrite)
	bundle_confirmation = ConfirmationDialog.new()
	bundle_confirmation.title = "Verified archive bundle preview"
	bundle_confirmation.ok_button_text = "Import new copies"
	bundle_confirmation.confirmed.connect(import_previewed_bundle)
	bundle_confirmation.canceled.connect(cancel_dialog)
	scene.add_child(bundle_confirmation)
	scene.match_panels.replay_panel.visibility_changed.connect(func():
		if not scene.match_panels.replay_panel.visible:
			cancel_clip()
			if _pending.get("scope") == "inspector": cancel_dialog())
	scene.library_panel.visibility_changed.connect(func():
		if scene.library_panel.visible: refresh_bundle_list()
		elif _pending.get("scope") == "library": cancel_dialog())
func _label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label
func _button(parent: Node, id: String, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	buttons[id] = button
	return button
func _allowed() -> bool:
	if scene.remote_mode: return false
	for name in ["workshop","competition"]:
		var workflow = scene.get(name)
		if workflow != null and workflow.is_active(): return false
	return scene.workflows == null or not scene.workflows.training.active
func _inspector_allowed() -> bool: return _allowed() and _playback != null and scene.session.playback == _playback and scene.match_panels.replay_panel.visible
func _library_allowed() -> bool: return _allowed() and scene.library_panel.visible and not scene.projectile_in_flight
func _note_path() -> String: return notes_path.path_join(_fingerprint+".json")
func on_opened() -> void:
	closing_replay()
	if not _allowed() or scene.session.playback == null: return
	_playback = scene.session.playback
	_fingerprint = Notes.fingerprint(_playback.recording_copy())
	notebook.bind(_fingerprint,_playback.action_count)
	clip_start = 0
	clip_end = _playback.action_count
	var path := ProjectSettings.globalize_path(_note_path())
	if FileAccess.file_exists(path):
		var loaded: Dictionary = notebook.load_from(path)
		if not loaded.ok: studio_status.text = "Notes load failed: "+str(loaded.reason)
	refresh_notes()
	_show_clip_range()
func closing_replay() -> void:
	_generation += 1
	cancel_clip()
	cancel_dialog()
	clip_job = null
	_playback = null
	_fingerprint = ""
	source_path = ""
	_selected_note = ""
	notebook = Notes.new()
	if note_list != null: note_list.clear()
func _persist_notes() -> bool:
	var directory := ProjectSettings.globalize_path(notes_path).simplify_path()
	if not Notes.safe_path(directory) or DirAccess.make_dir_recursive_absolute(directory) != OK:
		studio_status.text = "Notes changed in memory; directory unavailable"
		return false
	var saved: Dictionary = notebook.save_to(_note_path())
	if not saved.ok: studio_status.text = "Notes changed in memory; save failed: "+str(saved.reason)
	return saved.ok
func add_note() -> void:
	if not _inspector_allowed(): return
	var result: Dictionary = notebook.add(_playback.index,note_title.text,note_body.text,note_category.get_item_text(note_category.selected))
	if not result.ok: studio_status.text = str(result.reason); return
	_selected_note = result.id
	_persist_notes()
	refresh_notes()
func edit_note() -> void:
	if not _inspector_allowed(): return
	var result: Dictionary = notebook.edit(_selected_note,{"title":note_title.text,"body":note_body.text,"category":note_category.get_item_text(note_category.selected)})
	if not result.ok: studio_status.text = str(result.reason); return
	_persist_notes()
	refresh_notes()
func delete_note() -> void:
	if not _inspector_allowed(): return
	var result: Dictionary = notebook.remove(_selected_note)
	if not result.ok: studio_status.text = str(result.reason); return
	_selected_note = ""
	_persist_notes()
	refresh_notes()
func refresh_notes() -> void:
	if note_list == null: return
	note_list.clear()
	var category := "" if note_filter.selected == 0 else note_filter.get_item_text(note_filter.selected)
	var visible_rows: Array = notebook.list(note_search.text,category)
	var visible_ids: Array = visible_rows.map(func(row): return row.id)
	if _selected_note not in visible_ids: _selected_note = ""
	buttons.note_edit.disabled = _selected_note.is_empty()
	buttons.note_delete.disabled = _selected_note.is_empty()
	for row in visible_rows:
		var index := note_list.add_item("%d • %s • %s" % [row.index,row.category,row.title])
		note_list.set_item_metadata(index,row)
		note_list.set_item_tooltip(index,row.title+"\n"+row.body)
		if row.id == _selected_note: note_list.select(index)
func select_note(index: int) -> void:
	if not _inspector_allowed() or index < 0 or index >= note_list.item_count: return
	var row: Dictionary = note_list.get_item_metadata(index)
	_selected_note = row.id
	buttons.note_edit.disabled = false
	buttons.note_delete.disabled = false
	note_title.text = row.title
	note_body.text = row.body
	note_category.select(Notes.CATEGORIES.find(row.category))
	scene.archive_ui.seek_index(int(row.index))
func navigate_note(direction: int) -> void:
	if not _inspector_allowed(): return
	var category := "" if note_filter.selected == 0 else note_filter.get_item_text(note_filter.selected)
	var rows: Array = notebook.list(note_search.text,category)
	if direction < 0: rows.reverse()
	for row in rows:
		if (direction > 0 and row.index > _playback.index) or (direction < 0 and row.index < _playback.index):
			_selected_note = row.id
			refresh_notes()
			for index in note_list.item_count:
				if note_list.get_item_metadata(index).id == row.id: select_note(index); return
func _set_clip_boundary(start: bool, value: int) -> void:
	if (start and value != clip_start) or (not start and value != clip_end):
		cancel_clip()
		clip_job = null
		if _pending.get("action") == "clip_export": cancel_dialog()
	if start: clip_start = value
	else: clip_end = value
	_show_clip_range()
func _show_clip_range() -> void: clip_status.text = "Range [%d, %d) • %d actions" % [clip_start,clip_end,maxi(0,clip_end-clip_start)]
func build_clip() -> void:
	if not _inspector_allowed(): return
	cancel_clip()
	clip_job = Clip.new()
	if not clip_job.begin(_playback.recording_copy(),clip_start,clip_end): clip_status.text = "Invalid clip range"; return
	_playback.set_playing(false)
	clip_progress.max_value = maxi(1,clip_end)
	clip_progress.value = 0
	clip_status.text = "Building clip…"
func cancel_clip() -> void:
	if clip_job != null and not clip_job.finished:
		clip_job.cancel()
		if clip_status != null: clip_status.text = "Clip cancelled"
func update(_delta: float) -> void:
	if _playback != null and scene.session.playback != _playback: closing_replay(); return
	if not _inspector_allowed():
		cancel_clip()
		return
	if clip_job == null or clip_job.finished: return
	var progress: Dictionary = clip_job.step(32)
	clip_progress.value = clip_job.index
	clip_status.text = "Clip %s: %d / %d actions" % [progress.get("phase","error"),clip_job.index,clip_end]
	if not progress.ok: clip_status.text = "Clip failed: "+str(progress.reason)
	elif clip_job.finished: clip_status.text = "Verified clip ready • %d actions" % (clip_end-clip_start)
func _clip_ready() -> bool: return _inspector_allowed() and clip_job != null and clip_job.finished and clip_job.error.is_empty() and clip_job.result_recorder != null
func save_clip_to_library() -> void:
	if not _clip_ready(): return
	var saved: Dictionary = scene.library.save_replay(clip_title.text,clip_job.result_recorder,clip_job.result_runner)
	studio_status.text = "Clip saved with new ID: "+str(saved.id) if saved.ok else "Clip save failed: "+str(saved.reason)
	if saved.ok:
		var moved: RefCounted = clip_job.notebook_for_clip(notebook)
		var notes_file := notes_path.path_join(Notes.fingerprint(clip_job.result_recorder)+".json")
		var result: Dictionary = moved.save_to(notes_file)
		if not result.ok: studio_status.text += " (clip notes could not be saved)"
func pin_replay(id: String) -> void:
	if not _library_allowed(): return
	var loaded: Dictionary = scene.library.load_entry(id)
	if not loaded.ok or loaded.get("kind") != "replay": library_status.text = "Select a verified replay"; return
	_pinned_id = id
	_pinned_fingerprint = scene.library.fingerprint(id)
	library_status.text = "Pinned replay: "+str(loaded.metadata.title)
func compare_replay(id: String) -> Dictionary:
	if not _library_allowed(): return Notes.failure("library_unavailable")
	if _pinned_id.is_empty() or _pinned_fingerprint != scene.library.fingerprint(_pinned_id): return Notes.failure("pinned_replay_changed")
	var first: Dictionary = scene.library.load_entry(_pinned_id)
	var second: Dictionary = scene.library.load_entry(id)
	if not first.ok or not second.ok or first.get("kind") != "replay" or second.get("kind") != "replay": return Notes.failure("select_two_replays")
	comparison = Diff.compare(first.recorder,second.recorder)
	diff_details.text = JSON.stringify(comparison,"  ",true,true)
	library_status.text = "Comparison complete — identical initial configuration: %s" % comparison.get("configuration",{}).get("initial_equal",false)
	return comparison
func refresh_bundle_list() -> void:
	if not _library_allowed(): return
	var selected: Array[String] = []
	for index in bundle_list.get_selected_items(): selected.append(bundle_list.get_item_metadata(index))
	bundle_list.clear()
	var listing: Dictionary = scene.library.list_entries()
	for entry in listing.entries:
		var index := bundle_list.add_item(entry.title+" • "+entry.kind)
		bundle_list.set_item_metadata(index,entry.id)
		bundle_list.set_item_tooltip(index,entry.title+"\n"+entry.id)
		if entry.id in selected: bundle_list.select(index,false)
func _protected_output(path: String) -> bool:
	var absolute := ProjectSettings.globalize_path(path).simplify_path()
	if absolute == scene.library.base_path or absolute.begins_with(scene.library.base_path+"/"): return true
	if not source_path.is_empty() and absolute == ProjectSettings.globalize_path(source_path).simplify_path(): return true
	var notes_root := ProjectSettings.globalize_path(notes_path).simplify_path()
	return absolute == notes_root or absolute.begins_with(notes_root+"/")
func open_dialog(action: String) -> void:
	var inspector_action := action in ["notes_export","notes_import","clip_export"]
	if (inspector_action and not _inspector_allowed()) or (not inspector_action and not _library_allowed()) or (action == "clip_export" and not _clip_ready()): return
	cancel_dialog()
	var focused := scene.get_viewport().gui_get_focus_owner()
	_previous_focus = weakref(focused) if focused != null else null
	_pending = {"action":action,"scope":"inspector" if inspector_action else "library","generation":_generation,"fingerprint":_fingerprint,"library":scene.library,"ids":[],"path":""}
	if action == "bundle_export":
		for index in bundle_list.get_selected_items(): _pending.ids.append(bundle_list.get_item_metadata(index))
		if _pending.ids.is_empty(): library_status.text = "Select entries in the bundle list"; _pending = {}; return
	if action == "diff_export" and not comparison.get("ok",false): library_status.text = "Compare two replays first"; _pending = {}; return
	_pending["comparison"] = comparison.duplicate(true) if action == "diff_export" else {}
	_pending["clip_job"] = clip_job if action == "clip_export" else null
	var importing := action in ["notes_import","bundle_import"]
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE if importing else FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.filters = PackedStringArray(["*.zip ; TerraBlast archive bundle"] if action.begins_with("bundle") else ["*.json ; JSON"])
	file_dialog.current_file = "archives.zip" if action.begins_with("bundle") else "replay-studio.json"
	file_dialog.popup_centered_ratio(0.8)
func _pending_valid() -> bool:
	if _pending.is_empty() or _pending.generation != _generation or _pending.library != scene.library: return false
	if _pending.get("action") == "clip_export" and _pending.get("clip_job") != clip_job: return false
	if _pending.scope == "inspector": return _inspector_allowed() and _pending.fingerprint == _fingerprint
	return _library_allowed()
func file_selected(path: String) -> void:
	if not _pending_valid(): cancel_dialog(); return
	file_dialog.hide()
	_pending.path = path
	if _pending.action == "bundle_import":
		_bundle_preview = Bundle.inspect(path)
		_bundle_path = path
		if not _bundle_preview.ok: library_status.text = "Bundle rejected: "+str(_bundle_preview.reason); cancel_dialog(); return
		var descriptions := PackedStringArray()
		for entry in _bundle_preview.entries: descriptions.append("%s • %s • %d bytes" % [entry.title,entry.kind,entry.size])
		bundle_confirmation.dialog_text = "Verified %d entries. Import as new library IDs?\n%s" % [_bundle_preview.entries.size(),"\n".join(descriptions)]
		bundle_confirmation.popup_centered()
		return
	if _pending.action == "notes_import":
		var other := Notes.new()
		other.bind(_fingerprint,_playback.action_count)
		var loaded := other.load_from(path)
		var merged: Dictionary = notebook.merge(other.encode()) if loaded.ok else loaded
		studio_status.text = "Notes merged" if merged.ok else str(merged.reason)
		if merged.ok: _persist_notes(); refresh_notes()
		cancel_dialog()
		return
	if _protected_output(path): _status("Protected source or library path"); cancel_dialog(); return
	if FileAccess.file_exists(path): overwrite.dialog_text = "Replace this exported file?\n"+path; overwrite.popup_centered(); return
	_write_dialog(path,false)
func _status(text: String) -> void:
	if _pending.get("scope") == "library": library_status.text = text
	else: studio_status.text = text
func _write_dialog(path: String, replace: bool) -> void:
	if not _pending_valid() or _protected_output(path): cancel_dialog(); return
	var result := Notes.failure("unsupported_action")
	match _pending.action:
		"notes_export": result = notebook.save_to(path,replace)
		"clip_export":
			if _clip_ready():
				var encoded := Archive.encode(clip_job.result_recorder,clip_job.result_runner)
				if encoded.ok and Archive.decode(encoded.payload).ok: result = Notes.atomic_write(path,JSON.stringify(encoded.payload,"",true,true),replace)
		"diff_export": result = Diff.export(path,_pending.comparison,replace)
		"bundle_export": result = Bundle.export_bundle(scene.library,_pending.ids,path,replace)
	_status("Exported "+path if result.ok else "Export failed: "+str(result.reason))
	cancel_dialog()
func import_previewed_bundle() -> void:
	if not _pending_valid() or _pending.get("action") != "bundle_import" or _bundle_preview.is_empty(): cancel_dialog(); return
	# Reinspect before writing; the file may have changed while preview was open.
	var current := Bundle.inspect(_bundle_path)
	if not current.ok or current.manifest != _bundle_preview.manifest: library_status.text = "Bundle changed after preview"; cancel_dialog(); return
	var imported := Bundle.import_bundle(scene.library,_bundle_path)
	library_status.text = "Imported %d new entries" % imported.count if imported.ok else "Import failed: "+str(imported.reason)
	cancel_dialog()
	refresh_bundle_list()
	scene.archive_ui.refresh()
func cancel_dialog() -> void:
	_pending = {}
	_bundle_preview = {}
	_bundle_path = ""
	if file_dialog != null: file_dialog.hide()
	if overwrite != null: overwrite.hide()
	if bundle_confirmation != null: bundle_confirmation.hide()
	if _previous_focus != null:
		var focused = _previous_focus.get_ref()
		if is_instance_valid(focused) and focused.is_visible_in_tree(): focused.grab_focus()
	_previous_focus = null
