extends SceneTree
const S=preload("res://scripts/networking/transport/match_server.gd")
const C=preload("res://scripts/networking/transport/match_client.gd")
const P=preload("res://scripts/networking/messages/match_protocol.gd")
const F=preload("res://scripts/core/rules/match_factory.gd")
class Wire:
	extends "res://scripts/networking/transport/match_server.gd"
	var sent:Array=[]
	func _send_packet(id:int,data:Dictionary)->Error:
		sent.append({"id":id,"data":data.duplicate(true)}); return OK
class ClientWire:
	extends "res://scripts/networking/transport/match_client.gd"
	var sent:Array=[]
	func _send(data:Dictionary)->Error:
		sent.append(data.duplicate(true)); return OK
var failures:=0
func check(ok:bool,label:String)->void:
	if not ok: failures+=1; push_error(label)
func hello(server:Node,id:int,role:String="player",token:String="")->void:
	server.pending[id]=Time.get_ticks_msec()
	server._accept_hello(id,{"role":role,"resume_token":token,"extensions":["spectators_v1","chat_v1"]})
func _initialize()->void:
	var server=Wire.new(); server.runner=F.create_match(2); server.spectator_capacity=2
	check(P.valid_hello({"resume_token":""}),"Legacy hello player compatible")
	for value in [{"resume_token":"","role":"admin"},{"resume_token":"","extensions":1},{"resume_token":"","extensions":[1]},{"resume_token":"","extensions":["a".repeat(33)]},{"resume_token":"x","role":"spectator"}]: check(not P.valid_hello(value),"Malformed hello")
	var options=load("res://scripts/networking/transport/server_runtime_options.gd").new()
	check(options.apply({"spectator_capacity":6,"chat_enabled":true}).ok,"Typed spectator/chat options")
	for value in [{"spectator_capacity":7},{"spectator_capacity":-1},{"spectator_capacity":NAN},{"chat_enabled":1},{"chat_enabled":"yes"}]: check(not options.apply(value).ok,"Invalid options atomic")
	check(options.values.chat_enabled and options.values.spectator_capacity==6,"Invalid batch leaves options")
	server.pending[2]=Time.get_ticks_msec(); server._accept_hello(2,{"resume_token":""})
	hello(server,3)
	check(server.slots.size()==2 and server.slots[2]=="blue_1" and server.slots[3]=="red_1","Legacy and new players unique")
	var state=server.runner.state_snapshot(); var hash=P.terrain_checksum(server.runner.world)
	hello(server,4,"spectator"); hello(server,5,"spectator")
	check(server.spectators.size()==2 and server.spectators[4].id!=server.spectators[5].id,"Independent spectator IDs")
	check(server.runner.state_snapshot()==state and P.terrain_checksum(server.runner.world)==hash,"Spectator admission never mutates player state")
	hello(server,6,"spectator")
	check(not server.spectators.has(6) and server.rejected_disconnects.has(6),"Full spectator limit rejects")
	# Shared round robin remains global across player and both observer transfers.
	server.apply_options({"snapshot_chunks_per_frame":3})
	server.sent.clear()
	server._drain_snapshots()
	check(server.sent.size()==3 and server.sent.any(func(row): return row.id==2) and server.sent.any(func(row): return row.id==3) and server.sent.any(func(row): return row.id==4),"Global snapshot frame limit and round robin")
	server.sent.clear(); server._drain_snapshots()
	check(server.sent.any(func(row): return row.id==5),"Second spectator cannot starve behind players")
	var begin:Dictionary=server.snapshot_queues[4].messages[0]
	check(P.valid_snapshot_metadata(begin) and begin.player_id=="" and begin.role=="spectator","Spectator metadata valid without fake player")
	var invalid=begin.duplicate(true); invalid.role="player"
	check(not P.valid_snapshot_metadata(invalid),"Empty player identity forbidden")
	invalid=begin.duplicate(true); invalid.spectator_id="blue_1"
	check(not P.valid_snapshot_metadata(invalid),"Spectator identity bounded")
	for kind in ["command","move","surrender","restart","ready","rematch","forged"]: server._handle(4,{"type":kind,"generation":0,"ready":true,"vote":true})
	check(server.runner.state_snapshot()==state and server.slots.size()==2 and server.ready_slots.is_empty() and server.motion.is_empty() and server.rematch_votes.is_empty(),"Spectator cannot author any gameplay")
	server._handle(4,{"type":"display_name","generation":0,"name":"Widz Żółw"})
	check(server.spectators[4].name=="Widz Żółw" and server.runner.state_snapshot()==state,"Spectator rename independent during match")
	var token:String=server.peer_tokens[4]; var identity:String=server.spectators[4].id
	hello(server,7,"spectator",token)
	check(not server.spectators.has(7),"In-use spectator token rejected")
	hello(server,8,"player",token)
	check(not server.slots.has(8),"Cross-role token rejected")
	server.rematch_votes["blue_1"]=true; server.motion["blue_1"]={"vector":Vector2.ONE}
	server._disconnected(4)
	check(server.rematch_votes.get("blue_1",false) and server.motion.has("blue_1"),"Spectator disconnect preserves player intent/quorum")
	hello(server,9,"spectator",token)
	check(server.spectators[9].id==identity and server.spectators[9].name=="Widz Żółw","Resume identity and name")
	server._leave_participant(9)
	check(not server.spectator_reservations.has(token) and not server.spectators.has(9),"Leave releases reservation immediately")
	hello(server,10,"spectator")
	var expired:String=server.peer_tokens[10]
	server._disconnected(10); server.spectator_reservations[expired].expires=0
	# Avoid pending rejection teardown without a real ENet host in this model test.
	server.pending.clear(); server.rejected_disconnects.clear(); server._expire_reservations()
	check(not server.spectator_reservations.has(expired),"Expired identity released")
	var lobby=server.lobby_snapshot()
	check(P.valid_lobby(lobby) and lobby.roster.size()==2,"Bounded optional spectator roster")
	invalid=lobby.duplicate(true); invalid.spectators.append(invalid.spectators[0])
	check(not P.valid_lobby(invalid),"Duplicate spectator roster rejected")
	var diagnostic=server.diagnostic_snapshot()
	check(not JSON.stringify(diagnostic).contains(server.peer_tokens[5]) and not JSON.stringify(diagnostic).contains("127.0.0.1"),"Diagnostic omits secrets and addresses")
	diagnostic.roster.players[0].name="Mutated"
	check(server.participant_roster().players[0].name!="Mutated","Roster is deep copy")
	var client=ClientWire.new(); client.role="spectator"; client.requested_role="spectator"; client.ready_for_match=true; client.match_phase="playing"
	client.send_command(null); client.move_player(Vector2.ONE,0); client.surrender(); client.restart_match(); client.set_ready(true); client.vote_rematch(true)
	check(client.sent.is_empty(),"Client spectator gameplay guards")
	client.request_snapshot(); check(client.sent.size()==1,"Spectator retains resync")
	client.resume_token="old"
	check(client.connect_to_server("bad/path",1,"player")==ERR_INVALID_PARAMETER and client.resume_token=="old","Invalid endpoint leaves session")
	check(client.connect_to_server("localhost",1,"admin")==ERR_INVALID_PARAMETER and client.requested_role=="spectator","Invalid role atomic")
	client._handle({"type":"snapshot_begin","role":"player"})
	check(client.last_error=="unsupported_spectator_server","No silent downgrade to player")
	server.spectator_capacity=0
	hello(server,15,"spectator")
	check(not server.spectators.has(15) and server.sent.back().data.reason=="spectators_disabled","Default disabled spectator admission")
	server.close()
	check(server.spectators.is_empty() and server.spectator_reservations.is_empty() and server.snapshot_queues.is_empty(),"Close clears role structures")
	client.free(); server.free()
	print("network_spectator19: %d failures"%failures)
	quit(1 if failures else 0)
