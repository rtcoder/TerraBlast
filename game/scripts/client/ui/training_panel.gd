extends PanelContainer
signal lesson_requested(id: String)
signal retry_requested
signal last_retry_requested
signal continue_requested
signal next_requested
signal coach_requested
signal demonstrate_requested
signal exit_requested
signal assistance_changed(mode: String)
signal reset_progress_requested
var lesson_select: OptionButton
var description: Label
var status: Label
var hint: Label
var assistance_select: OptionButton
var _lessons: Array
var _progress: RefCounted
var scroll: ScrollContainer
func setup(lessons: Array, progress: RefCounted) -> void:
	_lessons = lessons
	_progress = progress
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025,0.04,0.08,0.97)
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]: style.set_content_margin(side,14)
	add_theme_stylebox_override("panel",style)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	lesson_select = OptionButton.new()
	for lesson in lessons:
		lesson_select.add_item(lesson.id.replace("_"," ").capitalize())
		lesson_select.set_item_metadata(lesson_select.item_count-1,lesson.id)
	box.add_child(lesson_select)
	description = Label.new()
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(description)
	lesson_select.item_selected.connect(func(_index): _describe())
	_describe()
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status)
	_button(box,"Begin selected lesson",func(): lesson_requested.emit(lesson_select.get_item_metadata(lesson_select.selected)))
	assistance_select = OptionButton.new()
	for mode in ["full","partial","none"]: assistance_select.add_item(mode)
	assistance_select.item_selected.connect(func(index): assistance_changed.emit(assistance_select.get_item_text(index)))
	box.add_child(assistance_select)
	_button(box,"Continue / practise",func(): continue_requested.emit())
	_button(box,"Retry lesson",func(): retry_requested.emit())
	_button(box,"Retry last shot",func(): last_retry_requested.emit())
	_button(box,"Next lesson",func(): next_requested.emit())
	hint = Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	_button(box,"Coach: suggest shot",func(): coach_requested.emit())
	_button(box,"Demonstrate suggested shot",func(): demonstrate_requested.emit())
	_button(box,"Reset lesson progress",func(): reset_progress_requested.emit())
	_button(box,"Return to original match",func(): exit_requested.emit())
	hide()
func _button(box: VBoxContainer, title: String, callback: Callable):
	var button := Button.new()
	button.text = title
	button.pressed.connect(callback)
	box.add_child(button)
func _describe():
	var lesson: Dictionary = _lessons[lesson_select.selected]
	description.text = lesson.description + ("\nCompleted ✓" if _progress.is_complete(lesson.id) else "")
func update_state(summary: Dictionary, suggestion: Dictionary) -> void:
	status.text = "%s — %s\nAttempts %s | Hits %s | Damage %s | Friendly damage %s\nActive time %.1fs | Streak %s" % [summary.lesson,summary.phase,summary.attempts,summary.hits,summary.enemy_damage,summary.friendly_damage,summary.seconds,summary.streak]
	if not summary.best.is_empty(): status.text += "\nBest: %.2fm from target | %s damage" % [summary.best.distance,summary.best.enemy_damage]
	if summary.has("last") and not summary.last.is_empty(): status.text += "\nLast: %.2fm from target | power %.2f | weapon %s" % [summary.last.distance,summary.last.power,summary.last.weapon]
	hint.text = "Coach power %.2f; direction %s" % [suggestion.command.shot_power,str(suggestion.command.aim_direction)] if suggestion.get("ok",false) else suggestion.get("reason","")
	_describe()
func _process(_delta):
	if scroll != null: preload("res://scripts/client/ui/panel_layout.gd").fit(self,scroll,get_viewport_rect().size)
