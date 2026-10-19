extends Node
var transport: Node
var shutdown_requested := false
var shutdown_deadline := 0
var runtime_options := {}
var shutdown_after := 0.0
var server_started_at := 0
var report_path := ""
var shutdown_reason := ""
var shutdown_report := {}
var exit_status := 0
func _ready() -> void:
	get_tree().auto_accept_quit=false
	var flags:={"--spectators":"spectator_capacity","--reservation-seconds":"reservation_seconds","--hello-seconds":"hello_seconds","--packet-rate":"packets_per_second","--byte-rate":"bytes_per_second","--snapshot-chunks":"snapshot_chunks_per_frame","--snapshot-bytes":"snapshot_bytes_per_frame","--receive-bytes":"receive_bytes_per_frame"}
	var args:=OS.get_cmdline_user_args()
	for flag in flags:
		if args.has(flag):
			var raw:String=GameConfig.argument(flag,"")
			if not raw.is_valid_float() or not is_finite(raw.to_float()): get_tree().quit(2); return
			runtime_options[flags[flag]]=raw.to_float()
	if args.has("--lobby-chat"): runtime_options.chat_enabled=true
	shutdown_after=float(GameConfig.argument("--shutdown-after","0"))
	report_path=GameConfig.argument("--server-report","")
	if not report_path.is_empty() and not _valid_report_path(report_path):
		push_error("Server report requires a .json path with an existing parent outside the project.")
		get_tree().quit(2)
		return
	server_started_at=Time.get_ticks_msec()
	transport = load("res://scripts/networking/transport/match_server.gd").new()
	add_child(transport)
	if not runtime_options.is_empty():
		if not transport.apply_options(runtime_options).ok:
			get_tree().quit(2)
			return
	var capacity := int(GameConfig.argument("--players", "2"))
	var require_ready := OS.get_cmdline_user_args().has("--lobby")
	var preset: String = GameConfig.argument("--preset", "classic")
	var error: Error = transport.start(int(GameConfig.argument("--port", "19170")), GameConfig.map_path(), preset, capacity, require_ready)
	if error != OK:
		push_error("Cannot start match server: %s" % error_string(error))
		get_tree().quit(1)
		return
	print("TerraBlast server ready; core players=%d map=%s preset=%s capacity=%d mode=%s" % [transport.runner.state.players.size(), GameConfig.argument("--map", "twin_forts"), preset, capacity, "lobby" if require_ready else "auto"])
	print("Spectator capacity=%d; lobby chat=%s" % [transport.spectator_capacity,str(transport.runtime_options.values.chat_enabled)])
	if args.has("--print-roster"): print(diagnostic_roster_json())
	if OS.get_cmdline_user_args().has("--smoke"):
		for child in get_children():
			if child is Node3D or child is Control:
				get_tree().quit(1)
		get_tree().quit(0)

func request_shutdown(reason: String = "requested") -> void:
	if shutdown_requested: return
	shutdown_requested=true
	shutdown_deadline=Time.get_ticks_msec()+1000
	shutdown_reason=reason.substr(0,64)
	if transport!=null: transport.graceful_shutdown()
	shutdown_report=transport.diagnostic_snapshot() if transport!=null else {"phase":"stopped"}
	shutdown_report["shutdown_reason"]=shutdown_reason
	if not report_path.is_empty():
		var saved: Error=preload("res://scripts/server/utility_cli.gd").write_atomic(ProjectSettings.globalize_path(report_path),JSON.stringify(shutdown_report))
		if saved!=OK:
			push_error("Server report write failed")
			exit_status=1
func _process(_delta: float) -> void:
	if shutdown_after>0 and not shutdown_requested and (Time.get_ticks_msec()-server_started_at)/1000.0>=shutdown_after: request_shutdown("deadline")
	if shutdown_requested and (transport==null or transport.peer==null or Time.get_ticks_msec()>=shutdown_deadline):
		if transport!=null: transport.close()
		get_tree().quit(exit_status)
func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST: request_shutdown("window_close")
func diagnostic_json() -> String:
	return JSON.stringify(transport.diagnostic_snapshot() if transport!=null else {"phase":"stopped"})

static func _valid_report_path(value: String) -> bool:
	if value.begins_with("res://") or value.get_extension().to_lower()!="json": return false
	var target:=ProjectSettings.globalize_path(value).simplify_path()
	var project:=ProjectSettings.globalize_path("res://").simplify_path().trim_suffix("/")
	if not target.is_absolute_path() or target==project or target.begins_with(project+"/"): return false
	# Reject directory links too: a sibling symlink must not redirect into sources.
	var current:=target
	while current!="/" and not current.is_empty():
		var ancestor:=DirAccess.open(current.get_base_dir())
		if ancestor!=null and ancestor.is_link(current.get_file()): return false
		var parent:=current.get_base_dir()
		if parent==current: break
		current=parent
	var directory:=DirAccess.open(target.get_base_dir())
	return directory!=null and not DirAccess.dir_exists_absolute(target)

func diagnostic_roster_json()->String:
	return JSON.stringify(transport.participant_roster() if transport!=null else {"players":[],"spectators":[]})
