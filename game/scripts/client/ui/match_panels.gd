extends Control
## Presentation and user intent only. Owner scene applies authoritative results.
signal save_requested
signal load_requested
signal export_requested
signal replay_requested
signal step_requested
signal rewind_requested
signal return_requested
var mode_select: OptionButton
var difficulty_select: OptionButton
var session_status: Label
var replay_panel: PanelContainer
var replay_status: Label
signal resume_requested
signal setup_requested(map_name: String, players: int, preset: String)
signal restart_requested
signal surrender_requested
signal close_requested
var pause_panel: PanelContainer
var setup_panel: PanelContainer
var help_panel: PanelContainer
var end_panel: PanelContainer
var end_label: Label
var restart_button: Button
var setup_error: Label
var panels: Array[Control] = []
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_panel = _panel("Match menu — P to close")
	_button(pause_panel, "Resume", func(): resume_requested.emit())
	_button(pause_panel, "Surrender current player", func(): surrender_requested.emit())
	_button(pause_panel, "Save local game", func(): save_requested.emit())
	_button(pause_panel, "Load local game", func(): load_requested.emit())
	_button(pause_panel, "Export replay", func(): export_requested.emit())
	_button(pause_panel, "Inspect last replay", func(): replay_requested.emit())
	session_status = Label.new()
	session_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box(pause_panel).add_child(session_status)
	replay_panel = _panel("Replay — action inspector")
	replay_status = Label.new()
	_box(replay_panel).add_child(replay_status)
	_button(replay_panel, "Next action", func(): step_requested.emit())
	_button(replay_panel, "Beginning", func(): rewind_requested.emit())
	_button(replay_panel, "Return to match", func(): return_requested.emit())
	setup_panel = _panel("New local match — F5 to close")
	_label(setup_panel, "Arena")
	var map_select := OptionButton.new()
	for key in GameConfig.MAPS:
		map_select.add_item(key)
	_box(setup_panel).add_child(map_select)
	_label(setup_panel, "Control mode / bot difficulty")
	mode_select = OptionButton.new()
	for key in ["hotseat", "solo"]:
		mode_select.add_item(key)
	_box(setup_panel).add_child(mode_select)
	difficulty_select = OptionButton.new()
	for key in ["easy", "normal"]:
		difficulty_select.add_item(key)
	difficulty_select.select(1)
	_box(setup_panel).add_child(difficulty_select)
	_label(setup_panel, "Players (solo: blue human / red bots)")
	var count := SpinBox.new()
	count.min_value = 2
	count.max_value = 10
	count.value = 10
	_box(setup_panel).add_child(count)
	_label(setup_panel, "Rules preset")
	var preset := OptionButton.new()
	for key in ["classic", "quick", "training"]:
		preset.add_item(key)
	_box(setup_panel).add_child(preset)
	setup_error = Label.new()
	_box(setup_panel).add_child(setup_error)
	_button(setup_panel, "Start new match", func(): setup_requested.emit(map_select.get_item_text(map_select.selected), int(count.value), preset.get_item_text(preset.selected)))
	_button(setup_panel, "Cancel", func(): close_requested.emit())
	help_panel = _panel("Controls — F6 to close")
	var help := Label.new()
	help.text = "Mouse: look | Wheel: zoom\nWASD / arrows: move | Space: jump\nHold RMB: aim\nHold LMB while aiming: charge; release: fire\nRelease RMB / Esc: cancel\n1 / 2 / 3: weapon | R: restart\nP: match menu (pauses local game)\nTab: scoreboard | F1: local diagnostics\nF2: multiplayer | F3: settings | F4: retry\nF5: new local match | F6: controls\nSolo: blue team human, red stationary bots\nP menu: save/load game, export/inspect replay"
	_box(help_panel).add_child(help)
	_button(help_panel, "Close", func(): close_requested.emit())
	end_panel = _panel("Match finished")
	end_label = Label.new()
	_box(end_panel).add_child(end_label)
	restart_button = _button(end_panel, "Restart", func(): restart_requested.emit())
	for panel in panels:
		panel.hide()
func _box(panel: PanelContainer) -> VBoxContainer:
	return panel.get_meta("box")
func _panel(title: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position = Vector2(30, 30)
	panel.custom_minimum_size = Vector2(460, 0)
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.025,0.04,0.08,0.97)
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		background.set_content_margin(side, 14)
	panel.add_theme_stylebox_override("panel", background)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.set_meta("panel_scroll", true)
	panel.add_child(scroll)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	panel.set_meta("box", box)
	var heading := Label.new()
	heading.text = title
	box.add_child(heading)
	panels.append(panel)
	return panel
func _button(panel: PanelContainer, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	_box(panel).add_child(button)
	return button
func hide_panels() -> void:
	for panel in panels:
		panel.hide()
func any_open() -> bool:
	return panels.any(func(panel): return panel.visible)

func _label(panel: PanelContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	_box(panel).add_child(label)

func _process(_delta: float) -> void:
	for panel in panels:
		var scroll: ScrollContainer = panel.get_child(0)
		var desired: float = _box(panel).get_combined_minimum_size().y
		scroll.custom_minimum_size.y = minf(desired, maxf(150.0, get_viewport_rect().size.y - 90.0))
