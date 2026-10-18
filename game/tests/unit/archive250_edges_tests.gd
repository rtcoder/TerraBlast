extends SceneTree
const Factory = preload("res://scripts/core/rules/match_factory.gd")
const Replay = preload("res://scripts/core/replay/match_replay.gd")
const Analyzer = preload("res://scripts/core/replay/replay_analyzer.gd")
const Playback = preload("res://scripts/core/replay/replay_playback.gd")
const Command = preload("res://scripts/core/turns/player_action_command.gd")
const Preferences = preload("res://scripts/client/session/library_preferences.gd")
const Library = preload("res://scripts/core/storage/local_archive_library.gd")
var failures := 0
func check(value: bool,label: String) -> void:
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	var runner = Factory.create_match(4)
	var recording = Replay.new()
	recording.capture(runner)
	recording.move(runner,Vector3.ZERO,Vector2(0,-1),0,false,0.1)
	recording.tick(runner,0.25)
	for unused in 2:
		var player = runner.state.get_active_player()
		var command = Command.new()
		command.player_id = player.player_id
		command.turn_id = runner.state.turn_id
		command.generation = runner.state.generation
		command.weapon_id = 1
		command.shot_power = 0.5
		command.aim_direction = Vector3(1,0.4,0).normalized()
		check(recording.submit(runner,command).ok,"Record valid shot")
		recording.tick(runner,0.2)
	var report := Analyzer.analyze(recording)
	check(report.ok and report.shots.size()==2 and report.action_types.shot==2,"Shot analysis")
	check(report.weapons.size()==1 and report.weapons[0].shots==2,"Weapon aggregate")
	check(report.turns.size()>=3 and report.shots[0].index<report.shots[1].index,"Turns and ordered shot bookmarks")
	check(report.players[0].distance>0 and report.players[0].active_time>0,"Movement/time attribution")
	check(report.final_hash==Replay.state_hash(runner),"Exact replay end state")
	check(Analyzer.compare(report,report).same_final,"Comparison identity")
	check(not Analyzer.compare({},report).ok,"Invalid comparison rejected")
	check(Analyzer.csv_cell('=a,"b"')=='"\'=a,""b"""',"CSV escaping/formula protection")
	check(Analyzer.to_csv(report,"players").contains("active_time"),"Player CSV header")
	check(Analyzer.to_csv(report,"shots").split("\r\n",false).size()==3,"Shot CSV rows")
	var analyzer = Analyzer.new()
	check(analyzer.begin(recording),"Start cancellable analysis")
	check(not analyzer.step(0).ok and analyzer.index==0,"Invalid budget preserves cursor")
	analyzer.step(1)
	analyzer.cancel()
	check(not analyzer.step(2).ok and analyzer.index==1 and analyzer.summary().reason=="cancelled","Cancel preserves partial cursor")
	var playback = Playback.new()
	check(playback.load_recording(recording),"Load playback")
	check(playback.next_turn() and playback.index==report.shots[0].index,"Next turn crosses first shot")
	check(playback.next_shot() and playback.index==report.shots[1].index,"Next shot bookmark")
	check(playback.previous_shot() and playback.index==report.shots[0].index,"Previous shot bookmark")
	check(playback.action_description().contains("power"),"Readable shot description")
	var before: int = playback.index
	check(not playback.seek(-1) and playback.index==before,"Failed seek preserves cursor")
	var copied = playback.recording_copy()
	copied.data.actions.clear()
	check(playback.action_count>0,"Recording copy cannot mutate playback")
	var base := ("/private/tmp" if OS.get_name()=="macOS" else "/tmp").path_join("tb250-edges-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(base)
	var path := base.path_join("preferences.json")
	var prefs = Preferences.new(path)
	var id := "0123456789abcdef0123456789abcdef"
	var fingerprint := "payload".sha256_text()
	check(prefs.toggle_favorite(id),"Favorite toggle")
	prefs.filters.query = "Żółć 重播"
	prefs.remember(id,fingerprint,2)
	check(prefs.save_to()==OK,"Save preferences")
	var loaded = Preferences.new(path)
	check(loaded.load_from() and loaded.favorites.has(id) and loaded.filters.query==prefs.filters.query,"Unicode preferences roundtrip")
	check(loaded.cursor(id,fingerprint,10)==2 and loaded.cursor(id,"other".sha256_text(),10)==0 and loaded.cursor(id,fingerprint,1)==0,"Cursor fingerprint/bounds")
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string('{"version":999}')
	file.close()
	check(not loaded.load_from() and loaded.favorites.has(id),"Corruption leaves existing preferences intact")
	var lib = Library.new(base.path_join("library"))
	var saved := lib.save_replay("Żółć  重播",recording,runner)
	check(saved.ok and lib.query({"query":"Żółć 重播"}).total==1,"Unicode normalized search")
	check(lib.query({"favorites_only":true,"favorites":[]}).total==0,"Favorites filter excludes absent")
	check(lib.query({"favorites_only":true,"favorites":[saved.id]}).total==1,"Favorites filter includes selected")
	check(not lib.export_entry(saved.id,lib.base_path.path_join(saved.id+".json"),true).ok,"Export cannot replace library envelope")
	var corrupt_id := "ffffffffffffffffffffffffffffffff"
	var corrupt_path: String = lib.base_path.path_join(corrupt_id+".json")
	file = FileAccess.open(corrupt_path,FileAccess.WRITE)
	file.store_string("broken")
	file.close()
	var health := lib.health_report()
	check(health.invalid==1 and health.errors[0].id==corrupt_id,"Corrupt entry identified")
	check(health.size_bytes==lib.preview(saved.id).size_bytes+6,"Storage bytes include corrupt entry")
	check(Analyzer.export_report(base.path_join("analysis.json"),report).ok,"Export JSON")
	check(not Analyzer.export_report(base.path_join("analysis.json"),report).ok,"Export requires explicit replacement")
	check(Analyzer.export_report(base.path_join("shots.csv"),report,"shots").ok,"Export CSV")
	lib.delete_entry(saved.id)
	lib.delete_entry(corrupt_id)
	DirAccess.remove_absolute(lib.base_path)
	for name in ["preferences.json","analysis.json","shots.csv"]: DirAccess.remove_absolute(base.path_join(name))
	DirAccess.remove_absolute(base)
	long_recording_and_legacy()
	print("archive250_edges: %d failures" % failures)
	quit(1 if failures else 0)

func long_recording_and_legacy() -> void:
	var runner = Factory.create_match(2)
	runner.rules.max_projectile_lifetime = 0.1
	var recording = Replay.new()
	recording.capture(runner)
	for unused in 40:
		var command = Command.new()
		command.player_id = runner.state.get_active_player().player_id
		command.turn_id = runner.state.turn_id
		command.generation = runner.state.generation
		command.weapon_id = 1
		command.shot_power = 0.5
		command.aim_direction = Vector3.UP
		check(recording.submit(runner,command).ok,"Long recording shot accepted")
	check(runner.history.size()==32,"Fixture exceeds bounded match history")
	var report := Analyzer.analyze(recording)
	check(report.ok and report.shots.size()==40 and report.weapons[0].shots==40,"Analyzer retains every shot beyond history cap")
	check(report.players[0].shots==20 and report.players[1].shots==20,"Player aggregates span whole recording")
	var archive = load("res://scripts/core/replay/replay_archive.gd")
	var decoded: Dictionary = archive.decode(archive.encode(recording,runner).payload)
	check(decoded.ok and Analyzer.analyze(decoded.recorder).final_hash==report.final_hash,"V2 exact archive analysis")
	var legacy := {"version":1,"recording":recording.data,"expected_hash":Replay.state_hash(runner,false)}
	decoded = archive.decode(JSON.parse_string(JSON.stringify(legacy,"",true,true)))
	check(decoded.ok and Analyzer.analyze(decoded.recorder).shots.size()==40,"Legacy V1 analysis through existing codec")
	check(recording.surrender(runner,runner.state.get_active_player().player_id).ok,"Recorded surrender")
	report = Analyzer.analyze(recording)
	check(report.ok and report.eliminations.size()==1 and report.eliminations[0].type=="surrender","Surrender elimination timeline")
	var invalid = Replay.new()
	invalid.data = recording.data.duplicate(true)
	invalid.data.actions[0].turn_id = 9999
	var analyzer = Analyzer.new()
	check(analyzer.begin(invalid),"Structurally valid but unexecutable recording loads")
	var failed: Dictionary = analyzer.step(32)
	check(not failed.ok and failed.index==0 and failed.type=="shot" and not analyzer.summary().ok,"First invalid action identified without false success")
