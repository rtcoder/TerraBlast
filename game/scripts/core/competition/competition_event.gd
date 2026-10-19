extends RefCounted
const Config = preload("res://scripts/core/competition/competition_config.gd")
const Schedule = preload("res://scripts/core/competition/competition_schedule.gd")
const Results = preload("res://scripts/core/competition/competition_results.gd")
const Standings = preload("res://scripts/core/competition/competition_standings.gd")
var _config := {}
var _results := []
var _active := {}
var _next_attempt := 1
var _frozen := false
var _last_draw := {}
func create(value: Variant) -> Dictionary:
	var checked := Config.validate(value)
	if not checked.ok: return checked
	_config = checked.config
	_results = []
	_active = {}
	_next_attempt = 1
	_frozen = false
	_last_draw = {}
	return {"ok":true}
func update_draft(value: Variant) -> Dictionary:
	if _frozen: return Config.failure("Competition rules are frozen after the first launch")
	return create(value)
func rename_entrant(id: String, name: String) -> Dictionary:
	var candidate := _config.duplicate(true)
	var found := false
	for entrant in candidate.get("entrants",[]):
		if entrant.id==id: entrant.name = name; found = true
	if not found: return Config.failure("Unknown participant")
	var checked := Config.validate(candidate)
	if checked.ok: _config = checked.config
	return checked
func snapshot() -> Dictionary:
	return {"config":_config.duplicate(true),"results":_results.duplicate(true),"active":_active.duplicate(true),"next_attempt":_next_attempt,"frozen":_frozen,"last_draw":_last_draw.duplicate(true)}
func fixtures() -> Array:
	return Schedule.resolve(Schedule.generate(_config),_results) if not _config.is_empty() else []
func ready_ids() -> Array:
	return [] if not _active.is_empty() else Schedule.ready(fixtures(),_results)
func fixture_by_id(id: String) -> Dictionary:
	for fixture in fixtures():
		if fixture.id==id: return fixture
	return {}
func launch(id: String) -> Dictionary:
	if not ready_ids().has(id) or _next_attempt>1000000000: return Config.failure("This match is not ready")
	_active = {"fixture_id":id,"attempt":_next_attempt}
	_next_attempt += 1
	_frozen = true
	return {"ok":true,"token":_active.duplicate(),"fixture":fixture_by_id(id),"config":_config.duplicate(true)}
func record(token: Dictionary, winner_team: int) -> Dictionary:
	if _active.is_empty() or token!=_active or winner_team not in [0,1,2]: return Config.failure("Stale or invalid result token")
	var result := Results.from_winner(fixture_by_id(token.fixture_id),token,winner_team)
	if not result.ok: return result
	_active = {}
	if _config.format=="knockout" and winner_team==0:
		_last_draw = result.result
		return {"ok":true,"completed":false,"draw_replay":true}
	_results.append(result.result)
	_last_draw = {}
	return {"ok":true,"completed":is_complete(),"draw_replay":false}
func abandon(token: Dictionary) -> Dictionary:
	if _active.is_empty() or token!=_active: return Config.failure("Stale active match")
	_active = {}
	return {"ok":true}
func correct(id: String, winner_team: int) -> Dictionary:
	if _config.get("format")=="knockout" or not _active.is_empty() or winner_team not in [0,1,2]: return Config.failure("Correction requires a league with no active match")
	for result in _results:
		if result.id==id:
			result.winner_team = winner_team
			return {"ok":true}
	return Config.failure("No completed result to correct")
func is_complete() -> bool:
	return not _config.is_empty() and _results.size()==fixtures().size()
func champion() -> String:
	if not is_complete(): return ""
	if _config.format!="knockout": return standings()[0].id
	var final: Dictionary = fixtures().back()
	for result in _results:
		if result.id==final.id: return final.a if result.winner_team==1 else final.b
	return ""
func standings() -> Array: return Standings.calculate(_config,_results) if not _config.is_empty() else []
func report() -> String:
	if _config.is_empty(): return ""
	var text := Standings.report(snapshot())
	if is_complete(): text += "Champion: "+name_for(champion())+"\n"
	return text
func name_for(id: String) -> String:
	for entrant in _config.get("entrants",[]):
		if entrant.id==id: return entrant.name
	return "To be decided"
func restore(value: Variant) -> Dictionary:
	if not Config.keys(value,["config","results","active","next_attempt","frozen","last_draw"]): return Config.failure("Invalid event fields")
	if not value.results is Array or value.results.size()>56 or not value.active is Dictionary or not value.last_draw is Dictionary or not value.frozen is bool or not Config.integer(value.next_attempt,1,1000000001): return Config.failure("Invalid event state")
	var candidate = get_script().new()
	var checked: Dictionary = candidate.create(value.config)
	if not checked.ok: return checked
	var attempts := {}
	var max_attempt := 0
	for result in value.results:
		if not result is Dictionary or not result.get("id") is String: return Config.failure("Invalid result")
		var fixture: Dictionary = candidate.fixture_by_id(result.id)
		if fixture.is_empty() or not candidate.ready_ids().has(result.id): return Config.failure("Result has an impossible pairing or round")
		checked = Results.validate_result(result,fixture)
		if not checked.ok or (candidate._config.format=="knockout" and int(result.winner_team)==0) or attempts.has(int(result.attempt)) or int(result.attempt)<=max_attempt: return Config.failure("Invalid or duplicate final result")
		attempts[int(result.attempt)] = true
		max_attempt = maxi(max_attempt,int(result.attempt))
		candidate._results.append(checked.result)
	var latest_result_attempt := max_attempt
	if not value.active.is_empty():
		if not Config.keys(value.active,["fixture_id","attempt"]) or not value.active.fixture_id is String or not Config.integer(value.active.attempt,1,1000000000) or not candidate.ready_ids().has(value.active.fixture_id) or attempts.has(int(value.active.attempt)) or int(value.active.attempt)<=max_attempt: return Config.failure("Invalid active match")
		candidate._active = {"fixture_id":value.active.fixture_id,"attempt":int(value.active.attempt)}
		attempts[int(value.active.attempt)] = true
		max_attempt = maxi(max_attempt,int(value.active.attempt))
	if not value.last_draw.is_empty():
		var draw: Variant = value.last_draw
		if candidate._config.format!="knockout" or not draw.get("id") is String: return Config.failure("Invalid draw replay")
		var fixture: Dictionary = candidate.fixture_by_id(draw.id)
		if fixture.is_empty() or not Schedule.ready(candidate.fixtures(),candidate._results).has(draw.id): return Config.failure("Impossible draw replay")
		checked = Results.validate_result(draw,fixture)
		if not checked.ok or draw.winner_team!=0 or attempts.has(int(draw.attempt)) or int(draw.attempt)<=latest_result_attempt: return Config.failure("Invalid draw replay result")
		if not candidate._active.is_empty() and int(draw.attempt)>=candidate._active.attempt: return Config.failure("Draw must precede the active replay attempt")
		candidate._last_draw = checked.result
		max_attempt = maxi(max_attempt,int(draw.attempt))
	if (value.frozen and int(value.next_attempt)==1) or int(value.next_attempt)<=max_attempt or (not value.frozen and (not value.results.is_empty() or not value.active.is_empty() or not value.last_draw.is_empty() or int(value.next_attempt)!=1)): return Config.failure("Invalid launch sequence")
	_config = candidate._config
	_results = candidate._results
	_active = candidate._active
	_last_draw = candidate._last_draw
	_next_attempt = int(value.next_attempt)
	_frozen = value.frozen
	return {"ok":true}
