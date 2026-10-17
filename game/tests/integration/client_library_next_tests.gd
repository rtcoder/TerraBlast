extends SceneTree
const Library = preload("res://scripts/core/storage/local_archive_library.gd")
const Replay = preload("res://scripts/core/replay/match_replay.gd")
var failures := 0
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280,720)
	var scene = load("res://scenes/debug/VoxelDebug.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_physics_process(false)
	var temporary_root := "/private/tmp" if OS.get_name() == "macOS" else "/tmp"
	var directory := temporary_root.path_join("terrablast-library-ui-%d" % OS.get_process_id())
	scene.library = Library.new(directory)
	scene._toggle_library()
	check(scene.library_panel.visible and scene.local_paused,"Library pauses local match")
	var velocity := Vector3(0.125,2.5,-0.25)
	scene.player_velocities["blue_1"] = velocity
	var before: String = Replay.state_hash(scene.runner)
	scene._library_save("session","Checkpoint UI")
	var listing: Dictionary = scene.library.list_entries("session")
	check(listing.ok and listing.entries.size()==1,"Named checkpoint saved")
	var checkpoint: String = listing.entries[0].id
	scene.runner.state.time_remaining -= 1
	check(scene._library_load(checkpoint),"Checkpoint loads")
	check(Replay.state_hash(scene.runner)==before and scene.player_velocities.blue_1==velocity,"Exact state and velocity restored")
	scene.session.recorder.tick(scene.runner,0.1)
	scene.session.recorder.tick(scene.runner,0.2)
	scene._toggle_library()
	scene._library_save("replay","Replay UI")
	listing = scene.library.list_entries("replay")
	check(listing.ok and listing.entries.size()==1,"Named replay saved")
	var replay_id: String = listing.entries[0].id
	var live = scene.runner
	var live_hash: String = Replay.state_hash(live)
	check(scene._library_load(replay_id),"Library opens inspector")
	check(scene.session.playback != null and scene.match_panels.replay_panel.visible,"Inspector visible")
	scene._toggle_replay_playing()
	scene._advance_replay(0.5)
	check(scene.session.playback.finished and Replay.state_hash(scene.runner)==live_hash,"Timed replay reaches exact final state")
	scene.match_panels.replay_seek.value = scene.match_panels.replay_seek.max_value
	scene._seek_replay_time(scene.match_panels.replay_seek.value)
	check(scene.session.playback.finished,"Slider exact endpoint reaches EOF")
	scene._rewind_replay()
	check(scene.session.playback.index==0,"Rewind resets cursor")
	scene.match_panels.replay_seek.grab_focus()
	var end_key := InputEventKey.new()
	end_key.keycode = KEY_END
	end_key.pressed = true
	Input.parse_input_event(end_key.duplicate())
	await process_frame
	await process_frame
	check(scene.session.playback.finished,"Keyboard End seeks after slider updates")
	end_key.pressed = false
	Input.parse_input_event(end_key.duplicate())
	end_key.keycode = KEY_LEFT
	end_key.pressed = true
	Input.parse_input_event(end_key.duplicate())
	await process_frame
	check(scene.session.playback.index == 1,"Left seeks previous action")
	end_key.keycode = KEY_RIGHT
	Input.parse_input_event(end_key.duplicate())
	await process_frame
	check(scene.session.playback.finished,"Right seeks next action")
	end_key.pressed = false
	Input.parse_input_event(end_key.duplicate())
	scene.match_panels.replay_seek.release_focus()

	scene._seek_replay_time(0.1)
	check(scene.session.playback.index==1,"Time seek selects boundary")
	scene._toggle_replay_playing()
	scene.match_panels.replay_speed.select(4)
	scene.match_panels.replay_speed.item_selected.emit(4)
	scene._toggle_settings()
	check(not scene.session.playback.playing,"Settings pauses replay")
	scene._return_from_replay()
	check(scene.runner==live and Replay.state_hash(live)==live_hash and scene.player_velocities.blue_1==velocity,"Return restores live match and velocity")
	check(scene._library_load(replay_id),"Reopen replay")
	check(scene.session.playback.speed == 1.0 and scene.match_panels.replay_speed.selected==2,"Speed selector resets with new playback")
	scene._return_from_replay()
	scene._toggle_library()
	scene._library_rename(checkpoint,"Renamed UI")
	listing = scene.library.list_entries("session")
	check(listing.entries[0].title=="Renamed UI","Rename via UI")
	var old_runner = scene.runner
	check(not scene._library_load("../bad") and scene.runner==old_runner,"Invalid ID preserves live runner")
	scene._library_delete(checkpoint)
	check(scene.library.list_entries("session").entries.is_empty(),"Delete via UI")
	scene._library_delete(replay_id)
	DirAccess.remove_absolute(directory)
	check(scene.bindings.rebind("jump",KEY_J).ok,"Remap jump")
	scene._apply_client_preferences()
	check(scene.match_panels.help_label.text.contains("J: jump"),"Help reflects remap")
	scene._close_overlays()
	scene.remote_mode = true
	scene._toggle_library()
	check(not scene.library_panel.visible,"Remote blocks library")
	scene.remote_mode = false
	if DisplayServer.get_name() != "headless":
		scene.preferences.hud_scale = 1.25
		scene._apply_client_preferences()
		scene._toggle_library()
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(temporary_root.path_join("terrablast-library-ui.png"))
		scene._toggle_settings()
		scene.settings_panel.get_child(0).scroll_vertical = 10000
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(temporary_root.path_join("terrablast-bindings-ui.png"))
	scene.queue_free()
	await process_frame
	print("Client library integration: %d failures" % failures)
	quit(0 if failures==0 else 1)
