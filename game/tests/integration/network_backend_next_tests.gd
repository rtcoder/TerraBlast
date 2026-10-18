extends SceneTree
const S=preload("res://scripts/networking/transport/match_server.gd")
const C=preload("res://scripts/networking/transport/match_client.gd")
const P=preload("res://scripts/networking/messages/match_protocol.gd")
const F=preload("res://scripts/core/rules/match_factory.gd")
class Wire:
	extends "res://scripts/networking/transport/match_server.gd"
	var sent: Array=[]
	var fail_send:=false
	func _send_packet(id: int,data: Dictionary) -> Error:
		if fail_send: return ERR_CANT_CONNECT
		sent.append({"id":id,"data":data.duplicate(true)})
		return OK
var failures:=0
func check(ok: bool,label: String) -> void:
	if not ok: failures+=1; push_error(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var server=Wire.new()
	server.runner=F.create_match(2)
	server.slots={2:"blue_1",3:"red_1"}
	server.peer_tokens={2:"a".repeat(64),3:"b".repeat(64)}
	check(server.apply_options({"snapshot_chunks_per_frame":2}).ok,"Configure queue budget")
	server._send_snapshot(2)
	var frozen_hash:=P.terrain_checksum(server.runner.world)
	var frozen_time: float=server.runner.state.time_remaining
	server.runner.tick(0.5)
	var command=load("res://scripts/core/turns/player_action_command.gd").new()
	command.player_id=server.runner.state.get_active_player().player_id
	command.turn_id=server.runner.state.turn_id
	command.generation=server.runner.state.generation
	command.weapon_id=1
	command.aim_direction=Vector3.DOWN
	command.shot_power=0.75
	var shot: Dictionary=server.runner.submit(command)
	check(shot.ok,"Concurrent shot accepted")
	server.terrain_revision=1
	server._send(2,{"type":"result","result":P.encode_result(shot),"base_terrain_revision":0,"terrain_revision":1,"phase":"playback"})
	server._send(2,{"type":"state","state":server.runner.state_snapshot(),"terrain_revision":1,"phase":"playback"})
	server._drain_snapshots()
	check(server.sent.size()==2 and not server.snapshot_queues.is_empty(),"Snapshot frame budget")
	for i in range(300):
		if server.snapshot_queues.is_empty(): break
		server._drain_snapshots()
	var client=C.new()
	var saw_end:=false
	for row in server.sent:
		if row.data.type=="snapshot_end":
			saw_end=true
			check(row.data.checksum==frozen_hash and row.data.state.time_remaining==frozen_time,"Snapshot frozen before mutation")
		if row.data.type in ["state","result"]: check(saw_end,"Catchup state follows end")
		client._handle(row.data)
	check(client.ready_for_match and client.runner.state.time_remaining==server.runner.state.time_remaining,"Snapshot plus ordered catchup converges")
	check(P.terrain_checksum(client.runner.world)==P.terrain_checksum(server.runner.world),"Concurrent terrain result converges after frozen snapshot")
	server.sent.clear()
	server._send_snapshot(2)
	server.fail_send=true
	server._drain_snapshots()
	check(server.snapshot_queues.is_empty() and server.diagnostics.send_failures>0 and server.sent.is_empty(),"Failed transfer aborts without end")
	server.fail_send=false
	server._send_snapshot(2)
	var newer: int=server.transfer_serial
	server._send_snapshot(2)
	check(server.snapshot_queues.size()==1 and server.transfer_serial>newer,"Transfer replacement bounded")
	server.reservations["a".repeat(64)]={"peer":2,"player":"blue_1","expires":0}
	client._handle(server.snapshot_queues[2].messages[0])
	var stage=client.staging
	client._handle({"type":"chunk","transfer_id":1,"chunk":{}})
	client._handle({"type":"snapshot_end","transfer_id":1})
	check(client.staging==stage and stage!=null,"Stale chunks/end cannot erase new staging")
	for i in range(130): server._send(2,{"type":"phase","phase":"playing"})
	check(server.snapshot_queues.size()==1 and server.snapshot_queues[2].catchup<128,"Catchup overflow supersedes with bounded fresh snapshot")
	server._disconnected(2)
	check(not server.snapshot_queues.has(2),"Disconnect cancels queued transfer")
	server.packet_budgets.clear()
	for i in range(100): check(server._allow_packet(77,10,999),"Initial packet burst")
	check(not server._allow_packet(77,10,1000),"Second boundary does not reset bucket")
	check(server._allow_packet(77,10,1010),"Continuous refill")
	var diagnostic: Dictionary=server.diagnostic_snapshot()
	check(not JSON.stringify(diagnostic).contains("bbbbbbbb"),"Diagnostics omit secrets")
	diagnostic.counters.packets=-10
	check(server.diagnostics.packets>=0,"Diagnostic copy")
	client.resume_token="saved"
	var old_host: String=client.last_host
	check(client.connect_to_server("bad/path",19170)==ERR_INVALID_PARAMETER and client.resume_token=="saved" and client.last_host==old_host,"Invalid connect preserves session")
	client.close()
	check(client.resume_token=="saved","Close preserves retry")
	client.leave()
	check(client.resume_token.is_empty(),"Leave forgets token")
	client.free()
	server.free()
	var lobby=load("res://scripts/client/ui/lobby_panel.gd").new()
	root.add_child(lobby)
	var state:={"capacity":2,"generation":0,"require_ready":true,"started":false,"roster":[{"id":"blue_1","name":"Blue","team":1,"connected":true,"ready":false,"rematch":false}]}
	lobby.present(state,"blue_1","waiting",true)
	var requests:=[0]
	lobby.ready_requested.connect(func(_v): requests[0]+=1)
	lobby._request_ready(); lobby._request_ready()
	check(requests[0]==1 and lobby.pending_operations.has("ready"),"Ready waits for authority")
	state.roster[0].ready=true
	lobby.present(state,"blue_1","waiting",true)
	check(not lobby.pending_operations.has("ready") and lobby._own_ready,"Ready ack")
	lobby.name_input.text="bad\nname"
	lobby._request_name()
	check(not lobby.pending_operations.has("name"),"Invalid name rejected locally")
	lobby._request_ready()
	lobby.operation_rejected("stale_generation")
	lobby.present(state,"blue_1","waiting",true)
	check(not lobby.ready_button.disabled and lobby.feedback.text=="stale_generation","Reject unlocks pending")
	lobby._request_ready()
	lobby._process(6.0)
	check(not lobby.ready_button.disabled and not lobby.pending_operations.has("ready"),"Pending timeout unlocks without new network event")
	state.started=true
	lobby.present(state,"blue_1","ended",true)
	lobby._request_rematch(); lobby._request_rematch()
	check(lobby.pending_operations.has("rematch") and not lobby._own_vote,"Rematch pending not optimistic")
	state.generation=1
	lobby.present(state,"blue_1","waiting",true)
	check(lobby.pending_operations.is_empty(),"Generation resets pending")
	var disconnects:=[0]
	lobby.disconnect_requested.connect(func(): disconnects[0]+=1)
	lobby._confirm_disconnect()
	check(disconnects[0]==0,"Disconnect requires confirmation")
	lobby.disconnect_confirmation.confirmed.emit()
	check(disconnects[0]==1,"Disconnect confirm emits once")
	lobby.queue_free()
	await process_frame
	print("network_backend_next: %d failures"%failures)
	quit(1 if failures else 0)
