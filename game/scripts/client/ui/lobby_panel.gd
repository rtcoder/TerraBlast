extends PanelContainer
## Renders validated server state; buttons emit intent, never mutate readiness.
signal follow_player_requested(player_id:String)
signal chat_send_requested(text:String)
signal text_entry_changed(active:bool)
var chat_panel:VBoxContainer
var follow_picker:OptionButton
var follow_ids:Array[String]=[""]
var followed_player:=""
var _presented_role:="player"
var _presented_spectator_id:=""
signal ready_requested(value: bool)
signal name_requested(value: String)
signal rematch_requested(value: bool)
signal disconnect_requested
signal close_requested
signal retry_requested
const Protocol=preload("res://scripts/networking/messages/match_protocol.gd")
var pending_operations := {}
var pending_generation := -1
var _presented_state := {}
var _presented_id := ""
var _presented_phase := "waiting"
var _presented_sync := false
var disconnect_confirmation: ConfirmationDialog
var connection_label: Label
var retry_button: Button
var summary: Label
var roster_label: Label
var name_label:Label
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
	name_label=_label("Your display name (before the match)")
	name_input = LineEdit.new()
	name_input.max_length = 24
	box.add_child(name_input)
	name_input.text_submitted.connect(func(_value): _request_name())
	name_apply = _button("Apply name",_request_name)
	ready_button = _button("Ready",_request_ready)
	rematch_button = _button("Vote rematch",_request_rematch)
	follow_picker=OptionButton.new()
	box.add_child(follow_picker)
	follow_picker.item_selected.connect(func(index:int):
		if index>=0 and index<follow_ids.size():
			followed_player=follow_ids[index]; follow_player_requested.emit(followed_player)
	)
	chat_panel=preload("res://scripts/client/ui/lobby_chat_panel.gd").new()
	box.add_child(chat_panel)
	chat_panel.send_requested.connect(func(text:String): chat_send_requested.emit(text))
	chat_panel.text_entry_changed.connect(func(active:bool): text_entry_changed.emit(active))
	feedback = _label("")
	connection_label=_label("")
	retry_button=_button("Retry connection",func(): retry_requested.emit())
	retry_button.disabled=true
	_button("Disconnect to local",_confirm_disconnect)
	disconnect_confirmation=ConfirmationDialog.new()
	add_child(disconnect_confirmation)
	disconnect_confirmation.dialog_text="Leave the online match and return to local play? Your slot may remain reserved briefly; deliberate departure forgets the resume token."
	disconnect_confirmation.confirmed.connect(func(): disconnect_requested.emit())
	visibility_changed.connect(func():
		if not visible:
			disconnect_confirmation.hide()
			chat_panel.reset_focus()
	)
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
func present(state: Dictionary, own_id: String, phase: String, synchronized: bool, role:String="player", spectator_id:String="") -> void:
	_presented_role=role
	name_label.text="Your spectator name" if role=="spectator" else "Your display name (before the match)"
	_presented_spectator_id=spectator_id
	_presented_state=state.duplicate(true)
	_presented_id=own_id
	_presented_phase=phase
	_presented_sync=synchronized
	if state.get("generation",-1)!=pending_generation:
		pending_operations.clear()
		pending_generation=state.get("generation",-1)
	if not synchronized: pending_operations.clear()
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
	var viewers:Array=state.get("spectators",[])
	if role=="spectator":
		own={}
		for row in viewers:
			if row.id==spectator_id: own=row
	var viewer_lines:Array[String]=[]
	for row in viewers:
		viewer_lines.append("%s%s — %s" % [row.name," [you]" if row.id==spectator_id else "","Watching" if row.connected else "Reserved"])
	for operation in pending_operations.keys():
		var field: String={"ready":"ready","name":"name","rematch":"rematch"}[operation]
		if own.get(field)==pending_operations[operation].value: pending_operations.erase(operation)
	var capacity: int = state.get("capacity",0)
	summary.text = "%d / %d connected | %d ready | %d / %d rematch votes\n%s" % [connected,capacity,ready,votes,capacity,waiting_text(state,phase,synchronized)]
	roster_label.text = "\n".join(lines)
	if not viewers.is_empty(): roster_label.text+="\nSpectators (%d / %d):\n%s" % [viewers.size(),state.get("spectator_capacity",0),"\n".join(viewer_lines)]
	if role=="spectator": summary.text="Observing — gameplay is read-only\n"+summary.text
	_update_follow(state,role,synchronized)
	_own_ready = own.get("ready",false)
	_own_vote = own.get("rematch",false)
	var pregame: bool = synchronized and role=="player" and not own.is_empty() and not state.get("started",false)
	var can_name:bool=synchronized and not own.is_empty() and (role=="spectator" or pregame)
	ready_button.disabled = not pregame or not state.get("require_ready",false) or pending_operations.has("ready")
	ready_button.text = "Not ready" if _own_ready else "Ready"
	name_input.editable = can_name
	name_apply.disabled = not can_name or pending_operations.has("name")
	var name: String = own.get("name", "")
	if name != _last_name and not name_input.has_focus():
		name_input.text = name
		_last_name = name
	rematch_button.disabled = role!="player" or not synchronized or own.is_empty() or phase != "ended" or not state.get("require_ready",false) or pending_operations.has("rematch")
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
func _process(delta: float) -> void:
	for operation in pending_operations.keys():
		pending_operations[operation].age+=delta
		if pending_operations[operation].age>=5.0:
			pending_operations.erase(operation)
			feedback.text="Server confirmation timed out; try again."
			_refresh_presented()
	scroll.custom_minimum_size.y = minf(box.get_combined_minimum_size().y, maxf(150,get_viewport_rect().size.y - 90))

func _request_ready() -> void:
	if ready_button.disabled or pending_operations.has("ready"): return
	pending_operations.ready={"value":not _own_ready,"age":0.0}
	ready_button.disabled=true
	feedback.text="Waiting for server confirmation…"
	ready_requested.emit(not _own_ready)
func _request_name() -> void:
	if name_apply.disabled or pending_operations.has("name"): return
	var value:=name_input.text.strip_edges()
	if not Protocol.valid_display_name(value): feedback.text="Name must contain 1–24 printable characters."; return
	pending_operations.name={"value":value,"age":0.0}
	name_apply.disabled=true
	feedback.text="Waiting for name confirmation…"
	name_requested.emit(value)
func _request_rematch() -> void:
	if rematch_button.disabled or pending_operations.has("rematch"): return
	pending_operations.rematch={"value":not _own_vote,"age":0.0}
	rematch_button.disabled=true
	feedback.text="Waiting for vote confirmation…"
	rematch_requested.emit(not _own_vote)
func operation_rejected(reason: String) -> void:
	pending_operations.clear()
	feedback.text=reason.substr(0,256)
	_refresh_presented()
func _confirm_disconnect() -> void: disconnect_confirmation.popup_centered()
func present_connection(value: Dictionary) -> void:
	if connection_label==null: return
	var progress: Dictionary=value.get("progress",{})
	connection_label.text="%s · %s · %d/%d chunks · RTT %s\n%s" % [value.get("role","player"),value.get("state","disconnected"),progress.get("completed",0),progress.get("total",0),str(value.latency_ms)+" ms" if value.get("latency_ms",-1)>=0 else "unavailable",value.get("last_error","")]
	retry_button.disabled=not value.get("can_retry",false)
	if value.get("state") in ["error","disconnected"]:
		pending_operations.clear()
		if chat_panel!=null:
			chat_panel.enabled=false; chat_panel.reset_focus()
		if not followed_player.is_empty(): followed_player=""; follow_player_requested.emit("")
	if disconnect_confirmation!=null:
		disconnect_confirmation.dialog_text="Leave observation and release your spectator slot?" if value.get("role")=="spectator" else "Leave the online match and release your player reservation?"

func _refresh_presented() -> void:
	present(_presented_state,_presented_id,_presented_phase,_presented_sync,_presented_role,_presented_spectator_id)

func _update_follow(state:Dictionary,role:String,synchronized:bool)->void:
	var names:Array[String]=["Free camera"]
	var ids:Array[String]=[""]
	for row in state.get("roster",[]):
		ids.append(row.id); names.append("Follow "+row.name)
	follow_picker.set_block_signals(true)
	follow_picker.clear()
	for name in names: follow_picker.add_item(name)
	follow_ids=ids
	if not ids.has(followed_player) or role!="spectator" or not synchronized:
		if not followed_player.is_empty(): followed_player=""; follow_player_requested.emit("")
	follow_picker.select(maxi(0,ids.find(followed_player)))
	follow_picker.set_block_signals(false)
	follow_picker.visible=role=="spectator"
	follow_picker.disabled=not synchronized

func present_chat(value:Dictionary)->void:
	if chat_panel!=null: chat_panel.present(value)
func chat_send_result(value:Dictionary)->void:
	if chat_panel!=null: chat_panel.send_result(value)
func chat_operation_rejected(nonce:String,reason:String)->void:
	if chat_panel!=null: chat_panel.operation_rejected(nonce,reason)
