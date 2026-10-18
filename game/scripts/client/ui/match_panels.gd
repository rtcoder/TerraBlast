extends Control
## Presentation and user intent only. Owner scene applies authoritative results.
signal training_requested
signal autosave_requested
signal next_round_requested
var profiles = preload("res://scripts/client/session/local_match_profiles.gd").new()
var player_count: SpinBox
var preset_select: OptionButton
var human_team_select: OptionButton
var _last_configuration := {}
var series_select: OptionButton
var profile_select: OptionButton
var profile_name: LineEdit
var config_summary: Label
var start_button: Button
var handoff_panel: PanelContainer
signal handoff_ready
var delete_profile_pending := ""
signal save_requested
signal load_requested
signal export_requested
signal replay_requested
signal step_requested
signal rewind_requested
signal library_requested
signal play_requested
signal speed_requested(value: float)
signal seek_requested(value: float)
signal scrub_requested(direction: int)
signal next_shot_requested
var play_button: Button
var replay_speed: OptionButton
var replay_dragging := false
var replay_seek: HSlider
var help_label: Label
signal return_requested
var map_select: OptionButton
var map_description: Label
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
	_button(pause_panel, "Library — F8", func(): library_requested.emit())
	_button(pause_panel, "Training lessons", func(): training_requested.emit())
	_button(pause_panel, "Continue latest autosave", func(): autosave_requested.emit())
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
	play_button = _button(replay_panel, "Play", func(): play_requested.emit())
	replay_speed = OptionButton.new()
	for speed in [0.25,0.5,1.0,2.0,4.0]:
		replay_speed.add_item(str(speed) + "×")
		replay_speed.set_item_metadata(replay_speed.item_count-1,speed)
	replay_speed.select(2)
	replay_speed.item_selected.connect(func(index): speed_requested.emit(float(replay_speed.get_item_metadata(index))))
	_box(replay_panel).add_child(replay_speed)
	replay_seek = HSlider.new()
	replay_seek.step = 0.0
	replay_seek.tooltip_text = "Drag to seek time. Left/Right: previous/next action. Home/End: start/end."
	replay_seek.drag_started.connect(func(): replay_dragging = true)
	replay_seek.drag_ended.connect(func(changed):
		replay_dragging = false
		if changed: seek_requested.emit(replay_seek.value)
	)
	replay_seek.gui_input.connect(func(event):
		if event is InputEventKey and event.pressed:
			if event.keycode in [KEY_LEFT,KEY_RIGHT]:
				replay_seek.accept_event()
				scrub_requested.emit(-1 if event.keycode == KEY_LEFT else 1)
			elif event.keycode in [KEY_HOME,KEY_END]:
				_seek_after_keyboard.call_deferred()
	)
	_box(replay_panel).add_child(replay_seek)
	_button(replay_panel, "Next shot", func(): next_shot_requested.emit())
	_button(replay_panel, "Next action", func(): step_requested.emit())
	_button(replay_panel, "Beginning", func(): rewind_requested.emit())
	_button(replay_panel, "Return to match", func(): return_requested.emit())
	setup_panel = _panel("New local match — F5 to close")
	_label(setup_panel, "Arena")
	map_select = OptionButton.new()
	for key in GameConfig.MAPS:
		var info: Dictionary = preload("res://scripts/core/maps/map_registry.gd").describe(key)
		map_select.add_item(info.get("name", key))
		map_select.set_item_metadata(map_select.item_count - 1,key)
	_box(setup_panel).add_child(map_select)
	map_description = Label.new()
	map_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box(setup_panel).add_child(map_description)
	map_select.item_selected.connect(_describe_map)
	_describe_map(0)
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
	_label(setup_panel, "Players (choose human team below)")
	var count := SpinBox.new()
	player_count = count
	count.min_value = 2
	count.max_value = 10
	count.value = 10
	_box(setup_panel).add_child(count)
	_label(setup_panel, "Rules preset")
	var preset := OptionButton.new()
	preset_select = preset
	for key in ["classic", "quick", "training"]:
		preset.add_item(key)
	_box(setup_panel).add_child(preset)
	setup_error = Label.new()
	_box(setup_panel).add_child(setup_error)
	start_button = _button(setup_panel, "Start new match", func(): setup_requested.emit(str(map_select.get_item_metadata(map_select.selected)), int(count.value), preset.get_item_text(preset.selected)))
	_button(setup_panel, "Cancel", func(): close_requested.emit())
	help_panel = _panel("Controls — F6 to close")
	help_label = Label.new()
	var help := help_label
	help.text = "Mouse: look | Wheel: zoom\nWASD / arrows: move | Space: jump\nHold RMB: aim\nHold LMB while aiming: charge; release: fire\nRelease RMB / Esc: cancel\n1 / 2 / 3: weapon | R: restart\nP: match menu (pauses local game)\nTab: scoreboard | F1: local diagnostics\nF2: multiplayer | F3: settings | F4: retry\nF5: new local match | F6: controls | F7: lobby\nOnline lobby: name + Ready before play\nRematch: all players vote after the match\nSolo: blue team human, red stationary bots\nP menu: save/load game, export/inspect replay"
	_box(help_panel).add_child(help)
	_button(help_panel, "Close", func(): close_requested.emit())
	end_panel = _panel("Match finished")
	end_label = Label.new()
	_box(end_panel).add_child(end_label)
	restart_button = _button(end_panel, "Restart", func(): restart_requested.emit())
	_button(end_panel,"Next round in series",func(): next_round_requested.emit())
	handoff_panel = _panel("Pass control to the next player")
	_button(handoff_panel,"Ready",func(): handoff_ready.emit())
	_setup_local_tools()
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
		preload("res://scripts/client/ui/panel_layout.gd").fit(panel,scroll,get_viewport_rect().size)
	_update_configuration()

func _describe_map(index: int) -> void:
	var info: Dictionary = preload("res://scripts/core/maps/map_registry.gd").describe(str(map_select.get_item_metadata(index)))
	map_description.text = "%s\nCapacity: %d players" % [info.get("description", ""),info.get("player_capacity",0)]

func update_bindings(bindings: RefCounted) -> void:
	help_label.text = "Mouse: look | Wheel: zoom\n%s / %s / %s / %s or arrows: move\n%s: jump | Hold RMB: aim\nHold LMB while aiming: charge; release: fire\nRelease RMB / Esc: cancel\n%s / %s / %s: weapons | %s: restart\n%s: match menu | %s: scoreboard\nF1: local diagnostics | F2: multiplayer\nF3: settings / key bindings | F4: retry\nF5: new match | F6: controls | F7: lobby\nF8: local library of saves and replays\nReplay time includes recorded simulation ticks.\nOnline: all players Ready; unanimous rematch vote." % [bindings.label("move_forward"),bindings.label("move_left"),bindings.label("move_back"),bindings.label("move_right"),bindings.label("jump"),bindings.label("weapon_1"),bindings.label("weapon_2"),bindings.label("weapon_3"),bindings.label("restart"),bindings.label("pause"),bindings.label("scoreboard")]
	_box(pause_panel).get_child(0).text = "Match menu — %s to close" % bindings.label("pause")

func _seek_after_keyboard() -> void:
	seek_requested.emit(replay_seek.value)

func current_configuration() -> Dictionary:
	return {"map":str(map_select.get_item_metadata(map_select.selected)),"count":int(player_count.value),"preset":preset_select.get_item_text(preset_select.selected),"mode":mode_select.get_item_text(mode_select.selected),"difficulty":difficulty_select.get_item_text(difficulty_select.selected),"human_team":human_team_select.selected+1}

func apply_configuration(value: Dictionary) -> void:
	if not profiles.validate(value).ok: return
	for index in map_select.item_count:
		if map_select.get_item_metadata(index) == value.map: map_select.select(index)
	player_count.max_value = preload("res://scripts/core/maps/map_registry.gd").describe(value.map).get("player_capacity",10)
	player_count.value = value.count
	preset_select.select(["classic","quick","training"].find(value.preset))
	mode_select.select(["hotseat","solo"].find(value.mode))
	difficulty_select.select(["easy","normal"].find(value.difficulty))
	human_team_select.select(value.human_team-1)
	_describe_map(map_select.selected)

func _setup_local_tools() -> void:
	profiles.load_from()
	_label(setup_panel,"Human team (solo)")
	human_team_select = OptionButton.new()
	for title in ["Team A / Blue","Team B / Red"]: human_team_select.add_item(title)
	_box(setup_panel).add_child(human_team_select)
	_label(setup_panel,"Series length")
	series_select = OptionButton.new()
	for count in [1,3,5]: series_select.add_item("Best of " + str(count))
	_box(setup_panel).add_child(series_select)
	for key in profiles.templates():
		_button(setup_panel,"Template: " + key.replace("_"," "),func(): apply_configuration(profiles.templates()[key]))
	profile_select = OptionButton.new()
	_box(setup_panel).add_child(profile_select)
	profile_select.item_selected.connect(func(index):
		var title := profile_select.get_item_text(index)
		if profiles.profiles.has(title):
			apply_configuration(profiles.profiles[title])
			profile_name.text = title
		delete_profile_pending = "")
	profile_name = LineEdit.new()
	profile_name.placeholder_text = "Configuration profile name"
	profile_name.max_length = 48
	_box(setup_panel).add_child(profile_name)
	_button(setup_panel,"Save profile",func():
		var result: Dictionary = profiles.put_profile(profile_name.text,current_configuration())
		if not result.ok: setup_error.text = result.reason
		else:
			setup_error.text = "Profile saved" if profiles.save_to() == OK else "Profile changed; save failed"
			_refresh_profiles())
	_button(setup_panel,"Delete profile (press twice to confirm)",func():
		if profile_select.item_count == 0: return
		var title := profile_select.get_item_text(profile_select.selected)
		if delete_profile_pending != title:
			delete_profile_pending = title
			setup_error.text = "Press Delete again to remove: " + title
			return
		profiles.remove_profile(title)
		setup_error.text = "Profile removed" if profiles.save_to() == OK else "Profile removed in memory; save failed"
		delete_profile_pending = ""
		_refresh_profiles())
	config_summary = Label.new()
	config_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box(setup_panel).add_child(config_summary)
	_refresh_profiles()
	_box(setup_panel).move_child(start_button,_box(setup_panel).get_child_count()-1)
	for child in _box(setup_panel).get_children():
		if child is Button and child.text == "Cancel": _box(setup_panel).move_child(child,_box(setup_panel).get_child_count()-1)
	if not profiles.last_config.is_empty(): apply_configuration(profiles.last_config)

func _refresh_profiles() -> void:
	profile_select.clear()
	for title in profiles.profiles: profile_select.add_item(title)

func _update_configuration() -> void:
	if human_team_select == null: return
	var value := current_configuration()
	if value == _last_configuration: return
	var capacity: int = preload("res://scripts/core/maps/map_registry.gd").describe(value.map).get("player_capacity",10)
	player_count.max_value = mini(10,capacity)
	_last_configuration = current_configuration().duplicate()
	var result: Dictionary = profiles.validate(_last_configuration)
	start_button.disabled = not result.ok
	var rules = preload("res://scripts/core/rules/rule_presets.gd").create(value.preset)
	config_summary.text = "%s | %s players | %s | Human team %s\nHP %s | Turn %.0fs | Turn limit %s" % [value.map,int(player_count.value),value.mode,value.human_team,rules.starting_health,rules.turn_time,rules.max_turns]
