extends PanelContainer
const Config = preload("res://scripts/core/competition/competition_config.gd")
const Registry = preload("res://scripts/core/maps/map_registry.gd")
signal create_requested(config: Dictionary)
signal rename_requested(id: String, name: String)
signal play_requested(id: String)
signal save_requested
signal resume_requested
signal correction_requested(id: String, winner_team: int)
signal abandon_requested
signal exit_requested
signal close_requested
signal copy_report_requested
signal confirmed(action: String, payload: Dictionary)
var scroll: ScrollContainer
var box: VBoxContainer
var status: Label
var title_input: LineEdit
var format_select: OptionButton
var count_select: OptionButton
var preset_select: OptionButton
var entrant_box: VBoxContainer
var maps_box: GridContainer
var tabs := {}
var entrant_draft := []
var maps_checks := {}
var view := {}
var schedule_box: VBoxContainer
var standings_box: VBoxContainer
var results_box: VBoxContainer
var report: TextEdit
var confirm_box: VBoxContainer
var confirm_label: Label
var confirm_button: Button
var confirm_action := ""
var confirm_payload := {}
var create_button: Button
var preview: Label
var focus = preload("res://scripts/client/ui/panel_focus_controller.gd").new()
func _ready() -> void:
	name = "CompetitionPanel"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035,0.05,0.085,0.99)
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]: style.set_content_margin(side,14)
	add_theme_stylebox_override("panel",style)
	scroll = ScrollContainer.new()
	scroll.follow_focus = true
	add_child(scroll)
	box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	label(box,"LOCAL COMPETITION",20)
	label(box,"Offline hotseat · 2–8 teams · league, return legs or knockout")
	status = label(box,"")
	var actions := HBoxContainer.new()
	box.add_child(actions)
	button(actions,"Save",func(): save_requested.emit(),"SaveCompetition")
	button(actions,"Resume saved",func(): resume_requested.emit(),"ResumeCompetition")
	button(actions,"Return to game",func(): exit_requested.emit(),"ExitCompetition")
	button(actions,"Close",func(): close_requested.emit(),"CloseCompetition")
	var navigation := HBoxContainer.new()
	box.add_child(navigation)
	for tab_name in ["Create","Schedule","Standings","Results"]:
		var key: String = tab_name
		button(navigation,tab_name,func(): show_tab(key))
		var tab := VBoxContainer.new()
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(tab)
		tabs[tab_name] = tab
	_build_form(tabs.Create)
	schedule_box = tabs.Schedule
	standings_box = tabs.Standings
	results_box = tabs.Results
	confirm_box = VBoxContainer.new()
	box.add_child(confirm_box)
	confirm_label = label(confirm_box,"")
	var confirmation_actions := HBoxContainer.new()
	confirm_box.add_child(confirmation_actions)
	button(confirmation_actions,"Cancel",func(): confirm_box.hide())
	confirm_button = button(confirmation_actions,"Confirm",func():
		var action := confirm_action
		var payload := confirm_payload.duplicate(true)
		confirm_box.hide()
		confirmed.emit(action,payload),"ConfirmCompetition")
	confirm_box.hide()
	show_tab("Create")
	hide()
func label(parent: Node, text: String, font_size := 16) -> Label:
	var node := Label.new()
	node.text = text
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.set_meta("base_font_size",font_size)
	node.add_theme_font_size_override("font_size",font_size)
	parent.add_child(node)
	return node
func button(parent: Node, text: String, callback: Callable, node_name := "") -> Button:
	var node := Button.new()
	node.text = text
	if not node_name.is_empty(): node.name = node_name
	parent.add_child(node)
	node.pressed.connect(callback)
	return node
func _build_form(parent: VBoxContainer) -> void:
	label(parent,"Event name")
	title_input = LineEdit.new()
	title_input.name = "EventTitle"
	title_input.max_length = 64
	parent.add_child(title_input)
	label(parent,"Format · rules · characters (equal teams)")
	var choices := HBoxContainer.new()
	parent.add_child(choices)
	format_select = OptionButton.new()
	for format in ["league","double_league","knockout"]:
		format_select.add_item(format.replace("_"," "))
		format_select.set_item_metadata(format_select.item_count-1,format)
	choices.add_child(format_select)
	preset_select = OptionButton.new()
	for preset in ["classic","quick","training"]: preset_select.add_item(preset)
	choices.add_child(preset_select)
	count_select = OptionButton.new()
	for count in [2,4,6,8,10]: count_select.add_item(str(count))
	choices.add_child(count_select)
	format_select.item_selected.connect(func(_index): _update_preview())
	count_select.item_selected.connect(func(_index): _update_map_support())
	label(parent,"Participants · order determines seeding and the final tie-break")
	entrant_box = VBoxContainer.new()
	parent.add_child(entrant_box)
	button(parent,"Add participant (maximum 8)",_add_entrant,"AddParticipant")
	label(parent,"Arena rotation · click order follows this fixed list")
	maps_box = GridContainer.new()
	maps_box.columns = 2
	parent.add_child(maps_box)
	for id in Registry.PATHS:
		var checkbox := CheckBox.new()
		checkbox.text = id.replace("_"," ")
		maps_box.add_child(checkbox)
		maps_checks[id] = checkbox
	preview = label(parent,"")
	create_button = button(parent,"Create / update draft",func(): create_requested.emit(form_configuration()),"CreateCompetition")
	apply_configuration(Config.defaults())
func apply_configuration(config: Dictionary) -> void:
	title_input.text = config.title
	format_select.select(["league","double_league","knockout"].find(config.format))
	preset_select.select(["classic","quick","training"].find(config.preset))
	count_select.select([2,4,6,8,10].find(int(config.count)))
	entrant_draft = config.entrants.duplicate(true)
	for id in maps_checks: maps_checks[id].button_pressed = config.maps.has(id)
	_rebuild_entrants()
	_update_map_support()
func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
func _add_entrant() -> void:
	if entrant_draft.size()>=8: set_status("Maximum 8 participants",true); return
	var id := ""
	for i in range(1,9):
		var candidate := "entrant_%d" % i
		var used := false
		for row in entrant_draft:
			if row.id==candidate: used = true
		if not used: id = candidate; break
	entrant_draft.append({"id":id,"name":"Team %d" % (entrant_draft.size()+1),"seed":entrant_draft.size()})
	_rebuild_entrants()
func _rebuild_entrants() -> void:
	_clear(entrant_box)
	for index in entrant_draft.size():
		var captured := index
		entrant_draft[index].seed = index
		var row := HBoxContainer.new()
		entrant_box.add_child(row)
		var field := LineEdit.new()
		field.text = entrant_draft[index].name
		field.max_length = 32
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		field.name = "EntrantName%d" % index
		row.add_child(field)
		field.text_changed.connect(func(value): entrant_draft[captured].name = value)
		button(row,"↑",func(): _move_entrant(captured,-1)).disabled = index==0
		button(row,"↓",func(): _move_entrant(captured,1)).disabled = index==entrant_draft.size()-1
		button(row,"×",func(): entrant_draft.remove_at(captured); _rebuild_entrants()).disabled = entrant_draft.size()<=2
	_update_preview()
func _move_entrant(index: int, direction: int) -> void:
	var swap: Dictionary = entrant_draft[index]
	entrant_draft[index] = entrant_draft[index+direction]
	entrant_draft[index+direction] = swap
	_rebuild_entrants()
func _update_map_support() -> void:
	var count: int = [2,4,6,8,10][count_select.selected]
	for id in maps_checks:
		var supported: bool = Registry.describe(id).get("supported_player_counts",[]).has(count)
		maps_checks[id].disabled = not supported
		maps_checks[id].tooltip_text = "" if supported else "Arena does not support this character count"
		if not supported: maps_checks[id].button_pressed = false
	_update_preview()
func _update_preview() -> void:
	if preview==null: return
	var cfg := {"entrants":entrant_draft,"format":["league","double_league","knockout"][format_select.selected]}
	var metrics := Config.preview(cfg)
	preview.text = "%d rounds · %d matches · %d byes\nLeague: 3/1/0 points → head-to-head → wins → seeding. Knockout draws must be replayed." % [metrics.rounds,metrics.fixtures,metrics.byes]
func form_configuration() -> Dictionary:
	var maps := []
	for id in maps_checks:
		if maps_checks[id].button_pressed: maps.append(id)
	return {"title":title_input.text,"format":["league","double_league","knockout"][format_select.selected],"entrants":entrant_draft.duplicate(true),"maps":maps,"count":[2,4,6,8,10][count_select.selected],"preset":preset_select.get_item_text(preset_select.selected)}
func show_tab(key: String) -> void:
	for name_key in tabs: tabs[name_key].visible = key==name_key
	fit(get_viewport_rect().size,1.0)
func set_status(text: String, is_error := false) -> void:
	status.text = text
	status.modulate = Color(1,0.65,0.5) if is_error else Color.WHITE
func present_confirmation(action: String, text: String, payload: Dictionary) -> void:
	confirm_action = action
	confirm_payload = payload.duplicate(true)
	confirm_label.text = text
	confirm_box.show()
	confirm_button.grab_focus()
	scroll.ensure_control_visible(confirm_button)
func refresh(value: Dictionary) -> void:
	view = value.duplicate(true)
	var event_state: Dictionary = view.snapshot
	var config: Dictionary = event_state.config
	var names := {}
	for entrant in config.entrants: names[entrant.id] = entrant.name
	_clear(schedule_box)
	_clear(standings_box)
	_clear(results_box)
	label(schedule_box,config.title+" · "+config.format.replace("_"," "),20)
	if view.complete: label(schedule_box,"Champion: "+names.get(view.champion,"?"),20)
	if not event_state.last_draw.is_empty(): label(schedule_box,"Draw — replay required: "+event_state.last_draw.id)
	var last_round := -1
	for fixture in view.fixtures:
		if fixture.round!=last_round:
			last_round = fixture.round
			label(schedule_box,"Round %d" % (last_round+1),19)
		var outcome := "Pending"
		for result in event_state.results:
			if result.id==fixture.id: outcome = "Draw (0:0)" if result.winner_team==0 else "Winner: "+names.get(fixture.a if result.winner_team==1 else fixture.b,"?")
		if event_state.active.get("fixture_id","")==fixture.id: outcome = "In progress"
		var match_label := label(schedule_box,"%s [A/Blue] vs %s [B/Red]\n%s · %s" % [names.get(fixture.a,"Winner of "+fixture.source_a),names.get(fixture.b,"Winner of "+fixture.source_b),fixture.map,outcome])
		match_label.set_meta("participants",[fixture.a,fixture.b])
		var id: String = fixture.id
		var play := button(schedule_box,"Play match",func(): play_requested.emit(id),"Play_"+id)
		play.disabled = not view.ready.has(id)
		play.tooltip_text = "Waiting for earlier results or another match is active" if play.disabled else "Launch this match"
	if config.format!="knockout" and config.entrants.size()%2:
		for round_index in Config.preview(config).rounds:
			var present := []
			for fixture in view.fixtures:
				if fixture.round==round_index: present.append(fixture.a); present.append(fixture.b)
			for entrant in config.entrants:
				if not present.has(entrant.id): label(schedule_box,"Round %d bye: %s" % [round_index+1,entrant.name])
	elif config.format=="knockout": label(schedule_box,"Seeded byes: %d · advancement follows this bracket" % Config.preview(config).byes)
	if not event_state.active.is_empty(): button(schedule_box,"Abandon current attempt",func(): abandon_requested.emit())
	label(standings_box,"Points → head-to-head group points → wins → seeding")
	for row in view.standings:
		label(standings_box,"%d. %s · %d pts\nM %d / W %d / D %d / L %d · tie-break: %s" % [row.rank,row.name,row.points,row.played,row.wins,row.draws,row.losses,row.tiebreak])
		var entrant_id: String = row.id
		button(standings_box,"Show matches: "+row.name,func(): _show_participant(entrant_id))
	if config.format=="knockout": label(standings_box,"Knockout rankings are shown by advancement in Schedule.")
	label(standings_box,"Rename participant (identity and results stay attached)")
	for entrant in config.entrants:
		var row := HBoxContainer.new()
		standings_box.add_child(row)
		var field := LineEdit.new()
		field.text = entrant.name
		field.max_length = 32
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(field)
		var entrant_id: String = entrant.id
		button(row,"Rename",func(): rename_requested.emit(entrant_id,field.text))
	label(results_box,"Completed matches and direct encounters")
	for result in event_state.results:
		var fixture := {}
		for candidate in view.fixtures:
			if candidate.id==result.id: fixture = candidate; break
		label(results_box,"%s vs %s — %s · attempt %d" % [names.get(fixture.a,"?"),names.get(fixture.b,"?"),"Draw (0:0)" if result.winner_team==0 else names.get(fixture.a if result.winner_team==1 else fixture.b,"?"),result.attempt])
		if config.format!="knockout":
			var choices := HBoxContainer.new()
			results_box.add_child(choices)
			var id: String = result.id
			for winner in [1,0,2]:
				var captured: int = winner
				button(choices,"Correct: "+("A" if winner==1 else "B" if winner==2 else "Draw"),func(): correction_requested.emit(id,captured)).disabled = not event_state.active.is_empty()
	report = TextEdit.new()
	report.name = "CompetitionReport"
	report.editable = false
	report.text = view.report
	report.custom_minimum_size = Vector2(0,200)
	report.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	results_box.add_child(report)
	button(results_box,"Copy report",func(): copy_report_requested.emit())
	fit(get_viewport_rect().size,1.0)
func _show_participant(id: String) -> void:
	show_tab("Schedule")
	for child in schedule_box.get_children():
		if child is Label and child.has_meta("participants"):
			child.visible = child.get_meta("participants").has(id)
		elif child is Button and child.name.begins_with("Play_"):
			var fixture_id := String(child.name).trim_prefix("Play_")
			for fixture in view.fixtures:
				if fixture.id==fixture_id: child.visible = fixture.a==id or fixture.b==id
func fit(viewport: Vector2, hud_scale := 1.0) -> void:
	if scroll==null: return
	var available := viewport-Vector2(32,32)
	position = Vector2(16,16)
	size = Vector2(minf(720,available.x),available.y)
	custom_minimum_size = Vector2.ZERO
	scroll.custom_minimum_size = Vector2.ZERO
	box.custom_minimum_size.x = maxf(240,size.x-42)
	add_theme_font_size_override("font_size",roundi(16*hud_scale))
	_scale_labels(self,hud_scale)
func _scale_labels(parent: Node, scale_value: float) -> void:
	for child in parent.get_children():
		if child.has_meta("base_font_size"): child.add_theme_font_size_override("font_size",roundi(float(child.get_meta("base_font_size"))*scale_value))
		_scale_labels(child,scale_value)
