extends SceneTree
var failures := 0
func check(value: bool, label: String) -> void:
	if not value: failures += 1; push_error(label)
func _initialize() -> void:
	for path in ["res://scripts/client/backend/connection_profiles.gd", "res://scripts/client/backend/guest_identity.gd", "res://scripts/networking/transport/server_runtime_options.gd"]:
		check(FileAccess.file_exists(path), "Required network model: " + path)
	if failures: quit(1); return
	var Profiles = load("res://scripts/client/backend/connection_profiles.gd")
	var path := ("/private/tmp" if OS.get_name()=="macOS" else "/tmp").path_join("tb-profiles-%d.json") % OS.get_process_id()
	var profiles = Profiles.new(path)
	var a: Dictionary = profiles.add_profile("Local", "::1", 19170, "http://127.0.0.1:7350")
	check(a.ok, "IPv6 profile")
	check(not profiles.add_profile("Bad", "http://host/path", 1, "ftp://host").ok,"Invalid endpoint atomic")
	check(profiles.save_to().ok,"Atomic save")
	var other = Profiles.new(path)
	check(other.load_from().ok and other.list_profiles().size()==1,"Profile roundtrip")
	check(other.remember_success("localhost",19170,"http://localhost:7350").ok,"Success metadata")
	var file := FileAccess.open(path,FileAccess.WRITE); file.store_string("{}"); file.close()
	check(not other.load_from().ok and other.list_profiles().size()==1,"Corrupt load preserves model")
	var copy: Array = other.list_profiles(); copy[0].title="Mutated"
	check(other.list_profiles()[0].title=="Local","Profile snapshots immutable")
	check(other.remove_profile(a.id).ok and other.list_profiles().is_empty(),"Selected delete")
	for invalid in ["", "a".repeat(254), "user@host", "https://host", "bad host", "-host", "host..name"]:
		check(not Profiles.valid_host(invalid),"Invalid host: "+invalid.left(30))
	for valid in ["localhost","127.0.0.1","::1","game.example.test"]: check(Profiles.valid_host(valid),"Accepted host")
	for invalid in ["ftp://host","http://host/secret","http://user:pass@host","https://host:0","http://host:65536","http://host:"]:
		check(not Profiles.valid_url(invalid),"Invalid URL")
	check(Profiles.valid_url("https://[::1]:7350"),"IPv6 backend URL")
	for i in range(20): check(other.add_profile("Profile "+str(i),"localhost",19170,"http://localhost:7350").ok,"Fill profile capacity")
	check(not other.add_profile("Overflow","localhost",19170,"http://localhost:7350").ok,"Profile cap")
	var first: String=other.list_profiles()[0].id
	check(not other.update_profile(first,{"port":-1}).ok and other.list_profiles()[0].port==19170,"Invalid update atomic")
	check(other.update_profile(first,{"title":"Renamed"}).ok and other.list_profiles()[0].id==first,"Rename keeps ID")
	check(not other.save_to(path+"/missing/file.json").ok,"Persistence failure surfaced")
	DirAccess.remove_absolute(path)
	var Identity=load("res://scripts/client/backend/guest_identity.gd")
	var ident: Dictionary=Identity.load_or_create(path)
	check(ident.ok and Identity.load_or_create(path).id==ident.id,"Stable guest identity")
	file=FileAccess.open(path,FileAccess.WRITE); file.store_string("bad"); file.close()
	var repaired: Dictionary=Identity.load_or_create(path)
	check(repaired.ok and Identity.valid(repaired.id) and repaired.id!=ident.id,"Corrupt identity repaired")
	check(not Identity.load_or_create(path+"/missing").ok,"Identity save error")
	DirAccess.remove_absolute(path)
	var Options=load("res://scripts/networking/transport/server_runtime_options.gd")
	var options=Options.new()
	check(not options.apply({"reservation_seconds":NAN}).ok,"Runtime nonfinite rejected")
	check(options.apply({"reservation_seconds":15.0}).ok,"Runtime options applied")
	var client=load("res://scripts/networking/transport/match_client.gd").new()
	check(client.has_method("status_snapshot"),"Client status API")
	check(not client.status_snapshot().has("resume_token"),"Status omits secret")
	var Protocol=load("res://scripts/networking/messages/match_protocol.gd")
	for control in [{"type":"pong","nonce":NAN},{"type":"phase","phase":[]},{"type":"rejected","reason":"x","fatal":"yes"},{"type":"rejected","reason":"x".repeat(300)}]:
		check(not Protocol.valid_control(control),"Malformed control rejected")
	check(Protocol.valid_resume_token("a".repeat(64)) and not Protocol.valid_resume_token("forged"),"Resume token format")
	client.ready_for_match=true
	client.request_snapshot()
	var attempts: int=client.recovery_attempts
	client.request_snapshot()
	check(client.recovery_attempts==attempts and not client.ready_for_match,"Recovery coalesces")
	client.recovery_wait=0
	client.recovery_attempts=5
	client.request_snapshot()
	check(client.last_error=="snapshot_retries_exhausted","Recovery bounded")
	client.sync_age=44.5; client.sync_idle=0.0
	check(client._sync_watchdog(1.0) and client.last_error=="snapshot_overall_timeout","Overall sync deadline independent of recent activity")
	client.sync_age=1.0; client.sync_idle=9.5
	check(client._sync_watchdog(1.0) and client.last_error=="snapshot_idle_timeout","Idle sync deadline")
	client.free()
	print("network_backend250: %d failures" % failures)
	quit(1 if failures else 0)
