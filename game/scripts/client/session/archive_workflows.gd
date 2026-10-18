extends RefCounted
## Local archive presentation. Analysis owns a private runner; scene retains authority.
const Analyzer = preload("res://scripts/core/replay/replay_analyzer.gd")
const Preferences = preload("res://scripts/client/session/library_preferences.gd")
const Library = preload("res://scripts/core/storage/local_archive_library.gd")
var scene: Node
var preferences: RefCounted
var page_size := 20
var offset := 0
var busy := false:
	set(value):
		busy = value
		_sync_busy()
var search: LineEdit
var sort_select: OptionButton
var favorites_only: CheckBox
var details: Label
var page_label: Label
var previous_page: Button
var next_page: Button
var favorite_button: Button
var import_kind: OptionButton
var diagnostics_status: Label
var invalid_entries: ItemList
var corrupt_confirmation: ConfirmationDialog
var pending_corrupt := ""
var file_dialog: FileDialog
var overwrite: ConfirmationDialog
var export_kind := ""
var export_id := ""
var pending_path := ""
var pending_import_kind := ""
var pending_title := ""
var analyzer: RefCounted
var report := {}
var analysis_status: Label
var statistics: Label
var shots: ItemList
var turns: ItemList
var action_label: Label
var progress: ProgressBar
var loop_toggle: CheckBox
var opened_id := ""
var opened_fingerprint := ""
var active_playback: RefCounted
var analysis_running := false:
	set(value):
		analysis_running = value
		_sync_busy()
var comparison_id := ""
var operation_buttons: Array[Button] = []
var cancel_analysis_button: Button
var _page_total := 0
var _restore_controls := false

func _init(owner_scene: Node, preferences_path: String = "user://library_preferences.json") -> void:
	scene = owner_scene
	preferences = Preferences.new(preferences_path)

func setup() -> void:
	preferences.load_from()
	var panel = scene.library_panel
	var controls := VBoxContainer.new()
	panel.box.add_child(controls)
	panel.box.move_child(controls,1)
	search = LineEdit.new()
	search.placeholder_text = "Search names…"
	search.max_length = 100
	controls.add_child(search)
	var row := HBoxContainer.new()
	controls.add_child(row)
	sort_select = OptionButton.new()
	for name in ["Newest first","Oldest first","Title","Kind"]: sort_select.add_item(name)
	row.add_child(sort_select)
	favorites_only = CheckBox.new()
	favorites_only.text = "Favorites only"
	row.add_child(favorites_only)
	_restore_controls = true
	search.text = preferences.filters.query
	sort_select.select(["newest","oldest","title","kind"].find(preferences.filters.sort))
	panel.filter.select(["","session","replay"].find(preferences.filters.kind))
	favorites_only.button_pressed = preferences.filters.favorites_only
	_restore_controls = false
	search.text_changed.connect(func(_text): filters_changed())
	sort_select.item_selected.connect(func(_index): filters_changed())
	favorites_only.toggled.connect(func(_value): filters_changed())
	panel.filter.item_selected.connect(func(_index): filters_changed())
	var paging := HBoxContainer.new()
	controls.add_child(paging)
	previous_page = _button(paging,"Previous page",func(): offset = maxi(0,offset-page_size); refresh())
	page_label = _label(paging,"")
	next_page = _button(paging,"Next page",func(): offset += page_size; refresh())
	details = _label(panel.box,"Select an entry to see its ID, type, size and UTC date.")
	panel.box.move_child(details,panel.entries.get_index()+1)
	panel.entries.item_selected.connect(func(_index): selected())
	var actions := HBoxContainer.new()
	panel.box.add_child(actions)
	favorite_button = _button(actions,"☆ Favorite",toggle_favorite)
	_button(actions,"Duplicate",duplicate_selected)
	_button(actions,"Preview",preview_selected)
	panel.box.move_child(actions,details.get_index()+1)
	var compare := HBoxContainer.new()
	panel.box.add_child(compare)
	_button(compare,"Pin checkpoint",pin_checkpoint)
	_button(compare,"Compare with pinned",compare_selected)
	var files := HBoxContainer.new()
	panel.box.add_child(files)
	import_kind = OptionButton.new()
	import_kind.add_item("Checkpoint JSON")
	import_kind.add_item("Replay JSON")
	files.add_child(import_kind)
	_button(files,"Import file…",open_import)
	_button(files,"Export selected…",open_raw_export)
	_button(panel.box,"Storage and damaged entries",show_diagnostics)
	diagnostics_status = _label(panel.box,"")
	invalid_entries = ItemList.new()
	invalid_entries.custom_minimum_size.y = 75
	invalid_entries.hide()
	panel.box.add_child(invalid_entries)
	_button(panel.box,"Delete selected damaged entry…",confirm_corrupt_delete)
	corrupt_confirmation = ConfirmationDialog.new()
	corrupt_confirmation.title = "Delete damaged archive"
	panel.add_child(corrupt_confirmation)
	corrupt_confirmation.confirmed.connect(delete_corrupt)
	corrupt_confirmation.canceled.connect(func(): pending_corrupt = "")
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.use_native_dialog = false
	file_dialog.size = Vector2i(760,480)
	file_dialog.file_selected.connect(file_selected)
	file_dialog.canceled.connect(cancel_dialog)
	scene.add_child(file_dialog)
	overwrite = ConfirmationDialog.new()
	overwrite.title = "Replace exported file?"
	overwrite.confirmed.connect(func(): _write_export(pending_path,true))
	overwrite.canceled.connect(cancel_dialog)
	scene.add_child(overwrite)
	# The coordinator owns the one explicit path-specific overwrite confirmation.
	file_dialog.set("disable_overwrite_warning",true)
	panel.visibility_changed.connect(func():
		if not panel.visible:
			cancel_dialog()
			corrupt_confirmation.hide()
			pending_corrupt = "")
	for child in panel.box.get_children():
		if child is HBoxContainer and child.get_child_count()==1 and child.get_child(0) is Button and child.get_child(0).text=="Close": panel.box.move_child(child,panel.box.get_child_count()-1)
	_collect_existing_buttons(panel.box)
	_collect_existing_buttons(scene.match_panels.replay_panel.get_meta("box"))
	_setup_inspector()
	_sync_busy()

func _label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)
	operation_buttons.append(button)
	return button

func _setup_inspector() -> void:
	var panel = scene.match_panels.replay_panel
	var box: VBoxContainer = panel.get_meta("box")
	var tools := VBoxContainer.new()
	box.add_child(tools)
	box.move_child(tools,2)
	action_label = _label(tools,"")
	var navigation := HBoxContainer.new()
	tools.add_child(navigation)
	_button(navigation,"Previous shot",previous_shot).tooltip_text = "Ctrl+Left"
	_button(navigation,"Next turn",next_turn).tooltip_text = "Ctrl+Right"
	loop_toggle = CheckBox.new()
	loop_toggle.text = "Loop on playback end"
	tools.add_child(loop_toggle)
	var analysis_buttons := HBoxContainer.new()
	tools.add_child(analysis_buttons)
	_button(analysis_buttons,"Analyze recording",begin_analysis)
	cancel_analysis_button = _button(analysis_buttons,"Cancel analysis",cancel_analysis)
	progress = ProgressBar.new()
	progress.custom_minimum_size.y = 16
	tools.add_child(progress)
	analysis_status = _label(tools,"Analyze to view statistics and shot bookmarks.")
	var tabs := TabContainer.new()
	tabs.custom_minimum_size.y = 180
	tools.add_child(tabs)
	var stats_scroll := ScrollContainer.new()
	stats_scroll.name = "Statistics"
	stats_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(stats_scroll)
	statistics = _label(stats_scroll,"")
	shots = ItemList.new()
	shots.name = "Shots"
	tabs.add_child(shots)
	shots.item_selected.connect(func(index): seek_index(int(shots.get_item_metadata(index))))
	turns = ItemList.new()
	turns.name = "Turns"
	tabs.add_child(turns)
	turns.item_selected.connect(func(index): seek_index(int(turns.get_item_metadata(index))))
	var exports := HBoxContainer.new()
	tools.add_child(exports)
	for kind in ["json","players","shots"]:
		_button(exports,"JSON report" if kind=="json" else kind.capitalize()+" CSV",func(): open_report_export(kind))
	panel.visibility_changed.connect(func():
		if not panel.visible:
			cancel_analysis()
			remember_cursor()
			cancel_dialog())

func _library_allowed() -> bool:
	return not busy and scene.session.can_archive()

func _inspector_allowed() -> bool:
	return not scene.remote_mode and scene.session.playback != null and scene.match_panels.replay_panel.visible and (scene.workflows == null or not scene.workflows.training.active)

func filters_changed() -> void:
	if _restore_controls or busy: return
	offset = 0
	preferences.filters = {"query":search.text,"sort":["newest","oldest","title","kind"][sort_select.selected],"kind":scene.library_panel.selected_kind(),"favorites_only":favorites_only.button_pressed}
	var saved: Error = preferences.save_to()
	refresh()
	if saved != OK: scene.library_panel.status.text += "\nCould not save library preferences."

func refresh() -> void:
	var options: Dictionary = preferences.filters.duplicate()
	options.query = search.text
	options.kind = scene.library_panel.selected_kind()
	options.sort = ["newest","oldest","title","kind"][sort_select.selected]
	options.favorites_only = favorites_only.button_pressed
	options.favorites = preferences.favorites
	options.offset = offset
	options.limit = page_size
	var result: Dictionary = scene.library.query(options)
	var total: int = result.get("total",0)
	_page_total = total
	if offset >= total and offset > 0:
		offset = maxi(0,((total-1)/page_size)*page_size)
		options.offset = offset
		result = scene.library.query(options)
	scene.library_panel.present(result)
	for i in range(scene.library_panel.entries.item_count):
		var metadata: Dictionary = scene.library_panel.entries.get_item_metadata(i)
		if preferences.favorites.has(metadata.id): scene.library_panel.entries.set_item_text(i,"★ " + scene.library_panel.entries.get_item_text(i))
	page_label.text = "%d–%d / %d" % [offset+1 if total>0 else 0,mini(offset+page_size,total),total]
	previous_page.disabled = busy or offset==0
	next_page.disabled = busy or offset+page_size>=total
	selected()

func selected() -> void:
	var entries: ItemList = scene.library_panel.entries
	var selected_rows := entries.get_selected_items()
	if selected_rows.is_empty():
		details.text = "Select an entry to see details."
		return
	var item: Dictionary = entries.get_item_metadata(selected_rows[0])
	var date := Time.get_datetime_string_from_unix_time(int(clampf(item.created,0,253402300799)))
	details.text = "%s\n%s · %s UTC · %s bytes\nID: %s" % [item.title,item.kind,date,item.get("size_bytes",0),item.id]
	favorite_button.text = "★ Remove favorite" if preferences.favorites.has(item.id) else "☆ Favorite"

func toggle_favorite() -> void:
	if not _library_allowed(): return
	if not preferences.toggle_favorite(scene.library_panel.selected_id()):
		scene.library_panel.status.text = "Select a valid entry first."
		return
	var error: Error = preferences.save_to()
	refresh()
	if error != OK: scene.library_panel.status.text = "Favorite changed in memory; preferences could not be saved."

func duplicate_selected() -> void:
	if not _library_allowed(): return
	busy = true
	var result: Dictionary = scene.library.duplicate_entry(scene.library_panel.selected_id(),scene.library_panel.title_input.text)
	busy = false
	scene._library_feedback(result,"Entry duplicated with a new ID.")

func preview_selected() -> void:
	if not _library_allowed(): return
	busy = true
	var result: Dictionary = scene.library.preview(scene.library_panel.selected_id())
	busy = false
	if not result.ok: scene.library_panel.status.text = "Preview failed: " + _error(result)
	else: details.text += "\nTurn %d · %s · %d players\nTeam HP: %s · %d actions\nFingerprint: %s" % [result.turn,result.status,result.player_count,str(result.team_health),result.actions,result.fingerprint]

func pin_checkpoint() -> void:
	if not _library_allowed(): return
	comparison_id = scene.library_panel.selected_id()
	scene.library_panel.status.text = "Pinned checkpoint ID: " + comparison_id

func compare_selected() -> void:
	if not _library_allowed(): return
	var first: Dictionary = scene.library.load_entry(comparison_id)
	var second: Dictionary = scene.library.load_entry(scene.library_panel.selected_id())
	var result: Dictionary = Library.compare_checkpoints(first,second)
	details.text = "Compare failed: " + _error(result) if not result.ok else "Checkpoint comparison\nSame terrain: %s\nSame state: %s\nSame options: %s\nSame velocities: %s" % [result.same_world,result.same_state,result.same_options,result.same_velocities]

func show_diagnostics() -> void:
	if not _library_allowed(): return
	var health: Dictionary = scene.library.health_report()
	diagnostics_status.text = "%d entries · %d damaged · %d bytes\nDuplicate payload groups: %d" % [health.entries,health.invalid,health.size_bytes,health.duplicates.size()]
	invalid_entries.clear()
	for error in health.errors:
		var id: String = error.get("id","")
		var index := invalid_entries.add_item("%s — %s" % [id if not id.is_empty() else error.get("file","Library"),error.get("reason","invalid")])
		invalid_entries.set_item_metadata(index,id)
		invalid_entries.set_item_tooltip(index,invalid_entries.get_item_text(index))
	invalid_entries.visible = not health.errors.is_empty()

func confirm_corrupt_delete() -> void:
	if not _library_allowed() or invalid_entries.get_selected_items().is_empty(): return
	pending_corrupt = invalid_entries.get_item_metadata(invalid_entries.get_selected_items()[0])
	if not Library.valid_id(pending_corrupt):
		scene.library_panel.status.text = "This diagnostic has no safe entry ID to delete."
		return
	corrupt_confirmation.dialog_text = "Permanently delete this damaged archive?\nID: " + pending_corrupt
	corrupt_confirmation.popup_centered()

func delete_corrupt() -> void:
	if not _library_allowed(): return
	var result: Dictionary = scene.library.delete_entry(pending_corrupt)
	pending_corrupt = ""
	corrupt_confirmation.hide()
	scene._library_feedback(result,"Damaged entry deleted.")
	show_diagnostics()

func open_import() -> void:
	if not _library_allowed(): return
	busy = true
	export_kind = "import"
	pending_import_kind = "session" if import_kind.selected==0 else "replay"
	pending_title = scene.library_panel.title_input.text
	file_dialog.title = "Import " + pending_import_kind + " JSON"
	file_dialog.filters = PackedStringArray(["*.json ; JSON archive"])
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.popup_centered_ratio(0.75)

func open_raw_export() -> void:
	if not _library_allowed(): return
	export_id = scene.library_panel.selected_id()
	if not Library.valid_id(export_id):
		scene.library_panel.status.text = "Select an entry to export."
		return
	export_kind = "raw"
	_open_save("json","archive-"+export_id+".json")

func open_report_export(kind: String) -> void:
	if busy or not _inspector_allowed() or not report.get("ok",false):
		analysis_status.text = "Finish analysis before exporting a report."
		return
	export_kind = kind
	_open_save("json" if kind=="json" else "csv","replay-"+kind+(".json" if kind=="json" else ".csv"))

func _open_save(extension: String, filename: String) -> void:
	busy = true
	file_dialog.title = "Export " + export_kind
	file_dialog.filters = PackedStringArray(["*."+extension+" ; "+extension.to_upper()])
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.current_file = filename
	file_dialog.popup_centered_ratio(0.75)

func file_selected(path: String) -> void:
	if not busy: return
	file_dialog.hide()
	if scene.remote_mode or (scene.workflows != null and scene.workflows.training.active):
		cancel_dialog()
		return
	if export_kind == "import":
		if not scene.session.can_archive(): cancel_dialog(); return
		var title := pending_title if Library.valid_title(pending_title) else path.get_file().get_basename().left(48)
		var result: Dictionary = scene.library.import_file(pending_import_kind,path,title)
		busy = false
		scene._library_feedback(result,"Imported: " + title)
		return
	if FileAccess.file_exists(path):
		pending_path = path
		overwrite.dialog_text = "Replace this existing file?\n" + path
		overwrite.popup_centered()
		return
	_write_export(path,false)

func _write_export(path: String, replace: bool) -> void:
	if not busy: return
	var result := {"ok":false,"reason":"operation_no_longer_available"}
	var destination := ProjectSettings.globalize_path(path).simplify_path()
	var protected: bool = destination == ProjectSettings.globalize_path(preferences.path).simplify_path() or destination.get_base_dir()==scene.library.base_path
	if protected or not scene.library._safe_path(destination):
		result = {"ok":false,"reason":"unsafe_path"}
	elif not scene.remote_mode and (scene.workflows == null or not scene.workflows.training.active):
		if export_kind == "raw" and scene.session.can_archive(): result = scene.library.export_entry(export_id,path,replace)
		elif _inspector_allowed() and report.get("ok",false): result = Analyzer.export_report(path,report,export_kind,replace)
	var message := "Exported: " + path if result.ok else "Export failed: " + _error(result)
	if export_kind == "raw": scene.library_panel.status.text = message
	else: analysis_status.text = message
	cancel_dialog()

func cancel_dialog() -> void:
	busy = false
	pending_path = ""
	if file_dialog != null: file_dialog.hide()
	if overwrite != null: overwrite.hide()

func on_opened() -> void:
	cancel_analysis()
	active_playback = scene.session.playback
	opened_id = ""
	opened_fingerprint = ""
	report = {}
	shots.clear()
	turns.clear()
	statistics.text = ""
	progress.value = 0
	analysis_status.text = "Analyze to view statistics and shot bookmarks."
	loop_toggle.button_pressed = false
	_update_action()

func opened_entry(id: String) -> void:
	if scene.session.playback == null: return
	opened_id = id
	opened_fingerprint = scene.library.fingerprint(id)
	var cursor: int = preferences.cursor(id,opened_fingerprint,scene.session.playback.action_count)
	if cursor > 0: seek_index(cursor)

func remember_cursor() -> void:
	if opened_id.is_empty() or scene.session.playback == null: return
	preferences.remember(opened_id,opened_fingerprint,scene.session.playback.index)
	if preferences.save_to() != OK: analysis_status.text = "Could not save replay position."

func closing_replay() -> void:
	remember_cursor()
	cancel_analysis()
	cancel_dialog()
	active_playback = null
	opened_id = ""

func begin_analysis() -> void:
	if busy or analysis_running or not _inspector_allowed(): return
	analyzer = Analyzer.new()
	report = {}
	shots.clear()
	turns.clear()
	statistics.text = ""
	if not analyzer.begin(scene.session.playback.recording_copy()):
		analysis_status.text = "Analysis failed: " + analyzer.error
		analysis_running = false
		return
	analysis_running = true
	progress.value = 0
	analysis_status.text = "Analyzing recording…"

func cancel_analysis() -> void:
	if analysis_running and analyzer != null:
		analyzer.cancel()
		analysis_status.text = "Analysis cancelled."
	analysis_running = false

func update(_delta: float) -> void:
	if not _inspector_allowed():
		if analysis_running: cancel_analysis()
		return
	_update_action()
	if not analysis_running: return
	var result: Dictionary = analyzer.step(32)
	progress.max_value = maxi(1,scene.session.playback.action_count)
	progress.value = analyzer.index
	analysis_status.text = "Analyzed %d / %d actions" % [analyzer.index,scene.session.playback.action_count]
	if not result.ok:
		analysis_running = false
		analysis_status.text = "Analysis stopped at action %d (%s): %s" % [result.get("index",analyzer.index),result.get("type","unknown"),result.get("reason","error")]
	elif analyzer.finished:
		analysis_running = false
		report = analyzer.summary() # Final hash is expensive: exactly once, only on completion.
		_present_report()

func _present_report() -> void:
	if not report.get("ok",false): analysis_status.text = "Analysis failed: " + str(report.get("reason","error")); return
	analysis_status.text = "Analysis complete — %.2f seconds, %d actions" % [report.duration,report.action_count]
	var names := {}
	for player in report.players: names[player.id] = player.name
	var weapons: Dictionary = scene.session.playback.runner.weapons
	var lines := PackedStringArray(["Outcome: %s · winning team %s" % [report.status,report.winner_team],"Shots · Hits · Damage · Kills · Movement · Active time"])
	for player in report.players:
		lines.append("%s: %d · %d · %d · %d · %.2fm · %.2fs" % [player.name,player.shots,player.hits,player.damage,player.kills,player.distance,player.active_time])
	lines.append("Terrain: %d changed / %d destroyed" % [report.terrain.changed,report.terrain.destroyed])
	lines.append("Eliminations: %d" % report.eliminations.size())
	for weapon in report.weapons: lines.append("%s: %d shots, %d damage, %d kills" % [weapons[weapon.weapon_id].display_name,weapon.shots,weapon.damage,weapon.kills])
	statistics.text = "\n".join(lines)
	for shot in report.shots:
		var index := shots.add_item("%.2fs · %s · %s · damage %d / kills %d" % [shot.time,names.get(shot.player_id,shot.player_id),weapons[shot.weapon_id].display_name,shot.damage,shot.kills])
		shots.set_item_metadata(index,shot.index)
		shots.set_item_tooltip(index,shots.get_item_text(index))
	for turn in report.turns:
		var index := turns.add_item("%.2fs · Turn %d · %s" % [turn.time,turn.turn,names.get(turn.player_id,turn.player_id)])
		turns.set_item_metadata(index,turn.index)

func _update_action() -> void:
	if scene.session.playback == null: return
	action_label.text = scene.session.playback.action_description()
	if not scene.session.playback.last_error.is_empty(): action_label.text += "\nPlayback error: " + scene.session.playback.last_error

func seek_index(index: int) -> void:
	if busy or not _inspector_allowed(): return
	scene.session.playback.set_playing(false)
	if not scene.session.playback.seek(index):
		analysis_status.text = "Could not seek to action %d: %s" % [index,scene.session.playback.last_error]
		return
	scene._replace_local_runner(scene.session.playback.runner)
	scene._update_replay_status()
	_update_action()

func previous_shot() -> void:
	if busy or not _inspector_allowed(): return
	scene.session.playback.set_playing(false)
	if not scene.session.playback.previous_shot(): analysis_status.text = "No previous shot, or seek failed."; return
	scene._replace_local_runner(scene.session.playback.runner)
	scene._update_replay_status()
	_update_action()

func next_turn() -> void:
	if busy or not _inspector_allowed(): return
	scene.session.playback.set_playing(false)
	if not scene.session.playback.next_turn(): analysis_status.text = "No next turn, or seek failed."; return
	scene._replace_local_runner(scene.session.playback.runner)
	scene._update_replay_status()
	_update_action()

func on_playback_advanced(changed: bool) -> void:
	if changed and _inspector_allowed() and loop_toggle.button_pressed and scene.session.playback.finished and scene.session.playback.action_count>0:
		if scene.session.playback.seek(0):
			scene._replace_local_runner(scene.session.playback.runner)
			scene.session.playback.set_playing(true)

func handle_input(event: InputEvent) -> bool:
	if not _inspector_allowed() or busy or not event is InputEventKey or not event.pressed or event.echo or not event.ctrl_pressed: return false
	if event.keycode == KEY_LEFT: previous_shot(); return true
	if event.keycode == KEY_RIGHT: next_turn(); return true
	return false

func _error(result: Dictionary) -> String:
	return scene.library_panel.error_message(str(result.get("reason","unknown error")))

func _collect_existing_buttons(node: Node) -> void:
	for child in node.get_children():
		if child is Button and child.text not in ["Close","Return to match"] and not operation_buttons.has(child): operation_buttons.append(child)
		_collect_existing_buttons(child)

func _sync_busy() -> void:
	var blocked := busy or analysis_running
	for button in operation_buttons:
		if not is_instance_valid(button): continue
		if button == cancel_analysis_button: button.disabled = not analysis_running
		elif button == previous_page: button.disabled = blocked or offset==0
		elif button == next_page: button.disabled = blocked or offset+page_size>=_page_total
		else: button.disabled = blocked
	if search != null: search.editable = not blocked
	if sort_select != null: sort_select.disabled = blocked
	if favorites_only != null: favorites_only.disabled = blocked
	if import_kind != null: import_kind.disabled = blocked
