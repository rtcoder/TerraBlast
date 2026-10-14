class_name NakamaClient
extends Node
signal status_changed(message: String)
signal match_found(data: Dictionary)
var base_url := "http://127.0.0.1:7350"
var server_key := "terrablast-dev-key"
var token := ""
var last_error := ""
var matched: Dictionary = {}
var socket: WebSocketPeer
var responses := {}
var sequence := 0
var was_open := false

func fail(message: String) -> bool:
	last_error = message
	status_changed.emit(message)
	return false

func guest_login(device_id: String) -> bool:
	if device_id.length() < 10:
		return fail("Guest ID must contain at least 10 characters.")
	var http := HTTPRequest.new()
	http.timeout = 5.0
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json", "Authorization: Basic " + Marshalls.utf8_to_base64(server_key + ":")])
	var error := http.request(base_url + "/v2/account/authenticate/device?create=true", headers, HTTPClient.METHOD_POST, JSON.stringify({"id": device_id}))
	if error != OK:
		http.queue_free()
		return fail("Cannot reach Nakama. Start backend/docker-compose.yml and retry.")
	var result: Array = await http.request_completed
	http.queue_free()
	if result[0] != HTTPRequest.RESULT_SUCCESS or result[1] != 200:
		return fail("Nakama login failed (HTTP %d). Check local backend and server key." % result[1])
	var data = JSON.parse_string(result[3].get_string_from_utf8())
	if not data is Dictionary or not data.get("token") is String:
		return fail("Invalid login response.")
	token = data.token
	last_error = ""
	status_changed.emit("Guest authenticated")
	return true

func connect_socket() -> bool:
	if token.is_empty():
		return fail("Log in as guest first.")
	close()
	socket = WebSocketPeer.new()
	var url := base_url.replace("https://", "wss://").replace("http://", "ws://")
	var error := socket.connect_to_url(url + "/ws?format=json&status=true&token=" + token.uri_encode())
	if error != OK:
		return fail("Cannot open Nakama socket.")
	var deadline := Time.get_ticks_msec() + 5000
	while socket != null and socket.get_ready_state() == WebSocketPeer.STATE_CONNECTING and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if socket == null or socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return fail("Nakama socket unavailable. Check backend and retry login.")
	was_open = true
	status_changed.emit("Lobby connection ready")
	return true

func _process(_delta: float) -> void:
	if socket == null:
		return
	socket.poll()
	if socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		if was_open:
			was_open = false
			fail("Nakama disconnected. Log in again to reconnect.")
		return
	while socket.get_available_packet_count() > 0:
		var data = JSON.parse_string(socket.get_packet().get_string_from_utf8())
		if not data is Dictionary:
			continue
		if data.has("ping"):
			socket.send_text(JSON.stringify({"pong": {}}))
		if data.has("cid"):
			responses[str(data.cid)] = data
		if data.has("matchmaker_matched"):
			matched = data.matchmaker_matched
			match_found.emit(matched)
			status_changed.emit("Opponent found")

func request(type: String, body: Dictionary) -> Dictionary:
	if socket == null or socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		fail("Connect to Nakama first.")
		return {}
	sequence += 1
	var cid := str(sequence)
	var envelope := {"cid": cid}
	envelope[type] = body
	socket.send_text(JSON.stringify(envelope))
	var deadline := Time.get_ticks_msec() + 5000
	while not responses.has(cid) and socket != null and socket.get_ready_state() == WebSocketPeer.STATE_OPEN and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var response: Dictionary = responses.get(cid, {})
	responses.erase(cid)
	if response.has("error") or response.is_empty():
		fail(str(response.get("error", {}).get("message", "Nakama request timed out; retry.")))
		return {}
	return response

func create_lobby() -> Dictionary:
	var response := await request("match_create", {"name": "TerraBlast"})
	return response.get("match", {})

func join_lobby(id: String) -> Dictionary:
	var response := await request("match_join", {"match_id": id})
	return response.get("match", {})

func find_match() -> bool:
	matched = {}
	var response := await request("matchmaker_add", {"min_count": 2, "max_count": 2, "query": "+properties.mode:terrablast", "string_properties": {"mode": "terrablast"}})
	return response.has("matchmaker_ticket")

func join_matched() -> Dictionary:
	if matched.is_empty():
		return {}
	var body := {"token": matched.token} if matched.has("token") else {"match_id": matched.get("match_id", "")}
	var response := await request("match_join", body)
	return response.get("match", {})

func close() -> void:
	if socket != null:
		socket.close()
		socket = null
	was_open = false
	responses.clear()

func _exit_tree() -> void:
	close()
