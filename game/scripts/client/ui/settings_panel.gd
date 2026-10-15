extends PanelContainer
signal closed
signal preferences_changed
var widgets := {}
var preferences: RefCounted
func setup(settings: RefCounted) -> void:
	preferences = settings
	position = Vector2(30, 230)
	custom_minimum_size = Vector2(390, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(390, minf(480.0, get_viewport_rect().size.y - 250.0))
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
	var reset := Button.new()
	reset.text = "Restore defaults"
	reset.pressed.connect(reset_preferences)
	box.add_child(reset)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func(): closed.emit())
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
