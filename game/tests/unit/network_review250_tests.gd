extends SceneTree
class FailingSocketClient:
	extends "res://scripts/client/backend/nakama_client.gd"
	func _send_socket_text(_text: String) -> Error:
		return ERR_CANT_CONNECT
class DeferredAuthClient:
	extends "res://scripts/client/backend/nakama_client.gd"
	func _start_http_request(_http: HTTPRequest, _url: String, _headers: PackedStringArray, _body: String) -> Error:
		return OK
class WireServer:
	extends "res://scripts/networking/transport/match_server.gd"
	var sent := 0
	func _send_packet(_id: int, _data: Dictionary) -> Error:
		sent += 1
		return OK
var failures := 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func _initialize(): call_deferred("run")
func run():
	var client := FailingSocketClient.new()
	root.add_child(client)
	client.socket = WebSocketPeer.new()
	client.pending_requests = {"1":true,"2":true}
	client.responses = {"1":{"cid":"1"}}
	client.searching = true
	client.matchmaking_ticket = "old-ticket"
	var generation: int = client.connection_generation
	client._accept_message({"ping":{}})
	check(client.socket == null,"Nakama send failure closes unusable socket")
	check(client.pending_requests.is_empty() and client.responses.is_empty(),"Send failure cancels all pending request state")
	check(client.connection_generation > generation and not client.searching and client.matchmaking_ticket.is_empty(),"Send failure invalidates pending async operations")
	check(client.connection_state == "error" and client.last_error == "Nakama send failed","Send failure remains visible after cleanup")
	client.free()
	var server := WireServer.new()
	var packet := {"type":"phase","phase":"playing"}
	server._send(2,packet)
	var envelope := packet.duplicate()
	envelope.version = load("res://scripts/networking/messages/match_protocol.gd").VERSION
	check(server.diagnostics.sent_bytes == load("res://scripts/networking/messages/match_protocol.gd").packet(envelope).size(),"Sent bytes include protocol envelope")
	var message := {"type":"state","padding":""}
	var overhead: int = load("res://scripts/networking/messages/match_protocol.gd").packet(message).size()
	message.padding = "x".repeat(32768-overhead)
	server.apply_options({"snapshot_bytes_per_frame":65536})
	server.sent = 0
	server.snapshot_queues[2] = {"messages":[message,message.duplicate()],"cursor":0}
	server._drain_snapshots()
	check(server.sent == 1,"Snapshot byte budget includes envelope overhead")
	server.free()
	var auth := DeferredAuthClient.new()
	root.add_child(auth)
	var login_results := []
	_login(auth,login_results)
	await process_frame
	check(auth.active_http != null,"Login has a cancellable request")
	auth.close()
	await process_frame
	await process_frame
	check(login_results == [false] and auth.active_http == null and auth.token.is_empty(),"Closed pending login finishes without committing session")
	auth.free()
	print("Network review250: %d failures" % failures)
	quit(1 if failures else 0)

func _login(client: Node, results: Array) -> void:
	results.append(await client.guest_login("review-250-deferred-login"))
