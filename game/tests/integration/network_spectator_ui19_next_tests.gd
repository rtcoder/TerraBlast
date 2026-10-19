extends SceneTree
const L=preload("res://scripts/client/ui/lobby_panel.gd")
const Chat=preload("res://scripts/networking/messages/lobby_chat.gd")
var failures:=0
func check(ok:bool,label:String)->void:
	if not ok: failures+=1; push_error(label)
func _initialize()->void: call_deferred("run")
func run()->void:
	root.size=Vector2i(1280,720)
	var lobby=L.new(); root.add_child(lobby); lobby.show()
	var viewer:String="spectator_"+"a".repeat(32)
	var state:Dictionary={"capacity":2,"generation":0,"require_ready":true,"started":true,"roster":[{"id":"blue_1","name":"Blue","team":1,"connected":true,"ready":false,"rematch":false},{"id":"red_1","name":"Red","team":2,"connected":true,"ready":false,"rematch":false}],"spectator_capacity":2,"spectators":[{"id":viewer,"name":"Widz","connected":true}]}
	lobby.present(state,"","playing",true,"spectator",viewer)
	var requests:Array=[]
	lobby.ready_requested.connect(func(v): requests.append(v))
	lobby.rematch_requested.connect(func(v): requests.append(v))
	lobby._request_ready(); lobby._request_rematch()
	check(requests.is_empty() and lobby.ready_button.disabled and lobby.rematch_button.disabled,"Viewer UI cannot ready or rematch")
	check(lobby.summary.text.contains("2 / 2 connected") and lobby.summary.text.contains("Observing") and lobby.roster_label.text.contains("Widz [you]"),"Separate role and counters")
	var names:Array=[]; lobby.name_requested.connect(func(v): names.append(v))
	lobby.name_input.text="Nowy Widz"; lobby._request_name()
	check(names==["Nowy Widz"] and lobby.name_input.editable,"Observer rename while playing")
	state.spectators[0].name="Nowy Widz"; lobby.present(state,"","playing",true,"spectator",viewer)
	check(not lobby.pending_operations.has("name"),"Observer name authority confirms")
	var targets:Array=[]; lobby.follow_player_requested.connect(func(v): targets.append(v))
	lobby.follow_picker.select(1); lobby.follow_picker.item_selected.emit(1)
	check(targets==["blue_1"] and lobby.followed_player=="blue_1","Follow emits actual player identity")
	state.roster.remove_at(0); lobby.present(state,"","playing",true,"spectator",viewer)
	check(targets.back()=="" and lobby.followed_player=="","Missing follow target returns free camera")
	var panel=lobby.chat_panel
	var model=Chat.new(); model.reset(0)
	var event:Dictionary=model.append({"id":"blue_1","name":"Blue","role":"player"},"[url]literal Żółw 😀","a".repeat(32),0,0).event
	var history:Dictionary=model.history(); history.enabled=true; history.pending_nonce=""
	lobby.present_chat(history)
	check(panel.rows.get_child_count()==1 and panel.rows.get_child(0) is Label and panel.rows.get_child(0).text.contains("[url]literal"),"Chat renders plain literal text")
	var sends:Array=[]
	lobby.chat_send_requested.connect(func(text):
		sends.append(text); lobby.chat_send_result({"ok":true,"nonce":"b".repeat(32)})
	)
	panel.input.text="Reply"; panel.input.text_submitted.emit("Reply"); panel._submit()
	check(sends==["Reply"] and not panel.pending.is_empty() and panel.input.text=="Reply","Enter and repeat wait for echo")
	lobby.chat_operation_rejected("b".repeat(32),"chat_rate_limit")
	check(panel.pending.is_empty() and panel.input.text=="Reply" and not panel.send_button.disabled,"Reject preserves draft and unlocks")
	panel._submit()
	event=model.append({"id":viewer,"name":"Nowy Widz","role":"spectator"},"Reply","b".repeat(32),0,10001).event
	history=model.history(); history.enabled=true; history.pending_nonce=""
	lobby.present_chat(history)
	check(panel.pending.is_empty() and panel.input.text.is_empty(),"Only matching server echo clears draft")
	panel.input.text="Timeout draft"; panel._submit(); panel._process(5.1)
	check(panel.pending.is_empty() and panel.input.text=="Timeout draft","Pending timeout preserves draft")
	var focus:Array=[]; lobby.text_entry_changed.connect(func(active): focus.append(active))
	panel.input.grab_focus(); await process_frame
	check(panel.input.has_focus() and focus.has(true),"Text focus exposes gameplay block hook")
	lobby.hide(); await process_frame
	check(not panel.input.has_focus() and focus.back()==false and panel.pending.is_empty(),"Hide releases focus and pending")
	for i in range(100): model.append({"id":"blue_1","name":"Blue","role":"player"},"Row "+str(i),str(i).sha256_text().left(32),0,(i+2)*10001)
	history=model.history(); history.enabled=true; lobby.present_chat(history)
	check(panel.rows.get_child_count()<=64,"History tree bounded")
	var menu=load("res://scripts/client/backend/backend_menu.gd").new(); menu.set_selected_role("spectator"); root.add_child(menu)
	check(menu.selected_role()=="spectator" and menu.role_picker.selected==1,"Pre-ready CLI role selection")
	menu.set_selected_role("invalid"); check(menu.selected_role()=="spectator","Bad menu role ignored")
	menu.role_picker.select(0); menu.role_picker.item_selected.emit(0)
	check(menu.selected_role()=="player","Picker changes future join role")
	lobby.queue_free(); menu.queue_free(); await process_frame
	print("network_spectator_ui19_next: %d failures"%failures)
	quit(1 if failures else 0)
