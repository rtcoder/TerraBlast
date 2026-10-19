extends SceneTree
const CompetitionPanel = preload("res://scripts/client/competition/competition_panel.gd")
const Event = preload("res://scripts/core/competition/competition_event.gd")
const Config = preload("res://scripts/core/competition/competition_config.gd")
var failures := 0
var created := {}
var played := ""
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(800,600)
	var panel := CompetitionPanel.new()
	root.add_child(panel)
	panel.show()
	panel.fit(Vector2(800,600),1.25)
	panel.create_requested.connect(func(value): created = value)
	panel.play_requested.connect(func(value): played = value)
	panel.title_input.text = "Native keyboard cup"
	panel.create_button.pressed.emit()
	check(created.title=="Native keyboard cup" and created.entrants.size()==2,"Native form emits entered configuration")
	var event := Event.new()
	event.create(created)
	panel.refresh({"snapshot":event.snapshot(),"fixtures":event.fixtures(),"ready":event.ready_ids(),"standings":event.standings(),"champion":"","complete":false,"report":event.report(),"dirty":false})
	panel.show_tab("Schedule")
	await process_frame
	var play: Button = panel.schedule_box.get_node("Play_league_0")
	play.grab_focus()
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = true
	Input.parse_input_event(key)
	await process_frame
	key.pressed = false
	Input.parse_input_event(key)
	await process_frame
	check(played=="league_0","Keyboard Enter invokes visible Play button")
	check(panel.get_rect().end.x<=800 and panel.get_rect().end.y<=600,"Native panel fits 800x600")
	panel.show_tab("Create")
	panel._add_entrant()
	panel._move_entrant(2,-1)
	check(panel.form_configuration().entrants[1].id=="entrant_3","Reordering keeps participant identity")
	panel.entrant_draft[1].name = "A very long participant name Żółw"
	panel._rebuild_entrants()
	panel.present_confirmation("replace","Replace the current competition?",{"revision":7})
	await process_frame
	check(panel.confirm_button.has_focus(),"Confirmation receives keyboard focus")
	if OS.get_environment("TB_COMPETITION_SCREENSHOT")!="":
		panel.confirm_box.hide()
		panel.fit(Vector2(800,600),1.25)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("TB_COMPETITION_SCREENSHOT"))
	panel.queue_free()
	await process_frame
	print("competition_panel19: ","PASS" if failures==0 else "FAIL"," failures=",failures)
	quit(0 if failures==0 else 1)
