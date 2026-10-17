extends PanelContainer
## Emits user intent; never mutates a match or filesystem.
signal close_requested
signal refresh_requested
signal save_requested(kind: String, title: String)
signal load_requested(id: String)
signal rename_requested(id: String, title: String)
signal delete_requested(id: String)
signal import_requested(kind: String, title: String)
var filter: OptionButton
var entries: ItemList
var title_input: LineEdit
var status: Label
var confirmation: ConfirmationDialog
var pending_delete := ""
var box: VBoxContainer
var scroll: ScrollContainer
func _ready() -> void:
	position = Vector2(30,30)
	custom_minimum_size = Vector2(530,0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025,0.04,0.08,0.98)
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]: style.set_content_margin(side,14)
	add_theme_stylebox_override("panel",style)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation",8)
	scroll.add_child(box)
	var heading := Label.new()
	heading.text = "Local library — F8"
	box.add_child(heading)
	filter = OptionButton.new()
	for item in ["All", "Sessions", "Replays"]: filter.add_item(item)
	filter.item_selected.connect(func(_index): refresh_requested.emit())
	box.add_child(filter)
	entries = ItemList.new()
	entries.custom_minimum_size = Vector2(490,150)
	entries.item_selected.connect(func(index): title_input.text = entries.get_item_metadata(index).title)
	box.add_child(entries)
	title_input = LineEdit.new()
	title_input.placeholder_text = "Name (1–48 characters)"
	title_input.max_length = 48
	box.add_child(title_input)
	_row(["Save checkpoint", "Save replay"], [func(): save_requested.emit("session",title_input.text),func(): save_requested.emit("replay",title_input.text)])
	_row(["Open selected", "Rename selected"], [func(): load_requested.emit(selected_id()),func(): rename_requested.emit(selected_id(),title_input.text)])
	_row(["Delete selected", "Refresh"], [_confirm_delete,func(): refresh_requested.emit()])
	_row(["Import quick save", "Import last replay"], [func(): import_requested.emit("session",title_input.text),func(): import_requested.emit("replay",title_input.text)])
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status)
	_row(["Close"],[func(): close_requested.emit()])
	confirmation = ConfirmationDialog.new()
	confirmation.title = "Delete library entry"
	add_child(confirmation)
	confirmation.confirmed.connect(func():
		var id := pending_delete
		pending_delete = ""
		delete_requested.emit(id)
	)
	visibility_changed.connect(func():
		if not visible:
			confirmation.hide()
			pending_delete = ""
	)
	hide()
func _row(labels: Array, callbacks: Array) -> void:
	var row := HBoxContainer.new()
	box.add_child(row)
	for index in labels.size():
		var button := Button.new()
		button.text = labels[index]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(callbacks[index])
		row.add_child(button)
func selected_id() -> String:
	var selected := entries.get_selected_items()
	return str(entries.get_item_metadata(selected[0]).id) if not selected.is_empty() else ""
func selected_kind() -> String:
	return ["","session","replay"][filter.selected]
func present(result: Dictionary) -> void:
	var prior := selected_id()
	entries.clear()
	for entry in result.get("entries",[]):
		var date := Time.get_datetime_string_from_unix_time(int(clampf(float(entry.created),0,253402300799))).replace("T"," ").left(16)
		var index := entries.add_item("%s · %s · %s" % [entry.title,entry.kind,date])
		entries.set_item_metadata(index,entry)
		entries.set_item_tooltip(index,"%s\n%s · %s\n%s" % [entry.title,entry.kind,date,entry.id])
		if entry.id == prior: entries.select(index)
	var errors: Array = result.get("errors",[])
	status.text = "%d entries" % entries.item_count if result.ok else str(result.get("reason","Library unavailable"))
	if not errors.is_empty(): status.text += "\n%d invalid entries: %s" % [errors.size(),str(errors[0].get("reason","Invalid file"))]
func _confirm_delete() -> void:
	pending_delete = selected_id()
	if pending_delete.is_empty():
		status.text = "Select an entry first."
		return
	var index := entries.get_selected_items()[0]
	confirmation.dialog_text = "Permanently delete “%s”?" % entries.get_item_metadata(index).title
	confirmation.popup_centered()
func _process(_delta: float) -> void:
	scroll.custom_minimum_size.y = minf(box.get_combined_minimum_size().y,maxf(150,get_viewport_rect().size.y-90))
