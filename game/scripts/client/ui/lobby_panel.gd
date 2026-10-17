extends PanelContainer
## Renders validated server state; buttons emit intent, never mutate readiness.
signal ready_requested(value: bool)
signal name_requested(value: String)
signal rematch_requested(value: bool)
signal disconnect_requested
signal close_requested
var summary: Label
var roster_label: Label
var name_input: LineEdit
var name_apply: Button
var ready_button: Button
var rematch_button: Button
var feedback: Label
var _own_ready := false
var _own_vote := false
var _last_name := ""
var scroll: ScrollContainer
var box: VBoxContainer
func _ready() -> void:
	position = Vector2(30,30)
	custom_minimum_size.x = 520
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.025,0.04,0.08,0.97)
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		background.set_content_margin(side,14)
	add_theme_stylebox_override("panel",background)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation",8)
	scroll.add_child(box)
	_label("Match lobby — F7 to close")
	summary = _label("")
	roster_label = _label("")
	_label("Your display name (before the match)")
	name_input = LineEdit.new()
	name_input.max_length = 24
	box.add_child(name_input)
	name_apply = _button("Apply name",func(): name_requested.emit(name_input.text))
	ready_button = _button("Ready",func(): ready_requested.emit(not _own_ready))
	rematch_button = _button("Vote rematch",func(): rematch_requested.emit(not _own_vote))
	feedback = _label("")
	_button("Disconnect to local",func(): disconnect_requested.emit())
	_button("Close",func(): close_requested.emit())
	hide()
func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 470
	box.add_child(label)
	return label
func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	box.add_child(button)
	return button
func present(state: Dictionary, own_id: String, phase: String, synchronized: bool) -> void:
	var own := {}
	var connected := 0
	var ready := 0
	var votes := 0
	var lines: Array[String] = []
	for row in state.get("roster", []):
		connected += int(row.connected)
		ready += int(row.ready)
		votes += int(row.rematch)
		if row.id == own_id:
			own = row
		var status := "Ready" if row.ready else "Connected"
		if not row.connected:
			status = "Vacant / reserved"
		lines.append("%s%s — %s — %s%s" % [row.name, " [you]" if row.id == own_id else "", "Blue" if row.team == 1 else "Red", status, " — rematch vote" if row.rematch else ""])
	var capacity: int = state.get("capacity",0)
	summary.text = "%d / %d connected | %d ready | %d / %d rematch votes\n%s" % [connected,capacity,ready,votes,capacity,waiting_text(state,phase,synchronized)]
	roster_label.text = "\n".join(lines)
	_own_ready = own.get("ready",false)
	_own_vote = own.get("rematch",false)
	var pregame: bool = synchronized and not own.is_empty() and not state.get("started",false)
	ready_button.disabled = not pregame or not state.get("require_ready",false)
	ready_button.text = "Not ready" if _own_ready else "Ready"
	name_input.editable = pregame
	name_apply.disabled = not pregame
	var name: String = own.get("name", "")
	if name != _last_name and not name_input.has_focus():
		name_input.text = name
		_last_name = name
	rematch_button.disabled = not synchronized or own.is_empty() or phase != "ended" or not state.get("require_ready",false)
	rematch_button.text = "Cancel rematch vote" if _own_vote else "Vote rematch"
static func waiting_text(state: Dictionary, phase: String, synchronized: bool) -> String:
	if not synchronized:
		return "Connection unavailable or synchronizing — F4 retries"
	if state.is_empty():
		return phase
	var connected := 0
	var ready := 0
	for row in state.roster:
		connected += int(row.connected)
		ready += int(row.ready)
	if phase == "ended":
		return "Match finished — all connected players must agree to rematch" if state.require_ready else "Match finished — Blue 1 can restart"
	if connected < state.capacity:
		return "Paused: waiting for reconnect (%d / %d)" % [connected,state.capacity] if state.started else "Waiting for players (%d / %d)" % [connected,state.capacity]
	if state.require_ready and not state.started:
		return "Waiting for ready (%d / %d)" % [ready,state.capacity]
	return "Projectile in flight" if phase == "playback" else "Match in progress"
func _process(_delta: float) -> void:
	scroll.custom_minimum_size.y = minf(box.get_combined_minimum_size().y, maxf(150,get_viewport_rect().size.y - 90))
