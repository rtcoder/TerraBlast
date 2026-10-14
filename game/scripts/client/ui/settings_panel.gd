extends PanelContainer
signal closed
var preferences: RefCounted
func setup(settings: RefCounted) -> void:
	preferences = settings
	position = Vector2(30, 210)
	custom_minimum_size = Vector2(390, 300)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	var title := Label.new()
	title.text = "Settings — F3 to close"
	box.add_child(title)
	_slider(box, "Volume", "volume", 0.0, 1.0, 0.05)
	_toggle(box, "Mute", "muted")
	_slider(box, "Mouse sensitivity", "sensitivity", 0.1, 3.0, 0.1)
	_toggle(box, "Invert vertical look", "invert_y")
	_toggle(box, "Fullscreen", "fullscreen")
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
	slider.value_changed.connect(func(value: float): _change(field, value))
	box.add_child(slider)
func _toggle(box: VBoxContainer, title: String, field: String) -> void:
	var toggle := CheckButton.new()
	toggle.text = title
	toggle.button_pressed = preferences.get(field)
	toggle.toggled.connect(func(value: bool): _change(field, value))
	box.add_child(toggle)
func _change(field: String, value: Variant) -> void:
	preferences.update({field: value})
	preferences.apply()
	if preferences.save_to() != OK:
		push_warning("Could not save client settings")
