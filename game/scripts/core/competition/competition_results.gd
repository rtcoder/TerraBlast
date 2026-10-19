extends RefCounted
const Config = preload("res://scripts/core/competition/competition_config.gd")
static func validate_result(value: Variant, fixture: Dictionary) -> Dictionary:
	if not Config.keys(value,["id","attempt","winner_team"]) or value.id!=fixture.id or not Config.integer(value.attempt,1,1000000000) or not Config.integer(value.winner_team,0,2): return Config.failure("Invalid match result")
	return {"ok":true,"result":{"id":value.id,"attempt":int(value.attempt),"winner_team":int(value.winner_team)}}
static func from_winner(fixture: Dictionary, token: Dictionary, winner_team: int) -> Dictionary:
	return validate_result({"id":fixture.id,"attempt":token.get("attempt",0),"winner_team":winner_team},fixture)
static func history(snapshot: Dictionary) -> Array:
	return snapshot.get("results",[]).duplicate(true)
