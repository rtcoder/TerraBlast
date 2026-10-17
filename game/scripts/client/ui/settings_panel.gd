extends PanelContainer
signal closed
signal preferences_changed
var widgets := {}
var preferences: RefCounted
var bindings: RefCounted
var binding_buttons := {}
var binding_status: Label
var capture_action := ""

func setup(settings: RefCounted, input_bindings: RefCounted = null) -> void:
	bindings = input_bindings
	preferences = settings
	position = Vector2(30, 30)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.04, 0.08, 0.97)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	add_theme_stylebox_override("panel", style)
	custom_minimum_size = Vector2(390, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(390, maxf(160.0, minf(630.0, (get_viewport_rect().size.y - 90.0) / 1.25)))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	var title := Label.new()
	title.text = "Settings — F3 to close"
	box.add_child(title)
	_slider(box, "Volume", "volume", 0.0, 1.0, 0.05)
	_toggle(box, "Mute", "muted")
	_slider(box, "Mouse sensitivity", "sensitivity", 0.1, 3.0, 0.1)
	_toggle(box, "Invert vertical look", "invert_y")
	_toggle(box, "Fullscreen", "fullscreen")
	_slider(box, "HUD text scale", "hud_scale", 1.0, 1.25, 0.05)
	_toggle(box, "Trajectory preview", "show_trajectory")
	_toggle(box, "High contrast crosshair", "high_contrast")
	if bindings != null:
		binding_status = Label.new()
		binding_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(binding_status)
		for action in bindings.DEFAULTS:
			var button := Button.new()
			binding_buttons[action] = button
			button.pressed.connect(begin_capture.bind(action))
			box.add_child(button)
		_refresh_bindings()
	visibility_changed.connect(func():
		if not visible:
			cancel_capture())
	var reset := Button.new()
	reset.text = "Restore defaults"
	reset.pressed.connect(reset_preferences)
	box.add_child(reset)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func():
		cancel_capture()
		closed.emit())
	box.add_child(close)
	hide()
func _slider(box: VBoxContainer, title: String, field: String, minimum: float, maximum: float, step: float) -> void:
	var label := Label.new()
	label.text = title
	box.add_child(label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = preferences.get(field)
	widgets[field] = slider
	slider.value_changed.connect(func(value: float): _change(field, value))
	box.add_child(slider)
func _toggle(box: VBoxContainer, title: String, field: String) -> void:
	var toggle := CheckButton.new()
	toggle.text = title
	toggle.button_pressed = preferences.get(field)
	widgets[field] = toggle
	toggle.toggled.connect(func(value: bool): _change(field, value))
	box.add_child(toggle)
func _change(field: String, value: Variant) -> void:
	preferences.update({field: value})
	preferences.apply()
	preferences_changed.emit()
	if preferences.save_to() != OK:
		push_warning("Could not save client settings")

func reset_preferences(persist: bool = true) -> void:
	cancel_capture()
	if bindings != null:
		bindings.reset_defaults()
		_refresh_bindings()
		if persist:
			_binding_save()
	preferences.reset_defaults()
	for field in widgets:
		var widget: Control = widgets[field]
		if widget is Range:
			widget.set_value_no_signal(preferences.get(field))
		elif widget is BaseButton:
			widget.set_pressed_no_signal(preferences.get(field))
	preferences.apply()
	preferences_changed.emit()
	if persist and preferences.save_to() != OK:
		push_warning("Could not save default settings")

func _refresh_bindings() -> void:
	for action in binding_buttons:
		binding_buttons[action].text = action.replace("_", " ").capitalize() + ": " + bindings.label(action)

func is_capturing() -> bool:
	return not capture_action.is_empty()

func begin_capture(action: String) -> void:
	if bindings == null or not bindings.DEFAULTS.has(action):
		return
	capture_action = action
	binding_status.text = "Press a key for " + action + " (Escape cancels)"

func cancel_capture() -> void:
	capture_action = ""
	if binding_status != null:
		binding_status.text = ""

func capture_event(event: InputEvent, persist: bool = true) -> bool:
	if not is_capturing():
		return false
	if not event is InputEventKey or not event.pressed or event.echo:
		return true
	var key: int = bindings.event_key(event)
	if key == KEY_ESCAPE:
		cancel_capture()
		return true
	var result: Dictionary = bindings.rebind(capture_action, key)
	if not result.ok:
		binding_status.text = result.error
		return true
	capture_action = ""
	_refresh_bindings()
	binding_status.text = "Binding changed"
	if persist:
		_binding_save()
	preferences_changed.emit()
	return true

func _binding_save() -> void:
	var result: Error = bindings.save_settings()
	if result != OK:
		binding_status.text = "Binding changed for this session; save failed: " + error_string(result)

func _notification(what: int) -> void:
	if what == MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT:
		cancel_capture()
