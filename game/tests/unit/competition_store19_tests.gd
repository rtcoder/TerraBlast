extends SceneTree
const Event = preload("res://scripts/core/competition/competition_event.gd")
const Config = preload("res://scripts/core/competition/competition_config.gd")
const Session = preload("res://scripts/core/replay/session_store.gd")
const Replay = preload("res://scripts/core/replay/match_replay.gd")
const Factory = preload("res://scripts/core/rules/match_factory.gd")
var failures := 0
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	if not FileAccess.file_exists("res://scripts/core/competition/competition_store.gd"):
		check(false,"Competition persistence not implemented")
		quit(1)
		return
	var Store = load("res://scripts/core/competition/competition_store.gd")
	var directory := ("/private/tmp" if OS.get_name()=="macOS" else "/tmp").path_join("terrablast-competition-store19-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join("competition.json")
	var event := Event.new()
	check(event.create(Config.defaults()).ok,"Create event")
	check(Store.save(path,event).ok,"Atomic draft save")
	var loaded: Dictionary = Store.load(path)
	check(loaded.ok and loaded.event.snapshot()==event.snapshot(),"Draft roundtrip")
	var before := FileAccess.get_file_as_bytes(path)
	check(not Store.save(path.path_join("not-a-directory"),event).ok,"Write failure reported")
	check(FileAccess.get_file_as_bytes(path)==before,"Failed save preserves previous file")
	var launch := event.launch(event.ready_ids()[0])
	var runner = Factory.create_match(2,GameConfig.MAPS.two_islands,"quick")
	var velocities := {}
	for player in runner.state.players: velocities[player.player_id] = Vector3(0.125,1.5,-0.25)
	var snapshot := Session.encode(runner,{"mode":"hotseat","difficulty":"normal","human_team":1},velocities)
	check(snapshot.ok,"Existing session codec encodes actual runner")
	var match_data := {"token":launch.token,"payload":snapshot.payload}
	check(Store.save(path,event,match_data).ok,"Active fixture save")
	loaded = Store.load(path)
	check(loaded.ok,"Active fixture loads: "+str(loaded.get("reason","verified")))
	if loaded.ok:
		check(Replay.state_hash(loaded.match.runner)==Replay.state_hash(runner),"Exact active runner hash")
		check(loaded.match.velocities==velocities,"Exact active velocities")
		check(loaded.event.snapshot()==event.snapshot(),"Exact tournament token and state")
	check(not Store.save(path,event).ok,"Active match cannot be silently omitted")
	var encoded: Dictionary = Store.encode(event.snapshot(),match_data)
	for mutation in ["version","unknown","token","hash","count","rules","weapons","dimensions"]:
		var candidate: Dictionary = encoded.payload.duplicate(true)
		match mutation:
			"version": candidate.version = 200
			"unknown": candidate.extra = true
			"token": candidate.match.token.attempt += 1
			"hash": candidate.match.payload.expected_hash = "0".repeat(64)
			"count": candidate.event.config.count = 4
			"rules":
				runner.rules.base_gravity += 0.25
				candidate.match.payload = Session.encode(runner,{"mode":"hotseat","difficulty":"normal","human_team":1},velocities).payload
				runner.rules.base_gravity -= 0.25
			"weapons":
				runner.weapons[1].terrain_damage += 1
				candidate.match.payload = Session.encode(runner,{"mode":"hotseat","difficulty":"normal","human_team":1},velocities).payload
				runner.weapons[1].terrain_damage -= 1
			"dimensions": candidate.event.config.maps = ["ballistics_range"]
		check(not Store.decode(candidate).ok,"Reject corrupt/mismatched "+mutation)
	check(event.snapshot().active==launch.token,"Rejected files never mutate live event")
	var abandoned := Event.new()
	abandoned.restore(event.snapshot())
	abandoned.abandon(launch.token)
	check(Store.save(path,abandoned).ok,"Abandoned match stores without payload")
	var oversized := FileAccess.open(path,FileAccess.WRITE)
	oversized.seek(Store.MAX_BYTES)
	oversized.store_8(32)
	oversized.close()
	check(not Store.load(path).ok,"Oversized file rejected before parse")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(directory)
	print("competition_store19: ","PASS" if failures==0 else "FAIL"," failures=",failures)
	quit(0 if failures==0 else 1)
