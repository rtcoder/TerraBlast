extends SceneTree
const S=preload("res://scripts/networking/transport/match_server.gd")
const C=preload("res://scripts/networking/transport/match_client.gd")
const P=preload("res://scripts/networking/messages/match_protocol.gd")
var failures:=0
var owned:Array=[]
func check(ok:bool,label:String)->void:
	if not ok: failures+=1; push_error(label)
func _initialize()->void: call_deferred("run")
func until(test:Callable,label:String,seconds:float=12.0)->bool:
	var deadline:int=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		if test.call(): return true
		await process_frame
	check(false,"Timeout: "+label)
	return false
func client(port:int,role:String="player")->Node:
	var c=C.new(); owned.append(c); root.add_child(c)
	check(c.connect_to_server("127.0.0.1",port,role)==OK,"Client socket")
	return c
func run()->void:
	var probe:=PacketPeerUDP.new(); check(probe.bind(0,"127.0.0.1")==OK,"Independent UDP port")
	var port:int=probe.get_local_port(); probe.close()
	var server=S.new(); owned.append(server); root.add_child(server)
	check(server.apply_options({"spectator_capacity":2,"snapshot_chunks_per_frame":1,"reservation_seconds":1.0}).ok,"Bounded options")
	if server.start(port,"res://maps/twin_forts.toml","classic",2,true)!=OK: check(false,"Server bind"); finish(); return
	var a=client(port); var b=client(port)
	if not await until(func(): return a.ready_for_match and b.ready_for_match,"Players sync"): finish(); return
	check(a.player_id!=b.player_id and server.slots.size()==2,"Authoritative player identities")
	a.set_ready(true); b.set_ready(true)
	await until(func(): return server.match_phase=="playing" and a.match_phase=="playing" and b.match_phase=="playing","Player quorum")
	var spectator=client(port,"spectator")
	await until(func(): return spectator.staging!=null,"Spectator transfer begin")
	var actor:Node=a if a.player_id==server.runner.state.get_active_player().player_id else b
	var command=load("res://scripts/core/turns/player_action_command.gd").new()
	command.player_id=actor.player_id; command.turn_id=actor.runner.state.turn_id; command.generation=actor.runner.state.generation
	command.weapon_id=1; command.aim_direction=Vector3.DOWN; command.shot_power=0.75
	actor.send_command(command)
	await until(func(): return server.terrain_revision==1,"Shot during slow spectator snapshot")
	await until(func(): return spectator.ready_for_match and spectator.terrain_revision==1,"Late join catchup converges")
	check(spectator.role=="spectator" and spectator.player_id=="" and spectator.spectator_id.begins_with("spectator_"),"No fake player identity")
	check(P.terrain_checksum(spectator.runner.world)==P.terrain_checksum(server.runner.world) and spectator.runner.state.turn_id==server.runner.state.turn_id,"Frozen snapshot plus real result exact terrain/state")
	check(server.slots.size()==2 and server.runner.state.players.size()==2,"Observer never changes roster capacity")
	var terrain_hash:String=P.terrain_checksum(server.runner.world); var revision:int=server.runner.state.revision
	for kind in ["command","move","surrender","restart","ready","rematch"]: spectator._send({"type":kind,"generation":0,"ready":true,"vote":true,"command":P.encode_command(command)})
	await create_timer(0.12).timeout
	check(server.runner.state.revision==revision and P.terrain_checksum(server.runner.world)==terrain_hash and server.rematch_votes.is_empty(),"Real UDP forged spectator intents rejected")
	spectator.set_display_name("Widz Żółw")
	await until(func(): return server.spectators.values()[0].name=="Widz Żółw","Spectator rename")
	var identity:String=spectator.spectator_id
	var token:String=spectator.resume_token
	spectator.close()
	await until(func(): return server.spectators.is_empty(),"Lost spectator transport")
	var before:float=server.runner.state.time_remaining
	await create_timer(0.1).timeout
	check(server.match_phase!="waiting" and (server.runner.state.status=="ended" or server.runner.state.time_remaining<before),"Spectator disconnect cannot pause live match")
	spectator.retry_connection()
	await until(func(): return spectator.ready_for_match,"Spectator resumes")
	check(spectator.spectator_id==identity and spectator.resume_token==token and spectator.lobby_state.spectators[0].name=="Widz Żółw","Resume restores role identity and name")
	var spectator2=client(port,"spectator")
	await until(func(): return spectator2.ready_for_match,"Second spectator")
	var full=client(port,"spectator")
	await until(func(): return full.connection_state=="error","Full spectator rejection")
	check(full.last_error=="spectator_slots_reserved_or_full" and server.slots.size()==2,"Full observer room leaves players alone")
	spectator2.leave()
	await until(func(): return server.spectator_reservations.size()==1,"Explicit leave releases immediately",0.8)
	full.connect_to_server("127.0.0.1",port,"spectator")
	await until(func(): return full.ready_for_match,"Freed place reused")
	var expiring:String=full.resume_token
	full.close(); await until(func(): return server.spectators.size()==1,"Disconnect creates reservation")
	await until(func(): return not server.spectator_reservations.has(expiring),"Observer grace expires",2.5)
	full.retry_connection(); await until(func(): return full.connection_state=="error","Expired reconnect rejected")
	check(full.last_error=="invalid_or_expired_resume_token" and full.resume_token=="","Expired token cannot recover another viewer")
	# Resync remains authorized and does not change role/identity.
	spectator.request_snapshot(); await until(func(): return spectator.ready_for_match,"Observer resync")
	check(spectator.spectator_id==identity and P.terrain_checksum(spectator.runner.world)==P.terrain_checksum(server.runner.world),"Observer repair converges")
	if server.runner.state.status!="ended":
		a.surrender(); await until(func(): return server.runner.state.status=="ended","End before rematch")
	a.vote_rematch(true); await until(func(): return server.rematch_votes.size()==1,"First player vote")
	spectator.close(); await until(func(): return server.spectators.is_empty(),"Spectator disconnect with player vote")
	check(server.rematch_votes.get(a.player_id,false),"Observer disconnect preserves rematch vote")
	spectator.retry_connection(); await until(func(): return spectator.ready_for_match,"Observer reconnect before rematch")
	b.vote_rematch(true)
	await until(func(): return server.runner.state.generation==1,"Players alone decide rematch")
	await until(func(): return spectator.ready_for_match and spectator.runner.state.generation==1 and a.ready_for_match and a.runner.state.generation==1,"Observer receives rematch snapshot")
	check(server.runner.state.players.size()==2 and spectator.player_id=="" and not server.started,"Rematch keeps spectator outside quorum")
	var report:Dictionary=server.diagnostic_snapshot()
	check(report.spectators==1 and report.roster.players.size()==2 and not JSON.stringify(report).contains(token),"Safe live diagnostic roster")
	server.graceful_shutdown()
	await until(func(): return spectator.last_error=="server_shutdown" and a.last_error=="server_shutdown" and b.last_error=="server_shutdown","Shutdown reaches all roles")
	finish()
func finish()->void:
	for node in owned:
		if is_instance_valid(node): node.close(); node.queue_free()
	await process_frame
	print("network_spectator19_next: %d failures"%failures)
	quit(1 if failures else 0)
