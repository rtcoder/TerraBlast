extends SceneTree
const S=preload("res://scripts/networking/transport/match_server.gd")
const C=preload("res://scripts/networking/transport/match_client.gd")
var failures:=0
var owned:Array=[]
var profiles_path:=""
func check(ok:bool,label:String)->void:
	if not ok: failures+=1; push_error(label)
func _initialize()->void: call_deferred("run")
func until(test:Callable,label:String)->bool:
	var deadline:int=Time.get_ticks_msec()+12000
	while Time.get_ticks_msec()<deadline:
		if test.call(): return true
		await process_frame
	check(false,"Timeout: "+label); return false
func run()->void:
	root.size=Vector2i(1280,720)
	var probe:=PacketPeerUDP.new(); check(probe.bind(0,"127.0.0.1")==OK,"Scene UDP port")
	var port:int=probe.get_local_port(); probe.close()
	var server=S.new(); owned.append(server); root.add_child(server)
	server.apply_options({"spectator_capacity":1,"chat_enabled":true})
	if server.start(port)!=OK: check(false,"Scene server bind"); finish(); return
	var a=C.new(); var b=C.new()
	for c in [a,b]: owned.append(c); root.add_child(c); c.connect_to_server("127.0.0.1",port)
	if not await until(func(): return a.ready_for_match and b.ready_for_match,"Scene players"): finish(); return
	var scene=load("res://scenes/debug/VoxelDebug.tscn").instantiate()
	root.add_child(scene)
	profiles_path=("/private/tmp" if OS.get_name()=="macOS" else "/tmp").path_join("tb19-network-scene-profiles-%d.json" % OS.get_process_id())
	var profiles=preload("res://scripts/client/backend/connection_profiles.gd").new(profiles_path)
	scene.backend_menu.setup_profiles(profiles)
	check(scene.backend_menu.profiles.path==profiles_path and not profiles_path.begins_with("user://"),"Full scene profile persistence isolated from normal preferences")
	scene._begin_network_connection("127.0.0.1",port,"spectator")
	if not await until(func(): return scene.network.ready_for_match and scene.network.chat_enabled,"Scene spectator role and chat"): scene.queue_free(); finish(); return
	check(scene.network.role=="spectator" and not scene._can_control(),"Full scene spectator has no gameplay control")
	scene.lobby_panel.show(); scene._refresh_menu_state(); scene._present_lobby()
	scene.lobby_panel.follow_picker.select(1); scene.lobby_panel.follow_picker.item_selected.emit(1)
	check(scene.spectator_follow==scene.runner.state.players[0].player_id and scene._camera_subject().player_id==scene.spectator_follow,"Full scene follow camera hook")
	var panel=scene.lobby_panel.chat_panel
	panel.input.grab_focus(); await process_frame
	check(scene.chat_text_active,"Full scene chat input hook")
	panel.input.text="Widz online — Żółw [url]"; panel._submit()
	await until(func(): return scene.network.chat_messages.size()==1 and panel.pending.is_empty(),"Full scene send feedback and server echo")
	check(panel.input.text.is_empty() and server.chat.history().messages[0].author_role=="spectator","Full scene chat wiring authoritative")
	if OS.get_cmdline_user_args().has("--smoke"):
		scene.lobby_panel.show(); scene._refresh_menu_state()
		await process_frame
		await RenderingServer.frame_post_draw
		var saved:Error=root.get_texture().get_image().save_png("/private/tmp/tb19-network-native.png")
		check(saved==OK,"Native viewport capture")
		scene.preferences.hud_scale=1.25; scene._apply_client_preferences()
		await process_frame
		await process_frame
		scene.lobby_panel.scroll.scroll_vertical=int(scene.lobby_panel.scroll.get_v_scroll_bar().max_value)
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("/private/tmp/tb19-network-native125.png")==OK,"Native125percent bottom controls")
		print("Native spectator scene ready on isolated UDP port "+str(port))
		await create_timer(5).timeout
	scene.lobby_panel.hide(); await process_frame
	check(not scene.chat_text_active,"Full scene hide releases input")
	scene._disconnect_to_local(); await create_timer(0.35).timeout
	check(not scene.remote_mode and server.spectator_reservations.is_empty(),"Full scene leave releases reservation after scene network removal")
	scene.queue_free(); await process_frame; finish()
func finish()->void:
	for node in owned:
		if is_instance_valid(node): node.close(); node.queue_free()
	await process_frame
	if not profiles_path.is_empty() and FileAccess.file_exists(profiles_path): DirAccess.remove_absolute(profiles_path)
	print("network_scene19_next: %d failures"%failures)
	quit(1 if failures else 0)
