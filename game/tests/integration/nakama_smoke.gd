extends SceneTree
var failures := 0
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var path := "res://scripts/client/backend/nakama_client.gd"
	check(ResourceLoader.exists(path), "Nakama adapter exists")
	if not ResourceLoader.exists(path):
		quit(1)
		return
	var a = load(path).new()
	var b = load(path).new()
	root.add_child(a)
	root.add_child(b)
	check(await a.guest_login("terrablast-smoke-guest-alpha"), "Guest A login")
	check(await b.guest_login("terrablast-smoke-guest-beta"), "Guest B login")
	if a.token.is_empty() or b.token.is_empty():
		quit(1)
		return
	check(await a.connect_socket(), "Guest A websocket")
	check(await b.connect_socket(), "Guest B websocket")
	var lobby: Dictionary = await a.create_lobby()
	check(lobby.has("match_id"), "Create lobby")
	if lobby.has("match_id"):
		var joined: Dictionary = await b.join_lobby(lobby.match_id)
		check(joined.get("match_id") == lobby.match_id, "Join same lobby")
	check(await a.find_match(), "Queue A")
	check(await b.find_match(), "Queue B")
	for attempt in range(300):
		if not a.matched.is_empty() and not b.matched.is_empty():
			break
		await create_timer(0.02).timeout
	check(not a.matched.is_empty() and not b.matched.is_empty(), "1v1 matchmaker pairs guests")
	if not a.matched.is_empty() and not b.matched.is_empty():
		var match_a: Dictionary = await a.join_matched()
		var match_b: Dictionary = await b.join_matched()
		check(match_a.has("match_id") and match_a.get("match_id") == match_b.get("match_id"), "Matched users join same lobby")
	a.close()
	b.close()
	var unavailable = load(path).new()
	root.add_child(unavailable)
	unavailable.base_url = "http://127.0.0.1:19999"
	check(not await unavailable.guest_login("terrablast-smoke-offline"), "Unavailable backend returns failure")
	check(not unavailable.last_error.is_empty(), "Unavailable backend has actionable error")
	print("Nakama smoke: %d failures" % failures)
	quit(1 if failures else 0)
