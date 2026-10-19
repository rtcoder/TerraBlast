extends RefCounted
static func generate(config: Dictionary) -> Array:
	if config.format=="knockout": return _knockout(config)
	var wheel := []
	for row in config.entrants: wheel.append(row.id)
	if wheel.size()%2: wheel.append("")
	var n: int = config.entrants.size()
	var modulus := n if n%2 else n+1
	var out := []
	for round_index in wheel.size()-1:
		for j in wheel.size()/2:
			var a: String = wheel[j]
			var b: String = wheel[wheel.size()-1-j]
			if a.is_empty() or b.is_empty(): continue
			var ai := _entrant_index(config,a)
			var bi := _entrant_index(config,b)
			if (bi-ai+modulus)%modulus>modulus/2:
				var swap := a
				a = b
				b = swap
			out.append(_fixture("league_%d" % out.size(),round_index,out.size(),a,b,"","",config))
		wheel.insert(1,wheel.pop_back())
	if config.format=="double_league":
		var first_leg := out.duplicate(true)
		for fixture in first_leg:
			out.append(_fixture("league_%d" % out.size(),fixture.round+wheel.size()-1,out.size(),fixture.b,fixture.a,"","",config))
	return out
static func _entrant_index(config: Dictionary, id: String) -> int:
	for i in config.entrants.size():
		if config.entrants[i].id==id: return i
	return -1
static func _fixture(id: String, round_index: int, index: int, a: String, b: String, source_a: String, source_b: String, config: Dictionary) -> Dictionary:
	return {"id":id,"round":round_index,"index":index,"a":a,"b":b,"source_a":source_a,"source_b":source_b,"map":config.maps[index%config.maps.size()]}
static func _knockout(config: Dictionary) -> Array:
	var slots := 2
	while slots<config.entrants.size(): slots *= 2
	var seeds := [0,1]
	while seeds.size()<slots:
		var expanded := []
		for seed in seeds:
			expanded.append(seed)
			expanded.append(seeds.size()*2-1-seed)
		seeds = expanded
	var level := []
	for seed in seeds: level.append({"entrant":config.entrants[seed].id if seed<config.entrants.size() else "","source":""})
	var out := []
	var round_index := 0
	while level.size()>1:
		var next := []
		for j in range(0,level.size(),2):
			var a: Dictionary = level[j]
			var b: Dictionary = level[j+1]
			if a.entrant=="" and a.source=="": next.append(b); continue
			if b.entrant=="" and b.source=="": next.append(a); continue
			var id := "cup_%d" % out.size()
			out.append(_fixture(id,round_index,out.size(),a.entrant,b.entrant,a.source,b.source,config))
			next.append({"entrant":"","source":id})
		level = next
		round_index += 1
	return out
static func resolve(fixtures: Array, results: Array) -> Array:
	var winners := {}
	var out := fixtures.duplicate(true)
	for fixture in out:
		if not fixture.source_a.is_empty(): fixture.a = winners.get(fixture.source_a,"")
		if not fixture.source_b.is_empty(): fixture.b = winners.get(fixture.source_b,"")
		for result in results:
			if result.id==fixture.id and result.winner_team in [1,2]: winners[fixture.id] = fixture.a if result.winner_team==1 else fixture.b
	return out
static func ready(fixtures: Array, results: Array) -> Array:
	var done := {}
	for result in results: done[result.id] = true
	var round_index := 1000
	var ready_ids := []
	for fixture in fixtures:
		if done.has(fixture.id): continue
		round_index = mini(round_index,fixture.round)
	for fixture in fixtures:
		if not done.has(fixture.id) and fixture.round==round_index and not fixture.a.is_empty() and not fixture.b.is_empty(): ready_ids.append(fixture.id)
	return ready_ids
