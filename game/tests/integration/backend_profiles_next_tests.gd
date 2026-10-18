extends SceneTree
class PendingLogin:
	extends "res://scripts/client/backend/nakama_client.gd"
	func _start_http_request(_http: HTTPRequest,_url: String,_headers: PackedStringArray,_body: String) -> Error: return OK
var failures:=0
func check(ok: bool,label: String) -> void:
	if not ok: failures+=1; push_error(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var menu=load("res://scripts/client/backend/backend_menu.gd").new()
	var profiles=load("res://scripts/client/backend/connection_profiles.gd").new(("/private/tmp" if OS.get_name()=="macOS" else "/tmp").path_join("tb-menu-%d.json")%OS.get_process_id())
	menu.setup_profiles(profiles)
	root.add_child(menu)
	menu.profile_title.text="Test endpoint"
	menu._add_profile()
	check(profiles.list_profiles().size()==1,"Favorite add in menu")
	menu.host.text="invalid/path"
	menu._connect_game()
	check(menu.status.text.contains("Invalid"),"Invalid direct connect rejected")
	menu.record_connection_success("127.0.0.1",19170)
	menu._use_last()
	check(menu.host.text=="127.0.0.1","Last successful endpoint")
	menu.present_game_connection({"state":"error","can_retry":true,"last_error":"timeout"})
	check(not menu.retry_button.disabled and menu.game_status.text.contains("timeout"),"Retry and error presentation")
	var nakama=menu.backend
	check(not nakama.set_endpoint("file:///secret") and nakama.base_url=="http://127.0.0.1:7350","Backend invalid endpoint atomic")
	nakama.pending_requests["known"]=true
	nakama._accept_message({"cid":"unknown","match":{}})
	check(nakama.responses.is_empty(),"Unsolicited response ignored")
	nakama._accept_message({"cid":"known","error":"wrong shape"})
	check(nakama.responses.known.error.message=="Invalid Nakama response","Malformed response controlled")
	var auth=PendingLogin.new()
	root.add_child(auth)
	auth.token="previous-token"
	var outcome:={"done":false,"ok":true}
	_start_login(auth,outcome)
	auth.close()
	await process_frame
	check(outcome.done and not outcome.ok and auth.token=="previous-token" and auth.active_http==null,"Cancelled HTTP cannot publish late login")
	var old_result:={"done":false,"ok":true}
	var new_result:={"done":false,"ok":false}
	_start_login(auth,old_result)
	var old_http=auth.active_http
	_start_login(auth,new_result)
	old_http.request_completed.emit(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),'{"token":"stale"}'.to_utf8_buffer())
	auth.active_http.request_completed.emit(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),'{"token":"fresh"}'.to_utf8_buffer())
	await process_frame
	check(old_result.done and not old_result.ok and new_result.ok and auth.token=="fresh","New login wins over stale HTTP completion")
	auth.queue_free()
	check(nakama.set_endpoint("http://localhost:7350") and nakama.token.is_empty(),"Endpoint change clears credentials")
	menu._disconnect_backend()
	check(not menu.busy and nakama.connection_state=="disconnected","Explicit disconnect clears busy")
	menu.queue_free()
	await process_frame
	DirAccess.remove_absolute(profiles.path)
	print("backend_profiles_next: %d failures"%failures)
	quit(1 if failures else 0)

func _start_login(client: Node,outcome: Dictionary) -> void:
	outcome.ok=await client.guest_login("terrablast-cancel-test250")
	outcome.done=true
