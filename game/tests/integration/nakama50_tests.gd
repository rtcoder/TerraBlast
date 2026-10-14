extends SceneTree
var failures := 0
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var client = load("res://scripts/client/backend/nakama_client.gd").new()
	root.add_child(client)
	check(await client.guest_login("terrablast-cancel-regression"), "Guest login for cancellation")
	if client.token.is_empty():
		quit(1)
		return
	check(await client.connect_socket(), "Cancellation websocket opens")
	check(await client.find_match(), "Matchmaker accepts search")
	check(not client.matchmaking_ticket.is_empty() and client.searching, "Search tracks active server ticket")
	check(not await client.find_match(), "Duplicate search rejected before submitting another ticket")
	check(await client.cancel_matchmaking(), "Cancel removes ticket on real Nakama")
	check(client.matchmaking_ticket.is_empty() and not client.searching, "Cancel clears ticket and searching state")
	check(await client.cancel_matchmaking(), "Repeated cancel is idempotent")
	check(await client.find_match(), "Search can restart after cancellation")
	var consumed: Dictionary = await client.request("matchmaker_remove", {"ticket": client.matchmaking_ticket})
	check(not consumed.is_empty(), "Server consumes ticket before local cancellation")
	var cancelled: bool = await client.cancel_matchmaking()
	check(cancelled, "Already consumed server ticket finishes cancellation: " + client.last_error)
	check(client.matchmaking_ticket.is_empty() and not client.searching, "Consumed ticket cannot lock subsequent matchmaking")
	check(await client.find_match(), "Queue again after consumed-ticket cancellation race")
	client.close()
	check(client.matchmaking_ticket.is_empty() and not client.searching and client.matched.is_empty(), "Disconnect clears ticket and stale matched session")
	client.queue_free()
	print("Nakama50: %d failures" % failures)
	quit(1 if failures else 0)
