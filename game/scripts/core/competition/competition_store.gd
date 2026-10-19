extends RefCounted
const Event = preload("res://scripts/core/competition/competition_event.gd")
const Config = preload("res://scripts/core/competition/competition_config.gd")
const Session = preload("res://scripts/core/replay/session_store.gd")
const Replay = preload("res://scripts/core/replay/match_replay.gd")
const Factory = preload("res://scripts/core/rules/match_factory.gd")
const Registry = preload("res://scripts/core/maps/map_registry.gd")
const DEFAULT_PATH := "user://local_competition.json"
const MAX_BYTES := Session.MAX_BYTES+262144
static func encode(event_snapshot: Dictionary, match_payload: Dictionary = {}) -> Dictionary:
	var payload := {"format":"terrablast_competition","version":1,"event":event_snapshot.duplicate(true),"match":match_payload.duplicate(true)}
	var checked := decode(payload)
	if not checked.ok: return checked
	return {"ok":true,"payload":payload}
static func decode(payload: Variant) -> Dictionary:
	if not Config.keys(payload,["format","version","event","match"]) or payload.format!="terrablast_competition" or not Config.integer(payload.version,1,1) or not payload.match is Dictionary: return Config.failure("Invalid competition file format or version")
	var event := Event.new()
	var checked := event.restore(payload.event)
	if not checked.ok: return checked
	var snapshot := event.snapshot()
	if snapshot.active.is_empty():
		if not payload.match.is_empty(): return Config.failure("Match snapshot without active fixture")
		return {"ok":true,"event":event,"match":{}}
	if not Config.keys(payload.match,["token","payload"]) or not Config.keys(payload.match.token,["fixture_id","attempt"]): return Config.failure("Invalid active match snapshot")
	var token: Dictionary = payload.match.token
	if token.fixture_id!=snapshot.active.fixture_id or not Config.integer(token.attempt,1,1000000000) or int(token.attempt)!=snapshot.active.attempt: return Config.failure("Active match token does not match event")
	var decoded := Session.decode(payload.match.payload)
	if not decoded.ok: return Config.failure("Invalid competition session: "+decoded.reason)
	if decoded.options!={"mode":"hotseat","difficulty":"normal","human_team":1}: return Config.failure("Competition session must use local hotseat")
	var fixture := event.fixture_by_id(snapshot.active.fixture_id)
	var canonical = Factory.create_match(snapshot.config.count,Registry.PATHS[fixture.map],snapshot.config.preset)
	if canonical==null: return Config.failure("Cannot validate fixture configuration")
	var runner: RefCounted = decoded.runner
	# Mutable terrain, positions and inventory are intentionally not compared.
	# These checks validate configuration compatibility, not terrain provenance.
	if runner.world.size!=canonical.world.size or Replay.properties(runner.rules)!=Replay.properties(canonical.rules) or runner.weapons.size()!=canonical.weapons.size() or runner.state.players.size()!=canonical.state.players.size(): return Config.failure("Session does not match fixture dimensions, rules or roster")
	for id in canonical.weapons:
		if not runner.weapons.has(id) or Replay.properties(runner.weapons[id])!=Replay.properties(canonical.weapons[id]): return Config.failure("Session weapon configuration differs from fixture")
	for index in canonical.state.players.size():
		var actual = runner.state.players[index]
		var expected = canonical.state.players[index]
		if actual.player_id!=expected.player_id or actual.team_id!=expected.team_id: return Config.failure("Session team assignment differs from fixture")
	decoded.token = snapshot.active.duplicate()
	return {"ok":true,"event":event,"match":decoded}
static func save(path: String, event: RefCounted, match_payload: Dictionary = {}) -> Dictionary:
	var encoded := encode(event.snapshot(),match_payload)
	if not encoded.ok: return encoded
	var content := JSON.stringify(encoded.payload,"",true,true)
	if content.to_utf8_buffer().size()>MAX_BYTES: return Config.failure("Competition file exceeds size limit")
	var temporary := path+".tmp-%d-%d" % [OS.get_process_id(),Time.get_ticks_usec()]
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file==null: return Config.failure("Cannot write competition file: "+error_string(FileAccess.get_open_error()))
	file.store_string(content)
	file.flush()
	var error := file.get_error()
	file.close()
	if error==OK: error = DirAccess.rename_absolute(temporary,path)
	if error!=OK:
		DirAccess.remove_absolute(temporary)
		return Config.failure("Cannot replace competition file: "+error_string(error))
	return {"ok":true}
static func load(path: String) -> Dictionary:
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null: return Config.failure("No saved competition or file is unavailable")
	if file.get_length()>MAX_BYTES:
		file.close()
		return Config.failure("Competition file exceeds size limit")
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	file.close()
	if error!=OK: return Config.failure("Invalid competition JSON")
	return decode(parser.data)
