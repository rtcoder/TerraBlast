extends VBoxContainer
signal send_requested(text:String)
signal text_entry_changed(active:bool)
const Chat=preload("res://scripts/networking/messages/lobby_chat.gd")
var history_scroll:ScrollContainer
var rows:VBoxContainer
var input:LineEdit
var send_button:Button
var feedback:Label
var pending:Dictionary={}
var enabled:=false
var generation:=-1
var _signature:=""

func _ready()->void:
	var title:=Label.new(); title.text="Lobby chat"; add_child(title)
	history_scroll=ScrollContainer.new()
	history_scroll.custom_minimum_size=Vector2(0,140)
	history_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	add_child(history_scroll)
	rows=VBoxContainer.new(); rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	history_scroll.add_child(rows)
	input=LineEdit.new(); input.max_length=256; input.placeholder_text="Message (Enter sends)"; add_child(input)
	input.text_submitted.connect(func(_text:String): _submit())
	input.focus_entered.connect(func(): text_entry_changed.emit(true))
	input.focus_exited.connect(func(): text_entry_changed.emit(false))
	send_button=Button.new(); send_button.text="Send"; add_child(send_button)
	send_button.pressed.connect(_submit)
	feedback=Label.new(); feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; add_child(feedback)
	visibility_changed.connect(func():
		if not is_visible_in_tree(): reset_focus()
	)
	_update_enabled()

func present(value:Dictionary)->void:
	if not Chat.valid_history(value): return
	if generation!=int(value.generation):
		generation=int(value.generation); pending.clear(); feedback.text=""
	enabled=value.get("enabled",false)==true
	var signature:String=JSON.stringify(value.messages)
	if signature!=_signature:
		_signature=signature
		var bar:VScrollBar=history_scroll.get_v_scroll_bar()
		var stick:bool=bar.value>=bar.max_value-bar.page-10
		for child in rows.get_children(): rows.remove_child(child); child.queue_free()
		for event in value.messages:
			var label:=Label.new()
			label.text="%s%s: %s" % [event.author_name," (spectator)" if event.author_role=="spectator" else "",event.text]
			label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			label.custom_minimum_size.x=400
			rows.add_child(label)
		if stick: history_scroll.set_deferred("scroll_vertical",2147483647)
	if not pending.is_empty():
		for event in value.messages:
			if event.nonce==pending.get("nonce") and value.get("pending_nonce","")=="":
				pending.clear(); input.text=""; feedback.text="Sent"; break
	_update_enabled()

func _submit()->void:
	if not enabled or not pending.is_empty(): return
	if not Chat.valid_text(input.text): feedback.text="Use 1–256 printable characters."; return
	pending={"nonce":"","age":0.0}
	feedback.text="Waiting for server confirmation…"
	_update_enabled()
	send_requested.emit(input.text)

func send_result(value:Dictionary)->void:
	if not value.get("ok",false):
		pending.clear(); feedback.text=str(value.get("reason","chat_send_failed")); _update_enabled(); return
	if pending.is_empty(): return
	pending.nonce=value.get("nonce","")

func operation_rejected(nonce:String,reason:String)->void:
	if not pending.is_empty() and pending.get("nonce")==nonce:
		pending.clear(); feedback.text=reason.left(64); _update_enabled()

func reset_focus()->void:
	if input!=null: input.release_focus()
	pending.clear()
	text_entry_changed.emit(false)
	_update_enabled()

func _update_enabled()->void:
	if input==null: return
	input.editable=enabled and pending.is_empty()
	send_button.disabled=not enabled or not pending.is_empty()
	if not enabled: feedback.text="Chat disabled or disconnected."

func _process(delta:float)->void:
	if pending.is_empty(): return
	pending.age+=delta
	if pending.age>=5.0:
		pending.clear(); feedback.text="Chat confirmation timed out; draft kept."; _update_enabled()
