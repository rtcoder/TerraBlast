extends SceneTree
const S=preload("res://scripts/networking/transport/match_server.gd")
const C=preload("res://scripts/networking/transport/match_client.gd")
const P=preload("res://scripts/networking/messages/match_protocol.gd")
class Legacy:
	extends "res://scripts/networking/transport/match_client.gd"
	func _send(data:Dictionary)->Error:
		if data.get("type")=="hello": data.erase("role"); data.erase("extensions")
		return super._send(data)
var failures:=0
var owned:Array=[]
func check(ok:bool,label:String)->void:
	if not ok: failures+=1; push_error(label)
func _initialize()->void: call_deferred("run")
func until(test:Callable,label:String,seconds:float=10.0)->bool:
	var deadline:int=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		if test.call(): return true
		await process_frame
	check(false,"Timeout: "+label); return false
func client(port:int,role:String="player")->Node:
	var c=C.new(); owned.append(c); root.add_child(c); c.connect_to_server("127.0.0.1",port,role); return c
func run()->void:
	var probe:=PacketPeerUDP.new(); check(probe.bind(0,"127.0.0.1")==OK,"Independent chat UDP port")
	var port:int=probe.get_local_port(); probe.close()
	var server=S.new(); owned.append(server); root.add_child(server)
	server.apply_options({"spectator_capacity":2,"chat_enabled":true,"snapshot_chunks_per_frame":1})
	if server.start(port)!=OK: check(false,"Chat server bind"); finish(); return
	var a=client(port)
	var legacy=Legacy.new(); owned.append(legacy); root.add_child(legacy); legacy.connect_to_server("127.0.0.1",port)
	if not await until(func(): return a.ready_for_match and legacy.ready_for_match and a.chat_enabled,"Chat player and legacy sync"): finish(); return
	check(server.slots.size()==2 and server.peer_extensions.values().any(func(v): return v.is_empty()),"Real legacy hello keeps player slot")
	var pending_peer:=ENetMultiplayerPeer.new()
	check(pending_peer.create_client("127.0.0.1",port)==OK,"Unidentified peer socket")
	await until(func():
		pending_peer.poll()
		return pending_peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED and not server.pending.is_empty(),"Unidentified peer reaches pending hello")
	check(a.send_chat("Pierwsza Żółw [url]").ok,"Player send accepted locally")
	await until(func(): return a.chat_messages.size()==1 and a.chat_pending.is_empty(),"Player server echo")
	pending_peer.poll()
	check(pending_peer.get_available_packet_count()==0,"No chat broadcast reaches pending unauthenticated peer")
	pending_peer.close()
	var second_nonce:String="b".repeat(32)
	a._send({"type":"chat_send","text":"Second","nonce":second_nonce,"generation":0})
	await until(func(): return a.chat_messages.size()==2,"Second event")
	var spectator=client(port,"spectator")
	await until(func(): return spectator.staging!=null,"Observer history slow transfer")
	a._send({"type":"chat_send","text":"During snapshot","nonce":"c".repeat(32),"generation":0})
	await until(func(): return spectator.ready_for_match and spectator.chat_messages.size()==3,"History plus concurrent live chat")
	check(spectator.chat_messages==a.chat_messages and spectator.chat_sequence==3,"Late chat converges exactly once")
	check(legacy.chat_messages.is_empty(),"Legacy client not sent unnegotiated chat events")
	check(spectator.send_chat("Widz mówi 😀").ok,"Observer may send chat")
	await until(func(): return a.chat_messages.size()==4 and spectator.chat_pending.is_empty(),"Both roles receive same event")
	var last:Dictionary=a.chat_messages.back()
	check(last.author_id==spectator.spectator_id and last.author_role=="spectator" and last.sequence==4,"Server assigns spectator attribution")
	var nonce:String="d".repeat(32)
	spectator._send({"type":"chat_send","text":"Spoof","nonce":nonce,"generation":0,"author_id":a.player_id})
	spectator._send({"type":"chat_send","text":"bad\ntext","nonce":"e".repeat(32),"generation":0})
	spectator._send({"type":"chat_send","text":"Old","nonce":"f".repeat(32),"generation":7})
	a._send({"type":"chat_send","text":"Duplicate with changed text","nonce":second_nonce,"generation":0})
	await create_timer(0.1).timeout
	check(server.chat.history().messages.size()==4 and a.chat_messages.size()==4,"Spoof malformed stale and duplicate never append")
	for i in range(6): spectator._send({"type":"chat_send","text":"Burst "+str(i),"nonce":str(i+20).sha256_text().left(32),"generation":0})
	await until(func(): return server.chat.history().messages.size()==7,"Observer rate budget")
	await create_timer(0.1).timeout
	check(server.chat.history().messages.size()==7,"Per-author chat limiter independent of player")
	# Locally remove latest event, then receive next sequence to require only chat history repair.
	var keep:Dictionary=a.chat_snapshot(); var world=a.runner; var revision:int=a.terrain_revision
	a.chat_messages.pop_back(); a.chat_sequence-=1
	var event:Dictionary=server.chat.history().messages.back()
	a._accept_chat_event(event)
	check(a.chat_sequence==event.sequence,"Contiguous live event applied")
	a.chat_sequence=1; a.chat_messages=a.chat_messages.slice(0,1)
	a._accept_chat_event(event)
	await until(func(): return a.chat_sequence==7,"Sequence gap chat-only history repair")
	check(a.runner==world and a.terrain_revision==revision,"Chat recovery never rebuilds terrain")
	var malformed:Dictionary=server.chat.history(); malformed.messages[1].author_role="admin"
	a._accept_chat_history(malformed,true)
	check(a.chat_sequence==7 and a.chat_messages.size()==7,"Malformed history leaves valid chat atomic")
	var identity:String=spectator.spectator_id
	spectator.close(); await until(func(): return server.spectators.is_empty(),"Chat spectator disconnected")
	spectator.retry_connection(); await until(func(): return spectator.ready_for_match and spectator.chat_messages.size()==7,"Reconnect chat history")
	check(spectator.spectator_id==identity and spectator.chat_messages==a.chat_messages,"Reconnect bounded tail and stable author")
	# A legacy player still controls real gameplay while chat is active.
	await until(func(): return legacy.match_phase=="playing" and a.match_phase=="playing","Legacy gameplay phase")
	var actor:Node=legacy if legacy.player_id==server.runner.state.get_active_player().player_id else a
	var command=load("res://scripts/core/turns/player_action_command.gd").new()
	command.player_id=actor.player_id; command.turn_id=actor.runner.state.turn_id; command.generation=0; command.weapon_id=1; command.aim_direction=Vector3.DOWN; command.shot_power=0.75
	actor.send_command(command)
	await until(func(): return server.terrain_revision==1 and spectator.terrain_revision==1,"Gameplay unaffected by chat")
	var blue:Node=a if a.player_id=="blue_1" else legacy
	blue.restart_match()
	await until(func(): return spectator.ready_for_match and spectator.runner.state.generation==1 and spectator.chat_generation==1 and spectator.chat_messages.is_empty(),"Rematch clears chat and old queued generation")
	check(server.chat.history().messages.is_empty() and server.chat.generation==1,"Chat generation reset shares authoritative restart")
	spectator._send({"type":"chat_send","text":"Stale after restart","nonce":"f".repeat(32),"generation":0})
	await create_timer(0.1).timeout
	check(server.chat.history().messages.is_empty(),"Delayed chat cannot cross rematch")
	for c in [a,legacy,spectator]: c.close()
	server.close(); server.apply_options({"chat_enabled":false})
	check(server.start(port)==OK,"Restart chat-disabled server")
	var disabled=client(port)
	await until(func(): return disabled.ready_for_match,"Disabled server sync")
	check(not disabled.chat_enabled and not disabled.send_chat("Denied").ok,"Disabled chat UI/API")
	disabled._send({"type":"chat_send","text":"Denied raw","nonce":"a".repeat(32),"generation":0})
	await create_timer(0.1).timeout
	check(server.chat.history().messages.is_empty(),"Disabled server rejects raw send")
	# A prior observer token belongs to the previous server generation. An explicit
	# role switch must discard it before hello and admit a fresh player slot.
	spectator.connect_to_server("127.0.0.1",port,"player")
	await until(func(): return spectator.ready_for_match,"Explicit observer-to-player role change")
	check(spectator.role=="player" and not spectator.player_id.is_empty() and spectator.resume_token!="" and spectator.spectator_id=="","Role switch starts fresh identity, no implicit promotion")
	finish()
func finish()->void:
	for node in owned:
		if is_instance_valid(node): node.close(); node.queue_free()
	await process_frame
	print("network_chat19_next: %d failures"%failures)
	quit(1 if failures else 0)
