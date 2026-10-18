extends SceneTree
const F=preload("res://scripts/core/rules/match_factory.gd")
const R=preload("res://scripts/core/replay/match_replay.gd")
const A=preload("res://scripts/core/replay/replay_analyzer.gd")
var failures:=0
func check(ok: bool,label: String) -> void:
	if not ok: failures+=1; push_error(label)
func _initialize() -> void:
	var runner=F.create_match(2)
	var recorder=R.new()
	runner.state.get_active_player().display_name = "Review Name"
	recorder.capture(runner)
	var cmd=load("res://scripts/core/turns/player_action_command.gd").new()
	cmd.player_id=runner.state.get_active_player().player_id
	cmd.turn_id=runner.state.turn_id; cmd.generation=runner.state.generation
	cmd.weapon_id=1; cmd.shot_power=0.75; cmd.aim_direction=Vector3.DOWN
	check(recorder.submit(runner,cmd).ok,"Terrain fixture shot accepted")
	var report:=A.analyze(recorder)
	check(runner.history.back().terrain_destroyed>0,"Fixture destroys terrain")
	check(report.terrain.destroyed==runner.history.back().terrain_destroyed,"Analysis counts pre-shot materials destroyed")
	check(not report.terrain.materials.has("0"),"Destroyed terrain retains original material grouping")
	var playback=load("res://scripts/core/replay/replay_playback.gd").new()
	check(playback.load_recording(recorder) and playback.seek(1),"Playback fixture")
	check(playback.action_description().contains("Review Name"),"Action description uses player name")
	var directory=("/private/tmp" if OS.get_name()=="macOS" else "/tmp").path_join("tb-archive-review-%d"%OS.get_process_id())
	var library=load("res://scripts/core/storage/local_archive_library.gd").new(directory)
	var saved=library.save_replay("Test",recorder,runner)
	check(saved.ok,"Library fixture")
	var file_path=directory.path_join(saved.id+".json")
	var envelope=JSON.parse_string(FileAccess.get_file_as_string(file_path))
	envelope.payload={}
	var file=FileAccess.open(file_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(envelope));file.close()
	check(library.health_report().invalid==1 and library.health_report().entries==0,"Health verifies payload")
	DirAccess.remove_absolute(file_path);DirAccess.remove_absolute(directory)
	print("archive_review: %d failures"%failures)
	quit(1 if failures else 0)
