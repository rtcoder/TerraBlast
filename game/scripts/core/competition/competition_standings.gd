extends RefCounted
const Schedule = preload("res://scripts/core/competition/competition_schedule.gd")
static func calculate(config: Dictionary, results: Array) -> Array:
	if config.format=="knockout": return []
	var rows := []
	var indexed := {}
	for entrant in config.entrants:
		var row := {"id":entrant.id,"name":entrant.name,"seed":entrant.seed,"rank":0,"played":0,"wins":0,"draws":0,"losses":0,"points":0,"head_points":0,"tiebreak":"points"}
		rows.append(row)
		indexed[row.id] = row
	var fixtures := Schedule.generate(config)
	for result in results:
		var fixture: Dictionary = _find(fixtures,result.id)
		if fixture.is_empty(): continue
		var a: Dictionary = indexed[fixture.a]
		var b: Dictionary = indexed[fixture.b]
		a.played += 1
		b.played += 1
		if result.winner_team==0:
			a.draws += 1; b.draws += 1; a.points += 1; b.points += 1
		else:
			var winner: Dictionary = a if result.winner_team==1 else b
			var loser: Dictionary = b if result.winner_team==1 else a
			winner.wins += 1; winner.points += 3; loser.losses += 1
	for result in results:
		var fixture: Dictionary = _find(fixtures,result.id)
		if fixture.is_empty(): continue
		var a: Dictionary = indexed[fixture.a]
		var b: Dictionary = indexed[fixture.b]
		if a.points!=b.points: continue
		if result.winner_team==0: a.head_points += 1; b.head_points += 1
		elif result.winner_team==1: a.head_points += 3
		else: b.head_points += 3
	rows.sort_custom(func(a,b):
		if a.points!=b.points: return a.points>b.points
		if a.head_points!=b.head_points: return a.head_points>b.head_points
		if a.wins!=b.wins: return a.wins>b.wins
		return a.seed<b.seed)
	for i in rows.size():
		rows[i].rank = i+1
		for other in rows:
			if other.id==rows[i].id or other.points!=rows[i].points: continue
			if other.head_points!=rows[i].head_points: rows[i].tiebreak = "head-to-head points"
			elif other.wins!=rows[i].wins: rows[i].tiebreak = "wins"
			else: rows[i].tiebreak = "seeding"; break
	return rows
static func _find(fixtures: Array, id: String) -> Dictionary:
	for fixture in fixtures:
		if fixture.id==id: return fixture
	return {}
static func matrix(config: Dictionary, results: Array) -> Array:
	var fixtures := Schedule.resolve(Schedule.generate(config),results)
	var out := []
	for fixture in fixtures:
		var row := {"id":fixture.id,"a":fixture.a,"b":fixture.b,"round":fixture.round,"winner_team":-1}
		for result in results:
			if result.id==fixture.id: row.winner_team = result.winner_team
		out.append(row)
	return out
static func report(snapshot: Dictionary) -> String:
	var config: Dictionary = snapshot.config
	var text := "%s — %s\n" % [config.title,config.format]
	var names := {}
	for entrant in config.entrants: names[entrant.id] = entrant.name
	for row in calculate(config,snapshot.results):
		text += "%d. %s | M %d W %d D %d L %d | %d pts | %s\n" % [row.rank,row.name,row.played,row.wins,row.draws,row.losses,row.points,row.tiebreak]
	for fixture in Schedule.resolve(Schedule.generate(config),snapshot.results):
		for result in snapshot.results:
			if result.id!=fixture.id: continue
			text += "R%d %s vs %s — %s [%s]\n" % [fixture.round+1,names.get(fixture.a,"?"),names.get(fixture.b,"?"),"Draw" if result.winner_team==0 else names.get(fixture.a if result.winner_team==1 else fixture.b,"?"),fixture.map]
	return text
