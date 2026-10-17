extends CanvasLayer
signal menu_visibility_changed(open: bool)
signal connect_game(host: String)
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
	panel.custom_minimum_size = Vector2(500, 360)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = "TerraBlast multiplayer — F2 to close"
	box.add_child(title)
	status = Label.new()
	status.text = "Guest login → create/join lobby or find opponent"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = 480
	box.add_child(status)
	backend.status_changed.connect(func(message: String): status.text = message)
	_button(box, "Guest login", _login)
	_button(box, "Create lobby", _create)
	lobby = LineEdit.new()
	lobby.placeholder_text = "Lobby ID (copy to second player)"
	box.add_child(lobby)
	_button(box, "Join lobby", _join)
	_button(box, "Find opponent — 1v1", _find)
	_button(box, "Cancel matchmaking", _cancel_search)
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
	_button(box, "Connect to gameplay server", func(): connect_game.emit(host.text.strip_edges()); toggle(false))
	backend.match_found.connect(_matched)
	panel.hide()

func _button(box: VBoxContainer, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	box.add_child(button)

func toggle(open: bool) -> void:
	panel.visible = open
	menu_visibility_changed.emit(open)

func _login() -> void:
	if busy:
		return
	busy = true
	var device := GameConfig.argument("--guest-id", "")
	if device.is_empty():
		var path := "user://guest_id.txt"
		if FileAccess.file_exists(path):
			device = FileAccess.get_file_as_string(path).strip_edges()
		else:
			device = Crypto.new().generate_random_bytes(16).hex_encode()
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file != null:
				file.store_string(device)
	if await backend.guest_login(device):
		await backend.connect_socket()
	busy = false

func _create() -> void:
	if busy:
		return
	busy = true
	var result: Dictionary = await backend.create_lobby()
	if result.has("match_id"):
		lobby.text = result.match_id
		status.text = "Lobby created. Share its ID; then connect both clients to the gameplay server."
	busy = false

func _join() -> void:
	if busy:
		return
	busy = true
	var result: Dictionary = await backend.join_lobby(lobby.text.strip_edges())
	if result.has("match_id"):
		status.text = "Joined lobby. Connect to the gameplay server when ready."
	busy = false

func _find() -> void:
	if busy:
		return
	busy = true
	if await backend.find_match():
		status.text = "Waiting for one opponent…"
	busy = false

func _matched(_data: Dictionary) -> void:
	var result: Dictionary = await backend.join_matched()
	if result.has("match_id"):
		lobby.text = result.match_id
		status.text = "Opponent found; lobby joined. Enter the shared gameplay server address."

func _cancel_search() -> void:
	if await backend.cancel_matchmaking():
		status.text = "Matchmaking cancelled"

func selected_port() -> int:
	if port.get_line_edit().has_focus():
		port.apply()
	return int(port.value)
