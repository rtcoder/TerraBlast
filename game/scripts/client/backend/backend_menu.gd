extends CanvasLayer
signal menu_visibility_changed(open: bool)
signal connect_game(host: String)
signal retry_requested
const Profiles=preload("res://scripts/client/backend/connection_profiles.gd")
const Identity=preload("res://scripts/client/backend/guest_identity.gd")
var role_picker:OptionButton
var _selected_role:="player"
var profiles: RefCounted
var profile_picker: OptionButton
var profile_title: LineEdit
var backend_url: LineEdit
var game_status: Label
var retry_button: Button
var last_button: Button
var profile_confirmation: ConfirmationDialog
var pending_profile_delete := ""
var operation_generation := 0
var buttons := {}
var scroll: ScrollContainer
var content: VBoxContainer
var game_connection := {}
func setup_profiles(value: RefCounted) -> void:
	profiles=value
	if profile_picker!=null: _refresh_profiles()
var panel: PanelContainer
var status: Label
var lobby: LineEdit
var host: LineEdit
var port: SpinBox
var backend: Node
var busy := false

func _ready() -> void:
	layer = 20
	backend = load("res://scripts/client/backend/nakama_client.gd").new()
	add_child(backend)
	panel = PanelContainer.new()
	panel.position = Vector2(30, 30)
	panel.custom_minimum_size = Vector2(500, 0)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	content=box
	scroll=ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	var title := Label.new()
	title.text = "TerraBlast multiplayer — F2 to close"
	box.add_child(title)
	status = Label.new()
	status.text = "Guest login → create/join lobby or find opponent"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = 480
	box.add_child(status)
	backend.status_changed.connect(func(message: String): status.text = message)
	backend_url=LineEdit.new()
	backend_url.text=backend.base_url
	backend_url.placeholder_text="Nakama URL"
	box.add_child(backend_url)
	_button(box,"Apply backend URL",_apply_backend)
	_button(box, "Guest login", _login)
	_button(box, "Create lobby", _create)
	lobby = LineEdit.new()
	lobby.placeholder_text = "Lobby ID (copy to second player)"
	box.add_child(lobby)
	lobby.max_length=256
	lobby.text_submitted.connect(func(_value): _join())
	_button(box,"Copy lobby ID",_copy_lobby)
	_button(box, "Join lobby", _join)
	_button(box, "Find opponent — 1v1", _find)
	_button(box, "Cancel matchmaking", _cancel_search)
	_button(box,"Cancel operation / disconnect backend",_disconnect_backend)
	host = LineEdit.new()
	host.text = "127.0.0.1"
	host.placeholder_text = "Gameplay server address"
	box.add_child(host)
	var port_label := Label.new()
	port_label.text = "Gameplay server port"
	box.add_child(port_label)
	port = SpinBox.new()
	port.min_value = 1
	port.max_value = 65535
	port.value = int(GameConfig.argument("--port", "19170"))
	box.add_child(port)
	role_picker=OptionButton.new()
	role_picker.add_item("Player"); role_picker.add_item("Spectator")
	role_picker.select(1 if _selected_role=="spectator" else 0)
	role_picker.item_selected.connect(func(index:int): _selected_role="spectator" if index==1 else "player")
	box.add_child(role_picker)
	_button(box, "Connect to gameplay server", _connect_game)
	_button(box,"Copy server endpoint",_copy_endpoint)
	_setup_profiles(box)
	game_status=Label.new()
	game_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	box.add_child(game_status)
	_button(box,"Retry gameplay connection",func(): retry_requested.emit())
	retry_button=buttons["Retry gameplay connection"]
	retry_button.disabled=true
	backend.match_found.connect(_matched)
	panel.hide()

func _button(box: VBoxContainer, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	box.add_child(button)
	buttons[text]=button

func toggle(open: bool) -> void:
	panel.visible = open
	menu_visibility_changed.emit(open)

func _login() -> void:
	if busy:
		return
	busy = true
	var generation:=operation_generation
	var device := GameConfig.argument("--guest-id", "")
	if device.is_empty():
		var identity: Dictionary=Identity.load_or_create()
		if not identity.ok:
			status.text="Guest identity could not be saved: "+identity.reason
			busy=false
			return
		device=identity.id
	if await backend.guest_login(device):
		if generation!=operation_generation: return
		await backend.connect_socket()
	if generation==operation_generation: busy=false

func _create() -> void:
	if busy:
		return
	busy = true
	var generation:=operation_generation
	var result: Dictionary = await backend.create_lobby()
	if generation!=operation_generation: return
	if result.has("match_id"):
		lobby.text = result.match_id
		status.text = "Lobby created. Share its ID; then connect both clients to the gameplay server."
	if generation==operation_generation: busy = false

func _join() -> void:
	if busy:
		return
	busy = true
	var generation:=operation_generation
	var result: Dictionary = await backend.join_lobby(lobby.text.strip_edges())
	if generation!=operation_generation: return
	if result.has("match_id"):
		status.text = "Joined lobby. Connect to the gameplay server when ready."
	if generation==operation_generation: busy = false

func _find() -> void:
	if busy:
		return
	busy = true
	var generation:=operation_generation
	if await backend.find_match():
		if generation!=operation_generation: return
		status.text = "Waiting for one opponent…"
	if generation==operation_generation: busy = false

func _matched(_data: Dictionary) -> void:
	var generation:=operation_generation
	var result: Dictionary = await backend.join_matched()
	if generation!=operation_generation: return
	if result.has("match_id"):
		lobby.text = result.match_id
		status.text = "Opponent found; lobby joined. Enter the shared gameplay server address."

func _cancel_search() -> void:
	var generation:=operation_generation
	if await backend.cancel_matchmaking():
		if generation!=operation_generation: return
		status.text = "Matchmaking cancelled"

func selected_port() -> int:
	if port.get_line_edit().has_focus():
		port.apply()
	return int(port.value)

func _process(_delta: float) -> void:
	if scroll!=null:
		scroll.custom_minimum_size=Vector2(500,minf(content.get_combined_minimum_size().y,maxf(150,get_viewport().get_visible_rect().size.y-90)))
	if backend==null: return
	var connected: bool=backend.connection_state in ["connected","searching","matched"]
	for key in ["Create lobby","Join lobby","Find opponent — 1v1"]:
		buttons[key].disabled=busy or not connected or backend.searching
	buttons["Guest login"].disabled=busy
	buttons["Cancel matchmaking"].disabled=not backend.searching and backend.matchmaking_ticket.is_empty()
	if last_button!=null: last_button.disabled=profiles.last_success().is_empty()
func _disconnect_backend() -> void:
	operation_generation+=1
	busy=false
	backend.close()
	status.text="Backend disconnected"
func _apply_backend() -> void:
	if not Profiles.valid_url(backend_url.text.strip_edges()): status.text="Invalid backend URL"; return
	_disconnect_backend()
	if backend.set_endpoint(backend_url.text.strip_edges()): status.text="Backend URL applied. Log in to connect."
func _connect_game() -> void:
	if not Profiles.valid_host(host.text.strip_edges()): status.text="Invalid gameplay host"; return
	connect_game.emit(host.text.strip_edges())
	toggle(false)
func _copy_lobby() -> void:
	if not Profiles.clean(lobby.text.strip_edges(),1,256): status.text="No valid lobby ID to copy"; return
	DisplayServer.clipboard_set(lobby.text.strip_edges())
	status.text="Lobby ID copied"
func _copy_endpoint() -> void:
	var value:=host.text.strip_edges()
	if not Profiles.valid_host(value): status.text="Invalid gameplay host"; return
	DisplayServer.clipboard_set(("["+value+"]" if value.contains(":") else value)+":"+str(selected_port()))
	status.text="Server endpoint copied"
func _setup_profiles(box: VBoxContainer) -> void:
	if profiles==null:
		profiles=Profiles.new()
		var loaded: Dictionary=profiles.load_from()
		if not loaded.ok and loaded.reason!="open_failed": status.text="Saved endpoints unavailable: "+loaded.reason
	profile_picker=OptionButton.new()
	box.add_child(profile_picker)
	profile_picker.item_selected.connect(_select_profile)
	profile_title=LineEdit.new()
	profile_title.placeholder_text="Favorite name"
	profile_title.max_length=48
	box.add_child(profile_title)
	_button(box,"Add favorite",_add_profile)
	_button(box,"Update favorite",_update_profile)
	_button(box,"Delete favorite",_confirm_profile_delete)
	_button(box,"Use last successful",_use_last)
	last_button=buttons["Use last successful"]
	profile_confirmation=ConfirmationDialog.new()
	panel.add_child(profile_confirmation)
	profile_confirmation.confirmed.connect(func():
		var id:=pending_profile_delete
		pending_profile_delete=""
		_profile_result(profiles.remove_profile(id))
	)
	panel.visibility_changed.connect(func():
		if not panel.visible:
			profile_confirmation.hide()
			pending_profile_delete=""
	)
	_refresh_profiles()
func _refresh_profiles() -> void:
	var prior:=_profile_id()
	profile_picker.clear()
	profile_picker.add_item("Select a favorite")
	profile_picker.set_item_metadata(0,"")
	for row in profiles.list_profiles():
		profile_picker.add_item(row.title)
		var index:=profile_picker.item_count-1
		profile_picker.set_item_metadata(index,row.id)
		if row.id==prior: profile_picker.select(index)
func _profile_id() -> String:
	return str(profile_picker.get_item_metadata(profile_picker.selected)) if profile_picker!=null and profile_picker.selected>=0 else ""
func _select_profile(_index: int) -> void:
	for row in profiles.list_profiles():
		if row.id==_profile_id():
			profile_title.text=row.title
			_use_endpoint(row)
func _use_endpoint(row: Dictionary) -> void:
	host.text=row.host
	port.value=row.port
	backend_url.text=row.backend_url
	status.text="Endpoint selected. Apply backend URL or connect gameplay when ready."
func _profile_result(value: Dictionary) -> void:
	if not value.ok: status.text=value.reason; return
	var saved: Dictionary=profiles.save_to()
	_refresh_profiles()
	status.text="Favorite saved" if saved.ok else "Changed for this session; save failed: "+saved.reason
func _add_profile() -> void: _profile_result(profiles.add_profile(profile_title.text.strip_edges(),host.text.strip_edges(),selected_port(),backend_url.text.strip_edges()))
func _update_profile() -> void: _profile_result(profiles.update_profile(_profile_id(),{"title":profile_title.text.strip_edges(),"host":host.text.strip_edges(),"port":selected_port(),"backend_url":backend_url.text.strip_edges()}))
func _confirm_profile_delete() -> void:
	pending_profile_delete=_profile_id()
	if pending_profile_delete.is_empty(): status.text="Select a favorite"; return
	profile_confirmation.dialog_text="Delete favorite “"+profile_picker.get_item_text(profile_picker.selected)+"”?"
	profile_confirmation.popup_centered()
func _use_last() -> void:
	var row: Dictionary=profiles.last_success()
	if not row.is_empty(): _use_endpoint(row)
func record_connection_success(value_host: String, value_port: int) -> void:
	var saved: Dictionary=profiles.remember_success(value_host,value_port,backend.base_url)
	if saved.ok:
		saved=profiles.save_to()
		if not saved.ok: status.text="Connection succeeded; endpoint history save failed"
func present_game_connection(value: Dictionary) -> void:
	game_connection=value.duplicate(true)
	if game_status==null: return
	var progress: Dictionary=value.get("progress",{})
	game_status.text="Gameplay (%s): %s · %s:%s · %d/%d chunks\nRTT: %s · %s" % [value.get("role","player"),value.get("state","disconnected"),value.get("host",""),value.get("port",0),progress.get("completed",0),progress.get("total",0),str(value.latency_ms)+" ms" if value.get("latency_ms",-1)>=0 else "unavailable",value.get("last_error","")]
	retry_button.disabled=not value.get("can_retry",false)

func selected_role()->String:
	return _selected_role
func set_selected_role(value:String)->void:
	if value not in ["player","spectator"]: return
	_selected_role=value
	if role_picker!=null: role_picker.select(1 if value=="spectator" else 0)
