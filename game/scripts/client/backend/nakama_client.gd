class_name NakamaClient
extends Node
signal status_changed(message: String)
signal match_found(data: Dictionary)
signal connection_state_changed(state: String)
var base_url := "http://127.0.0.1:7350"
var server_key := "terrablast-dev-key"
var token := ""
var last_error := ""
var matched: Dictionary = {}
var socket: WebSocketPeer
var responses := {}
var sequence := 0
var was_open := false
var connection_state := "disconnected"
var matchmaking_ticket := ""
var searching := false
var search_generation := 0
var connection_generation := 0
const Endpoints = preload("res://scripts/client/backend/connection_profiles.gd")
const Identity = preload("res://scripts/client/backend/guest_identity.gd")
const MAX_BODY := 65536
const MAX_PACKETS := 32
const MAX_RECEIVE_BYTES := 262144
const MAX_REQUESTS := 16
var pending_requests := {}
var active_http: HTTPRequest
var auth_generation := 0
func set_endpoint(value: String) -> bool:
	if not Endpoints.valid_url(value): return fail("Invalid backend URL")
	value=value.trim_suffix("/")
	if value!=base_url:
		close()
		token=""
		base_url=value
	return true
func _cancel_http() -> void:
	auth_generation+=1
	if is_instance_valid(active_http):
		active_http.cancel_request()
		active_http.queue_free()
	active_http=null


func _state(value: String) -> void:
	connection_state = value
	connection_state_changed.emit(value)

func fail(message: String) -> bool:
	last_error = message
	_state("error")
	status_changed.emit(message)
	return false

func guest_login(device_id: String) -> bool:
	if not Endpoints.valid_url(base_url) or not Identity.valid(device_id): return fail("Invalid backend URL or guest ID (10–128 characters).")
	_cancel_http()
	var generation:=auth_generation
	_state("authenticating")
	var http := HTTPRequest.new()
	active_http=http
	http.timeout=5.0
	http.body_size_limit=MAX_BODY
	add_child(http)
	var completed:={"done":false,"result":[]}
	http.request_completed.connect(func(code,status,headers,body):
		completed.result=[code,status,headers,body]
		completed.done=true
	)
	var headers:=PackedStringArray(["Content-Type: application/json","Authorization: Basic "+Marshalls.utf8_to_base64(server_key+":")])
	var error:=_start_http_request(http,base_url.trim_suffix("/")+"/v2/account/authenticate/device?create=true",headers,JSON.stringify({"id":device_id}))
	if error!=OK:
		_cancel_http()
		return fail("Cannot reach Nakama. Check backend endpoint.")
	while not completed.done and generation==auth_generation and is_inside_tree(): await get_tree().process_frame
	if generation!=auth_generation: return false
	active_http=null
	http.queue_free()
	if not completed.done: return false
	var result: Array=completed.result
	if result[0]!=HTTPRequest.RESULT_SUCCESS or result[1]!=200: return fail("Nakama login failed (HTTP %d)." % result[1])
	var data: Variant=JSON.parse_string(result[3].get_string_from_utf8())
	if not data is Dictionary or not Endpoints.clean(data.get("token"),1,16384): return fail("Invalid login response.")
	token=data.token
	last_error=""
	_state("authenticated")
	status_changed.emit("Guest authenticated")
	return true

func connect_socket() -> bool:
	if not Endpoints.valid_url(base_url): return fail("Invalid backend URL")
	if token.is_empty():
		return fail("Log in as guest first.")
	close()
	var generation:=connection_generation
	_state("connecting")
	socket = WebSocketPeer.new()
	var url := base_url.replace("https://", "wss://").replace("http://", "ws://")
	var error := socket.connect_to_url(url + "/ws?format=json&status=true&token=" + token.uri_encode())
	if error != OK:
		close()
		return fail("Cannot open Nakama socket.")
	var deadline := Time.get_ticks_msec() + 5000
	while generation==connection_generation and socket != null and socket.get_ready_state() == WebSocketPeer.STATE_CONNECTING and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if generation!=connection_generation: return false
	if socket == null or socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		close()
		return fail("Nakama socket unavailable. Check backend and retry login.")
	was_open = true
	last_error = ""
	_state("connected")
	status_changed.emit("Lobby connection ready")
	return true

func _process(_delta: float) -> void:
	if socket == null:
		return
	socket.poll()
	if socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		if was_open:
			was_open = false
			matchmaking_ticket = ""
			searching = false
			matched.clear()
			search_generation += 1
			fail("Nakama disconnected. Log in again to reconnect.")
		return
	var received:=0
	for unused in range(mini(socket.get_available_packet_count(),MAX_PACKETS)):
		var bytes:=socket.get_packet()
		received+=bytes.size()
		if bytes.size()<=MAX_BODY:
			var data: Variant=JSON.parse_string(bytes.get_string_from_utf8())
			if data is Dictionary: _accept_message(data)
		if socket == null: break
		if received>=MAX_RECEIVE_BYTES: break

func _accept_message(data: Dictionary) -> void:
	if data.has("ping") and data.ping is Dictionary:
		if socket != null and _send_socket_text(JSON.stringify({"pong":{}})) != OK:
			close()
			fail("Nakama send failed")
			return
	if data.get("cid") is String and pending_requests.has(data.cid):
		if valid_response(data): responses[data.cid]=data
		else: responses[data.cid]={"error":{"message":"Invalid Nakama response"}}
	if data.get("matchmaker_matched") is Dictionary and searching:
		var value: Dictionary=data.matchmaker_matched
		if not Endpoints.clean(value.get("token",value.get("match_id","")),1,16384): return
		matched=value.duplicate(true)
		matchmaking_ticket=""
		searching=false
		_state("matched")
		match_found.emit(matched)
		status_changed.emit("Opponent found")

static func valid_response(value: Dictionary) -> bool:
	if value.has("error"):
		if not value.error is Dictionary or not value.error.get("message") is String or value.error.message.length()>512: return false
	for key in ["match","matchmaker_ticket"]:
		if value.has(key) and not value[key] is Dictionary: return false
	if value.has("match") and not Endpoints.clean(value.match.get("match_id"),1,256): return false
	if value.has("matchmaker_ticket") and not Endpoints.clean(value.matchmaker_ticket.get("ticket"),1,512): return false
	return true

func request(type: String, body: Dictionary, terminal_error: String = "") -> Dictionary:
	if socket == null or socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		fail("Connect to Nakama first.")
		return {}
	if pending_requests.size()>=MAX_REQUESTS:
		fail("Too many pending Nakama requests")
		return {}
	sequence += 1
	var cid := str(sequence)
	var request_generation := connection_generation
	var envelope := {"cid": cid}
	envelope[type] = body
	pending_requests[cid]=true
	if _send_socket_text(JSON.stringify(envelope))!=OK:
		close()
		fail("Nakama send failed")
		return {}
	var deadline := Time.get_ticks_msec() + 5000
	while request_generation == connection_generation and not responses.has(cid) and socket != null and socket.get_ready_state() == WebSocketPeer.STATE_OPEN and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if request_generation != connection_generation:
		return {}
	pending_requests.erase(cid)
	var response: Dictionary = responses.get(cid, {})
	responses.erase(cid)
	if not terminal_error.is_empty() and response.get("error", {}).get("message") == terminal_error:
		return response
	if response.has("error") or response.is_empty():
		fail(str(response.get("error", {}).get("message", "Nakama request timed out; retry.")))
		return {}
	return response

func create_lobby() -> Dictionary:
	var response := await request("match_create", {"name": "TerraBlast"})
	return response.get("match", {})

func join_lobby(id: String) -> Dictionary:
	if not Endpoints.clean(id,1,256):
		fail("Invalid lobby ID")
		return {}
	var response := await request("match_join", {"match_id": id})
	return response.get("match", {})

func find_match() -> bool:
	if searching or not matchmaking_ticket.is_empty():
		return fail("Matchmaking is already running. Cancel before starting another search.")
	matched = {}
	searching = true
	search_generation += 1
	var generation := search_generation
	_state("searching")
	var response := await request("matchmaker_add", {"min_count": 2, "max_count": 2, "query": "+properties.mode:terrablast", "string_properties": {"mode": "terrablast"}})
	var ticket: String = str(response.get("matchmaker_ticket", {}).get("ticket", ""))
	if generation != search_generation:
		if not ticket.is_empty():
			await request("matchmaker_remove", {"ticket": ticket}, "Matchmaker ticket not found")
		return false
	if ticket.is_empty():
		searching = false
		return false
	# A match notification can precede the ticket response.
	if matched.is_empty():
		matchmaking_ticket = ticket
	return true

func cancel_matchmaking() -> bool:
	search_generation += 1
	searching = false
	matched.clear()
	var ticket := matchmaking_ticket
	if ticket.is_empty():
		_state("connected" if was_open else "disconnected")
		return true
	var response := await request("matchmaker_remove", {"ticket": ticket}, "Matchmaker ticket not found")
	if response.is_empty():
		return false
	matchmaking_ticket = ""
	last_error = ""
	_state("connected")
	status_changed.emit("Matchmaking cancelled")
	return true

func retry_connection() -> bool:
	return await connect_socket()

func join_matched() -> Dictionary:
	if matched.is_empty():
		return {}
	var body := {"token": matched.token} if matched.has("token") else {"match_id": matched.get("match_id", "")}
	var response := await request("match_join", body)
	return response.get("match", {})

func close() -> void:
	_cancel_http()
	pending_requests.clear()
	search_generation += 1
	connection_generation += 1
	searching = false
	matchmaking_ticket = ""
	matched.clear()
	_state("disconnected")
	if socket != null:
		socket.close()
		socket = null
	was_open = false
	responses.clear()

func _exit_tree() -> void:
	close()

func _start_http_request(http: HTTPRequest,url: String,headers: PackedStringArray,body: String) -> Error:
	return http.request(url,headers,HTTPClient.METHOD_POST,body)

func _send_socket_text(text: String) -> Error:
	return socket.send_text(text) if socket != null else ERR_UNCONFIGURED
