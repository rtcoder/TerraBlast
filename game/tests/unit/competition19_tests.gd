extends SceneTree
var failures := 0
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void: call_deferred("run")
func configuration(n: int, format := "league") -> Dictionary:
	var entrants := []
	for i in n: entrants.append({"id":"entrant_%d" % (i+1),"name":"Team %d" % (i+1),"seed":i})
	return {"title":"Local cup","format":format,"entrants":entrants,"maps":["two_islands"],"count":2,"preset":"quick"}
func run() -> void:
	if not FileAccess.file_exists("res://scripts/core/competition/competition_event.gd"):
		check(false,"Competition event is not implemented")
		quit(1)
		return
	var Event = load("res://scripts/core/competition/competition_event.gd")
	var Config = load("res://scripts/core/competition/competition_config.gd")
	var Schedule = load("res://scripts/core/competition/competition_schedule.gd")
	for n in range(2,9):
		for format in ["league","double_league","knockout"]:
			var cfg := configuration(n,format)
			var event = Event.new()
			check(event.create(cfg).ok,"Valid configuration %d %s" % [n,format])
			var expected: int = n-1 if format == "knockout" else n*(n-1)/2*(2 if format == "double_league" else 1)
			check(event.fixtures().size()==expected,"Hand-derived fixture count %d %s" % [n,format])
			check(Schedule.generate(cfg)==Schedule.generate(cfg),"Deterministic schedule")
			var pairs := {}
			var rounds := {}
			var sides := {}
			if format != "knockout":
				for fixture in event.fixtures():
					var pair := [fixture.a,fixture.b]
					pair.sort()
					var key := str(pair)
					pairs[key] = pairs.get(key,0)+1
					for id in [fixture.a,fixture.b]:
						var round_key := "%d/%s" % [fixture.round,id]
						check(not rounds.has(round_key),"One fixture per entrant per round")
						rounds[round_key] = true
					sides[fixture.a] = sides.get(fixture.a,0)+1
					sides[fixture.b] = sides.get(fixture.b,0)-1
				for count in pairs.values(): check(count==(2 if format=="double_league" else 1),"Each pairing occurs once per leg")
				for balance in sides.values(): check(abs(balance)<=(0 if format=="double_league" else 1),"Balanced A/B assignment")
			var limit := 0
			while not event.is_complete() and limit<60:
				var ready: Array = event.ready_ids()
				check(not ready.is_empty(),"Unfinished event has a ready match")
				if ready.is_empty(): break
				var launch: Dictionary = event.launch(ready.back())
				check(launch.ok,"Launch selected ready match")
				check(not event.launch(ready.back()).ok,"No parallel active fixture")
				if format=="knockout" and limit==0:
					check(event.record(launch.token,0).ok,"Knockout draw accepted for replay")
					check(event.snapshot().results.is_empty(),"Draw does not promote a knockout entrant")
					var old: Dictionary = launch.token
					launch = event.launch(ready.back())
					check(not event.record(old,1).ok,"Stale draw replay token rejected")
				check(event.record(launch.token,1).ok,"Authoritative mapped team result")
				check(not event.record(launch.token,1).ok,"Repeated result deduplicated")
				limit += 1
			check(event.is_complete() and not event.champion().is_empty(),"Whole event completes")
			var restored = Event.new()
			check(restored.restore(event.snapshot()).ok,"Completed event validates on restore")
			check(restored.report()==event.report(),"Report stable across restore")
	for patch in [{"title":""},{"format":"unknown"},{"maps":[]},{"maps":["two_islands","two_islands"]},{"count":true},{"count":12},{"preset":"unknown"}]:
		var invalid := configuration(3)
		invalid.merge(patch,true)
		check(not Config.validate(invalid).ok,"Reject invalid configuration option "+str(patch))
	for count in [1,9]:
		check(not Config.validate(configuration(count)).ok,"Reject participant count outside 2–8")
	var controlled := configuration(2)
	controlled.entrants[0].name = "Bad"+String.chr(128)
	check(not Config.validate(controlled).ok,"Unicode control characters rejected in names")
	var event = Event.new()
	check(event.create(configuration(3)).ok,"Create test league")
	var before: Dictionary = event.snapshot()
	var bad := configuration(3)
	bad.entrants[1].name = " team 1 "
	check(not event.create(bad).ok and event.snapshot()==before,"Duplicate normalized names rejected atomically")
	bad = configuration(3)
	bad.count = 3
	check(not Config.validate(bad).ok,"Unequal teams rejected")
	bad = configuration(3)
	bad.maps = ["unknown"]
	check(not Config.validate(bad).ok,"Unknown arena rejected")
	check(event.update_draft(configuration(4)).ok,"Draft remains editable")
	var launched: Dictionary = event.launch(event.ready_ids()[0])
	check(not event.update_draft(configuration(3)).ok,"Launched rules frozen")
	check(event.rename_entrant("entrant_1","Żółwie").ok,"Rename during event")
	check(event.record(launched.token,1).ok,"First league result")
	check(event.correct(launched.token.fixture_id,0).ok,"Correct league result")
	var played := 0
	var points := 0
	for row in event.standings():
		played += row.played
		points += row.points
	check(played==2 and points==2,"Draw correction replaces victory points")
	before = event.snapshot()
	bad = before.duplicate(true)
	bad.results.append(bad.results[0].duplicate())
	check(not event.restore(bad).ok and event.snapshot()==before,"Duplicate results restore is atomic")
	var table_event = Event.new()
	table_event.create(configuration(3))
	while not table_event.is_complete():
		var launch: Dictionary = table_event.launch(table_event.ready_ids()[0])
		table_event.record(launch.token,0)
	check(table_event.standings()[0].id=="entrant_1" and table_event.standings()[0].points==2,"Full tie resolves by stable seeding")
	check(table_event.report().contains("Team 1"),"User report contains participants")
	# Hand-calculated 3-way cycle: each has 3 points and one win, seeding resolves.
	var cycle = Event.new()
	cycle.create(configuration(3))
	while not cycle.is_complete():
		var launch: Dictionary = cycle.launch(cycle.ready_ids()[0])
		var a: String = launch.fixture.a
		var b: String = launch.fixture.b
		var winner := "entrant_1" if [a,b].has("entrant_1") and [a,b].has("entrant_2") else "entrant_2" if [a,b].has("entrant_2") else "entrant_3"
		cycle.record(launch.token,1 if a==winner else 2)
	var cycle_rows: Array = cycle.standings()
	check(cycle_rows[0].id=="entrant_1" and cycle_rows[1].id=="entrant_2" and cycle_rows[2].id=="entrant_3","Three-way head-to-head cycle resolved by seeding")
	check(cycle_rows[0].head_points==3 and cycle_rows[1].head_points==3 and cycle_rows[2].head_points==3,"Mini-table counts only tied group results")
	before = cycle.snapshot()
	bad = before.duplicate(true)
	bad.results[1].attempt = bad.results[0].attempt
	check(not cycle.restore(bad).ok,"Duplicate historical attempts rejected")
	bad = before.duplicate(true)
	bad.next_attempt = 1.5
	check(not cycle.restore(bad).ok,"Fractional attempt rejected")
	var interrupted = Event.new()
	interrupted.create(configuration(3,"knockout"))
	var initial: Dictionary = interrupted.launch(interrupted.ready_ids()[0])
	interrupted.record(initial.token,0)
	check(Event.new().restore(interrupted.snapshot()).ok,"Draw-only knockout resumes")
	var retried: Dictionary = interrupted.launch(initial.token.fixture_id)
	check(Event.new().restore(interrupted.snapshot()).ok,"Active drawn replay resumes")
	var future_draw: Dictionary = interrupted.snapshot()
	future_draw.last_draw.attempt = 3
	future_draw.next_attempt = 4
	check(not Event.new().restore(future_draw).ok,"Draw must precede the current replay attempt")
	check(interrupted.abandon(retried.token).ok and interrupted.snapshot().results.is_empty(),"Abandoned retry awards no result")
	var duel = Event.new()
	duel.create(configuration(4))
	var winners := {"entrant_1/entrant_2":"entrant_2","entrant_1/entrant_3":"entrant_1","entrant_1/entrant_4":"entrant_4","entrant_2/entrant_3":"entrant_3","entrant_2/entrant_4":"entrant_4","entrant_3/entrant_4":"entrant_3"}
	while not duel.is_complete():
		var launch: Dictionary = duel.launch(duel.ready_ids()[0])
		var pair := [launch.fixture.a,launch.fixture.b]
		pair.sort()
		var winner: String = winners["/".join(pair)]
		duel.record(launch.token,1 if launch.fixture.a==winner else 2)
	var duel_rows: Array = duel.standings()
	check(duel_rows[0].id=="entrant_3" and duel_rows[1].id=="entrant_4" and duel_rows[2].id=="entrant_2" and duel_rows[3].id=="entrant_1","Direct encounter outranks seeding in two tied pairs")
	var impossible = Event.new()
	impossible.create(configuration(3))
	bad = impossible.snapshot()
	bad.frozen = true
	check(not impossible.restore(bad).ok,"Frozen event requires a historical launch")
	bad = cycle.snapshot()
	var first_attempt: int = bad.results[0].attempt
	bad.results[0].attempt = bad.results[1].attempt
	bad.results[1].attempt = first_attempt
	check(not cycle.restore(bad).ok,"Historical attempts must increase monotonically")
	print("competition19: ","PASS" if failures==0 else "FAIL", " failures=",failures)
	quit(0 if failures==0 else 1)
