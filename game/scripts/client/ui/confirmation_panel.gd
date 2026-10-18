extends PanelContainer
signal confirmed(token: Dictionary)
signal cancelled
var token := {}
var message: Label
var focus = preload("res://scripts/client/ui/panel_focus_controller.gd").new()
func _ready():
	position = Vector2(40,40)
	custom_minimum_size = Vector2(420,0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025,0.04,0.08,1)
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]: style.set_content_margin(side,16)
	add_theme_stylebox_override("panel",style)
	var box := VBoxContainer.new()
	add_child(box)
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(message)
	for label in ["Cancel","Confirm"]:
		var button := Button.new()
		button.text = label
		box.add_child(button)
		if label == "Cancel": button.pressed.connect(func(): hide(); focus.close(self); cancelled.emit())
		else: button.pressed.connect(func():
			var captured := token.duplicate(true)
			hide()
			focus.close(self)
			confirmed.emit(captured))
	hide()
func present(title: String, detail: String, value: Dictionary) -> void:
	token = value.duplicate(true)
	message.text = title + "\n" + detail
	show()
	move_to_front()
	focus.open(self)
