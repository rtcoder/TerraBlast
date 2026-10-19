extends Window
signal playtest_requested(count: int)
signal exit_requested
signal closed
const Registry = preload("res://scripts/core/maps/map_registry.gd")
const Store = preload("res://scripts/core/workshop/workshop_store.gd")
var document: RefCounted
var store = Store.new()
var buttons := {}
var metadata := {}
var fields := {}
var tabs: TabBar
var entries: ItemList
var preview: Control
var layer: SpinBox
var zoom_control: HSlider
var players: OptionButton
var report: Label
var notice: Label
var confirmation: ConfirmationDialog
var file_dialog: FileDialog
var shipped: OptionButton
var active_kind := "boxes"
var _syncing := false
var _pending := ""
var _pending_path := ""
var _dialog_action := ""
var _save_then_pending := false
func setup(value: RefCounted) -> void:
	hide()
	document = value
	name = "ArenaWorkshop"
	title = "Arena Workshop"
	force_native = true
	min_size = Vector2i(720,540)
	size = Vector2i(1180,820)
	unresizable = false
	var background := PanelContainer.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("102032")
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]: style.set_content_margin(side,12)
	background.add_theme_stylebox_override("panel",style)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	background.add_child(scroll)
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(page)
	var heading := Label.new()
	heading.text = "ARENA WORKSHOP  /  LOCAL MAP EDITOR"
	heading.add_theme_font_size_override("font_size",22)
	page.add_child(heading)
	var toolbar := HFlowContainer.new()
	page.add_child(toolbar)
	_button(toolbar,"new","New",func(): request_action("new"))
	shipped = OptionButton.new()
	shipped.name = "ShippedMaps"
	for id in Registry.PATHS:
		shipped.add_item(id.replace("_"," ").capitalize())
		shipped.set_item_metadata(shipped.item_count-1,id)
	toolbar.add_child(shipped)
	_button(toolbar,"shipped","Open shipped copy",func(): request_action("shipped"))
	_button(toolbar,"import","Import TOML…",func(): request_action("import"))
	_button(toolbar,"save","Save",save_current)
	_button(toolbar,"save_as","Save As…",func(): _show_file("save"))
	_button(toolbar,"undo","Undo",func(): document.undo(); refresh())
	_button(toolbar,"redo","Redo",func(): document.redo(); refresh())
	_button(toolbar,"exit","Return to match",func(): request_action("close"))
	var meta := GridContainer.new()
	meta.columns = 6
	page.add_child(meta)
	metadata.id = _text(meta,"ID","local_arena")
	metadata.map_name = _text(meta,"Name","Local Arena")
	metadata.theme = _text(meta,"Theme","workshop")
	metadata.dimensions = _vector(meta,"Dimensions",Vector3i(32,12,32),1,256)
	_button(meta,"metadata","Apply metadata",_apply_metadata)
	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.custom_minimum_size.y = 340
	page.add_child(body)
	var editing := VBoxContainer.new()
	editing.custom_minimum_size.x = 330
	body.add_child(editing)
	tabs = TabBar.new()
	for title_text in ["Boxes","Carves","Spawns"]: tabs.add_tab(title_text)
	tabs.tab_changed.connect(func(index):
		if not _syncing: choose_kind(["boxes","carves","spawns"][index]))
	editing.add_child(tabs)
	entries = ItemList.new()
	entries.name = "Operations"
	entries.custom_minimum_size.y = 130
	entries.item_selected.connect(select_entry)
	editing.add_child(entries)
	var form := GridContainer.new()
	form.columns = 2
	editing.add_child(form)
	fields.position = _vector(form,"Position",Vector3i(5,1,5),-1000000,1000000)
	fields.extent = _vector(form,"Size",Vector3i(3,3,3),1,256)
	fields.material = OptionButton.new()
	for code in ["air","dirt","stone","metal"]: fields.material.add_item(code)
	fields.material.select(1)
	_row(form,"Material",fields.material)
	fields.label = _text(form,"Label","")
	fields.custom_health = CheckBox.new()
	fields.custom_health.text = "Override material health"
	_row(form,"Health override",fields.custom_health)
	fields.health = _number(form,"Health",1,10000,100)
	fields.radius = _number(form,"Radius",1,256,1)
	fields.team = OptionButton.new()
	fields.team.add_item("Team 1 / blue")
	fields.team.add_item("Team 2 / red")
	_row(form,"Team",fields.team)
	fields.slot = _number(form,"Slot",0,31,0)
	fields.yaw = _number(form,"Yaw (degrees)",-36000,36000,0,0.1)
	var operations := HFlowContainer.new()
	editing.add_child(operations)
	_button(operations,"add","Add",func(): _apply_entry(true))
	_button(operations,"apply","Apply",func(): _apply_entry(false))
	_button(operations,"duplicate","Duplicate",func(): _result(document.duplicate_entry(active_kind,document.selection.index)))
	_button(operations,"delete","Delete",func(): _result(document.remove_entry(active_kind,document.selection.index)))
	_button(operations,"up","↑ Up",func(): _result(document.move_entry(active_kind,document.selection.index,-1)))
	_button(operations,"down","↓ Down",func(): _result(document.move_entry(active_kind,document.selection.index,1)))
	var visual := VBoxContainer.new()
	visual.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(visual)
	preview = preload("res://scripts/client/workshop/workshop_preview.gd").new()
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	visual.add_child(preview)
	preview.cell_selected.connect(func(position):
		for index in 3: fields.position[index].value = position[index])
	var viewbar := HBoxContainer.new()
	visual.add_child(viewbar)
	layer = _number(viewbar,"Layer Y",0,11,0)
	layer.value_changed.connect(func(value): if not _syncing: preview.set_layer(int(value)))
	zoom_control = HSlider.new()
	zoom_control.min_value = 0.25
	zoom_control.max_value = 4
	zoom_control.step = 0.05
	zoom_control.value = 1
	zoom_control.custom_minimum_size.x = 100
	zoom_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zoom_control.value_changed.connect(func(value): preview.set_zoom(value))
	viewbar.add_child(zoom_control)
	_button(viewbar,"fit","Fit",func(): preview.fit(); zoom_control.value = 1)
	var testing := HFlowContainer.new()
	page.add_child(testing)
	_button(testing,"validate","Validate",func(): refresh(); set_notice("Validation refreshed"))
	players = OptionButton.new()
	players.name = "PlaytestPlayers"
	testing.add_child(players)
	_button(testing,"playtest","Playtest arena",func():
		if players.selected >= 0: playtest_requested.emit(int(players.get_item_metadata(players.selected))))
	report = Label.new()
	report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(report)
	notice = Label.new()
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(notice)
	confirmation = ConfirmationDialog.new()
	confirmation.title = "Unsaved arena changes"
	confirmation.dialog_text = "Save your changes before continuing?"
	confirmation.ok_button_text = "Save"
	confirmation.cancel_button_text = "Cancel"
	confirmation.add_button("Discard",false,"discard")
	confirmation.confirmed.connect(func(): resolve_pending("save"))
	confirmation.canceled.connect(func(): resolve_pending("cancel"))
	confirmation.custom_action.connect(func(action): resolve_pending(action))
	add_child(confirmation)
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.toml ; TerraBlast arena"])
	file_dialog.file_selected.connect(_file_selected)
	file_dialog.canceled.connect(func(): _save_then_pending = false; _pending = "")
	add_child(file_dialog)
	close_requested.connect(func(): request_action("close"))
	window_input.connect(_window_input)
	refresh()
	hide()
func _row(parent: Node, label_text: String, control: Control) -> void:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	control.set_meta("field_label",label)
	parent.add_child(control)
func _text(parent: Node, label_text: String, value: String) -> LineEdit:
	var input := LineEdit.new()
	input.text = value
	input.custom_minimum_size.x = 110
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row(parent,label_text,input)
	return input
func _number(parent: Node, label_text: String, low: float, high: float, value: float, step := 1.0) -> SpinBox:
	var input := SpinBox.new()
	input.min_value = low
	input.max_value = high
	input.step = step
	input.value = value
	input.custom_minimum_size.x = 72
	_row(parent,label_text,input)
	return input
func _vector(parent: Node, label_text: String, value: Vector3i, low: float, high: float) -> Array[SpinBox]:
	var row := HBoxContainer.new()
	_row(parent,label_text,row)
	var result: Array[SpinBox] = []
	for axis in 3:
		var input := SpinBox.new()
		input.min_value = low
		input.max_value = high
		input.step = 1
		input.value = value[axis]
		input.custom_minimum_size.x = 70
		row.add_child(input)
		result.append(input)
	row.set_meta("vector_fields",result)
	return result
func _button(parent: Node, id: String, label_text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = id.to_pascal_case()
	button.text = label_text
	button.pressed.connect(callback)
	parent.add_child(button)
	buttons[id] = button
	return button
func present() -> void:
	refresh()
	var screen := DisplayServer.screen_get_usable_rect()
	if screen.size.x > 0 and screen.size.y > 0:
		size = Vector2i(mini(1180,screen.size.x-40),mini(820,screen.size.y-80)).max(min_size)
	popup_centered(size)
	grab_focus()
func choose_kind(kind: String) -> void:
	if kind not in ["boxes","carves","spawns"]: return
	active_kind = kind
	document.select(kind,0)
	refresh()
func select_entry(index: int) -> void:
	document.select(active_kind,index)
	refresh()
func _visibility(control: Control, value: bool) -> void:
	control.visible = value
	var label = control.get_meta("field_label",null)
	if label != null: label.visible = value
func refresh() -> void:
	if document == null or preview == null: return
	_syncing = true
	var definition = document.snapshot()
	title = "Arena Workshop — " + definition.display_name + (" *" if document.is_dirty() else "")
	metadata.id.text = definition.id
	metadata.map_name.text = definition.display_name
	metadata.theme.text = definition.theme
	for axis in 3: metadata.dimensions[axis].value = definition.size[axis]
	active_kind = document.selection.kind
	tabs.current_tab = ["boxes","carves","spawns"].find(active_kind)
	entries.clear()
	var collection: Array = definition.get(active_kind)
	for index in collection.size():
		var entry: Dictionary = collection[index]
		var label_text := str(entry.get("name",""))
		if label_text.is_empty(): label_text = "Team %s / slot %s" % [entry.get("team",1),entry.get("slot",0)] if active_kind == "spawns" else str(entry.get("material",entry.get("shape","sphere")))
		entries.add_item("%d • %s  %s" % [index,label_text,str(entry.position)])
	var selected: int = document.selection.index
	if selected >= 0 and selected < collection.size():
		entries.select(selected)
		var entry: Dictionary = collection[selected]
		for axis in 3: fields.position[axis].value = entry.position[axis]
		if active_kind == "boxes":
			for axis in 3: fields.extent[axis].value = entry.size[axis]
			fields.material.select(maxi(0,["air","dirt","stone","metal"].find(entry.get("material","dirt"))))
			fields.label.text = str(entry.get("name",""))
			fields.custom_health.button_pressed = entry.has("health")
			fields.health.min_value = 0 if entry.get("material") == "air" else 1
			fields.health.value = entry.get("health",100)
		elif active_kind == "carves": fields.radius.value = entry.get("radius",1)
		else:
			fields.team.select(int(entry.team)-1)
			fields.slot.value = entry.get("slot",0)
			fields.yaw.value = entry.get("yaw",0)
	for key in ["material","label","custom_health","health"]: _visibility(fields[key],active_kind == "boxes")
	_visibility(fields.extent[0].get_parent(),active_kind == "boxes")
	_visibility(fields.radius,active_kind == "carves")
	for key in ["team","slot","yaw"]: _visibility(fields[key],active_kind == "spawns")
	buttons.up.visible = active_kind == "boxes"
	buttons.down.visible = active_kind == "boxes"
	buttons.up.disabled = selected <= 0
	buttons.down.disabled = selected < 0 or selected >= collection.size()-1
	for key in ["apply","duplicate","delete"]: buttons[key].disabled = selected < 0
	buttons.undo.disabled = not document.can_undo()
	buttons.redo.disabled = not document.can_redo()
	var validation: Dictionary = document.validate()
	report.text = "Valid arena • supported players: " + str(validation.supported_counts) if validation.ok else "Validation errors:\n" + "\n".join(validation.errors)
	var previous_count: int = int(players.get_item_metadata(players.selected)) if players.selected >= 0 and players.item_count > 0 else 2
	players.clear()
	for count in validation.supported_counts:
		players.add_item("%d players" % count)
		players.set_item_metadata(players.item_count-1,count)
		if count == previous_count: players.select(players.item_count-1)
	buttons.playtest.disabled = not validation.ok or players.item_count == 0
	layer.max_value = definition.size.y-1
	layer.value = clampf(layer.value,0,layer.max_value)
	preview.present(definition,validation,document.selection)
	preview.set_layer(int(layer.value))
	_syncing = false
func set_notice(text: String) -> void: notice.text = text
func _result(result: Dictionary) -> void:
	set_notice("Changes applied" if result.ok else str(result.get("reason","Operation failed")))
	refresh()
func _read_vector(inputs: Array) -> Array: return [int(inputs[0].value),int(inputs[1].value),int(inputs[2].value)]
func _apply_metadata() -> void:
	var extent := _read_vector(metadata.dimensions)
	_result(document.set_metadata({"id":metadata.id.text,"name":metadata.map_name.text,"theme":metadata.theme.text,"size":Vector3i(extent[0],extent[1],extent[2])}))
func _apply_entry(adding: bool) -> void:
	var entry := {"position":_read_vector(fields.position)}
	if active_kind == "boxes":
		entry.size = _read_vector(fields.extent)
		entry.material = fields.material.get_item_text(fields.material.selected)
		entry.name = fields.label.text
		if fields.custom_health.button_pressed: entry.health = 0 if entry.material == "air" else int(fields.health.value)
		elif not adding: entry.health = null
	elif active_kind == "carves":
		entry.shape = "sphere"
		entry.radius = int(fields.radius.value)
	else:
		entry.team = fields.team.selected+1
		entry.slot = int(fields.slot.value)
		entry.yaw = float(fields.yaw.value)
	_result(document.add_entry(active_kind,entry) if adding else document.update_entry(active_kind,document.selection.index,entry))
func request_action(action: String, path := "") -> void:
	if document.is_dirty():
		_pending = action
		_pending_path = path
		confirmation.popup_centered()
	else: _perform(action,path)
func resolve_pending(decision: String) -> void:
	confirmation.hide()
	if decision == "cancel":
		_pending = ""
		return
	if decision == "save":
		if document.source_path.is_empty():
			_save_then_pending = true
			_show_file("save")
			return
		if not save_path(document.source_path): return
	_finish_pending()
func _finish_pending() -> void:
	var action := _pending
	var path := _pending_path
	_pending = ""
	_pending_path = ""
	_save_then_pending = false
	if not action.is_empty(): _perform(action,path)
func _perform(action: String, path: String) -> void:
	match action:
		"new": document.new_document(); refresh(); set_notice("New local arena")
		"shipped":
			var id: String = shipped.get_item_metadata(shipped.selected)
			var result: Dictionary = store.load_document(Registry.PATHS[id])
			if result.ok: document.replace_definition(result.definition); refresh(); set_notice("Editing a local copy of " + id)
			else: set_notice(result.reason)
		"import":
			if path.is_empty(): _show_file("import")
			else: import_path(path)
		"close": hide(); closed.emit(); exit_requested.emit()
func import_path(path: String) -> bool:
	var result: Dictionary = store.load_document(path)
	if not result.ok:
		set_notice(result.reason)
		return false
	document.replace_definition(result.definition,path if not path.begins_with("res://") else "")
	refresh()
	set_notice("Imported " + path)
	return true
func save_path(path: String) -> bool:
	var result: Dictionary = store.save_document(path,document.snapshot())
	if not result.ok:
		set_notice(str(result.get("reason","Save failed")))
		return false
	document.mark_saved(path)
	refresh()
	set_notice("Saved " + path)
	return true
func save_current() -> void:
	if document.source_path.is_empty(): _show_file("save")
	else: save_path(document.source_path)
func _show_file(action: String) -> void:
	_dialog_action = action
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if action == "save" else FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.title = "Save arena as TOML" if action == "save" else "Import arena TOML"
	if action == "save": file_dialog.current_file = document.snapshot().id + ".toml"
	file_dialog.popup_centered_ratio(0.8)
func _file_selected(path: String) -> void:
	if _dialog_action == "save":
		if save_path(path) and _save_then_pending: _finish_pending()
	else: import_path(path)
func _window_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_ESCAPE:
		request_action("close")
		set_input_as_handled()
	elif event.ctrl_pressed or event.meta_pressed:
		if event.keycode == KEY_S:
			save_current()
			set_input_as_handled()
		elif event.keycode == KEY_Z and not gui_get_focus_owner() is LineEdit:
			if event.shift_pressed: document.redo()
			else: document.undo()
			refresh()
			set_input_as_handled()
